using Miao.App.Boot;
using Miao.Data;
using Miao.Sites;
using Miao.Software.Catalog;
using Miao.Software.Dev.Claude;
using Miao.Software.Jobs;
using Miao.Software.Dev.Volta;
using Miao.Utilities;

namespace Miao.App;

/// <summary>
/// 进程级服务：数据库、软件目录、网站、工具集、Volta、Claude、JobRunner。
/// </summary>
public static class AppServices
{
    private static readonly object Gate = new();
    private static AppDatabase? _db;
    private static SoftwareCatalog? _software;
    private static SiteService? _sites;
    private static UtilitiesService? _utilities;
    private static VoltaPackageService? _volta;
    private static ClaudeCodeService? _claude;
    private static JobRunner? _jobs;
    private static SilentTaskRunner? _silent;
    private static bool _updateProbeStarted;
    private static bool _postBootSilentStarted;

    /// <summary>本地 SQLite。</summary>
    public static AppDatabase Db
    {
        get { EnsureInitialized(); return _db!; }
    }

    /// <summary>软件目录。</summary>
    public static SoftwareCatalog Software
    {
        get { EnsureInitialized(); return _software!; }
    }

    /// <summary>常用网站。</summary>
    public static SiteService Sites
    {
        get { EnsureInitialized(); return _sites!; }
    }

    /// <summary>工具集。</summary>
    public static UtilitiesService Utilities
    {
        get { EnsureInitialized(); return _utilities!; }
    }

    /// <summary>Volta 包版本清单（node / pnpm / yarn）。</summary>
    public static VoltaPackageService Volta
    {
        get { EnsureInitialized(); return _volta!; }
    }

    /// <summary>Claude Code 配置与插件。</summary>
    public static ClaudeCodeService Claude
    {
        get { EnsureInitialized(); return _claude!; }
    }

    /// <summary>任务执行器（可在完整初始化前创建）。</summary>
    public static JobRunner Jobs
    {
        get { return EnsureJobRunner(); }
    }

    /// <summary>进主壳后的静默任务队列。</summary>
    public static SilentTaskRunner Silent
    {
        get
        {
            EnsureJobRunner();
            return _silent!;
        }
    }

    /// <summary>核心服务是否已就绪。</summary>
    public static bool IsInitialized
    {
        get
        {
            lock (Gate)
            {
                return _db is not null && _software is not null && _jobs is not null;
            }
        }
    }

    /// <summary>
    /// 仅确保 <see cref="JobRunner"/> 可用（出窗后即可挂桥，不必等库初始化）。
    /// </summary>
    public static JobRunner EnsureJobRunner()
    {
        if (_jobs is not null && _silent is not null) return _jobs;
        lock (Gate)
        {
            _jobs ??= new JobRunner();
            _silent ??= new SilentTaskRunner(maxConcurrency: 1);
            return _jobs;
        }
    }

    /// <summary>幂等初始化（无进度回调）。</summary>
    public static void EnsureInitialized()
    {
        var result = InitializeWithProgress(null);
        if (result.Fatal)
            throw new InvalidOperationException(result.Message ?? "启动初始化失败");
    }

    /// <summary>
    /// 分步初始化：任务数等比进度；单任务超时 + 失败重试；
    /// 核心失败达上限 → <see cref="BootInitResult.Fatal"/>；数据失败达上限 → 跳过并继续（降级）。
    /// </summary>
    /// <param name="report">
    /// stage / message / percent。
    /// stage=<c>log</c> 时仅日志（percent 可忽略）；其余为进度。
    /// </param>
    public static BootInitResult InitializeWithProgress(Action<string, string, int>? report)
    {
        if (IsInitialized)
        {
            report?.Invoke("ready", "服务已就绪", 100);
            return BootInitResult.AlreadyReady();
        }

        lock (Gate)
        {
            if (_db is not null && _software is not null && _jobs is not null)
            {
                report?.Invoke("ready", "服务已就绪", 100);
                return BootInitResult.AlreadyReady();
            }
        }

        var degraded = false;
        var maxRetry = BootOptions.MaxRetryCount;
        var timeout = BootOptions.TaskTimeout;
        var seedsMessage = "种子已是最新";
        var dbMessage = AppPaths.IsDevDataProfile
            ? "打开本地数据库（开发库已重建）"
            : "打开本地数据库";

        void Log(string message) => report?.Invoke("log", message, 0);

        bool RunTask(string name, BootTaskSeverity severity, Action action, out string? failMessage)
        {
            failMessage = null;
            for (var attempt = 1; attempt <= maxRetry; attempt++)
            {
                try
                {
                    RunWithTimeout(action, timeout);
                    if (attempt > 1)
                        Log($"{name}：第 {attempt} 次成功");
                    return true;
                }
                catch (Exception ex)
                {
                    failMessage = ex.Message;
                    var detail = ex is TimeoutException
                        ? $"超时（>{BootOptions.TaskTimeoutSeconds}s）"
                        : ex.Message;
                    if (attempt < maxRetry)
                    {
                        Log($"{name} 失败，重试 {attempt}/{maxRetry}：{detail}");
                        if (severity == BootTaskSeverity.Critical)
                            ClearPartialCore();
                    }
                    else
                    {
                        Log($"{name} 已达重试上限（{maxRetry}）：{detail}");
                    }
                }
            }

            return false;
        }

        // —— 先执行开库/种子（进度在知道探测总数后再等比汇报）——
        if (!RunTask(
                "打开数据库",
                BootTaskSeverity.Critical,
                () =>
                {
                    lock (Gate)
                    {
                        AppPaths.ResetDevDatabaseIfNeeded();
                        _db?.Dispose();
                        _db = new AppDatabase(AppPaths.DatabasePath);
                    }
                },
                out var dbErr))
        {
            return BootInitResult.FatalFail(dbErr ?? "打开数据库失败");
        }

        Log(dbMessage);

        if (!RunTask(
                "应用种子",
                BootTaskSeverity.Data,
                () =>
                {
                    lock (Gate)
                    {
                        if (_db is null) throw new InvalidOperationException("数据库未打开");
                        var applied = SeedLoader.ApplyIfNeeded(_db);
                        seedsMessage = applied ? "已应用种子数据" : "种子已是最新";
                    }
                },
                out var seedErr))
        {
            degraded = true;
            seedsMessage = $"种子跳过：{seedErr}";
            Log(seedsMessage);
        }
        else
        {
            Log(seedsMessage);
        }

        IReadOnlyList<string> toolIds;
        lock (Gate)
        {
            toolIds = _db!.ListSoftware().Select(r => r.Id).ToList();
        }

        var total = 3 + toolIds.Count;
        var done = 0;

        void Tick(string stage, string message)
        {
            done++;
            var percent = total <= 0
                ? 100
                : (int)Math.Clamp(Math.Round(100.0 * done / total), 0, 100);
            report?.Invoke(stage, message, percent);
        }

        // 等比进度从这里开始（开库/种子已完成，立刻记两格）
        Tick("database", dbMessage);
        Tick("seeds", seedsMessage);

        if (!RunTask(
                "初始化服务",
                BootTaskSeverity.Critical,
                () =>
                {
                    lock (Gate)
                    {
                        if (_db is null) throw new InvalidOperationException("数据库未打开");
                        _claude = new ClaudeCodeService();
                        _volta = new VoltaPackageService(_db);
                        _software = new SoftwareCatalog(_db, _claude, _volta);
                        _sites = new SiteService(_db);
                        _utilities = new UtilitiesService(_db);
                        _jobs ??= new JobRunner();
                    }
                },
                out var svcErr))
        {
            ClearPartialCore();
            return BootInitResult.FatalFail(svcErr ?? "初始化服务失败");
        }

        Tick("services", "初始化服务");

        SoftwareCatalog catalog;
        lock (Gate)
        {
            catalog = _software!;
            // 服务创建后列表仍一致
            toolIds = _db!.ListSoftware().Select(r => r.Id).ToList();
        }

        for (var i = 0; i < toolIds.Count; i++)
        {
            var id = toolIds[i];
            var label = $"探测 {id}";
            if (!RunTask(
                    label,
                    BootTaskSeverity.Data,
                    () => catalog.ProbeTool(id, probeUpdates: false),
                    out _))
            {
                degraded = true;
                Tick("catalog", $"{label}（{i + 1}/{toolIds.Count}）已跳过");
            }
            else
            {
                Tick("catalog", $"{label}（{i + 1}/{toolIds.Count}）");
            }
        }

        report?.Invoke(
            "ready",
            degraded ? "服务就绪（部分数据任务已跳过）" : "服务就绪",
            100);
        return BootInitResult.Success(degraded);
    }

    /// <summary>主壳就绪后：更新探测 + 版本缓存等静默任务。</summary>
    public static void StartPostBootSilentTasks()
    {
        StartBackgroundUpdateProbe();
        EnqueueVersionCacheTasks();
    }

    /// <summary>主壳就绪后后台补探更新（不阻塞启动）。</summary>
    public static void StartBackgroundUpdateProbe()
    {
        if (_updateProbeStarted || _software is null) return;
        _updateProbeStarted = true;
        var catalog = _software;
        _ = Task.Run(() =>
        {
            try { catalog.ProbeUpdatesOnly(); }
            catch { /* 静默：不影响主流程 */ }
        });
    }

    /// <summary>入队 Node 版本目录增量同步（打开后执行）。</summary>
    public static void EnqueueVersionCacheTasks()
    {
        if (_postBootSilentStarted) return;
        if (_volta is null) return;
        _postBootSilentStarted = true;

        var volta = _volta;
        Silent.Enqueue(
            "cache.versions.node",
            "同步 Node.js 版本目录",
            async (progress, ct) =>
            {
                progress.Report(8);
                await volta.ListAsync("node", ltsOnly: false, forceRemote: true, ct).ConfigureAwait(false);
                progress.Report(100);
            });
    }

    private static void ClearPartialCore()
    {
        lock (Gate)
        {
            try { _db?.Dispose(); } catch { /* ignore */ }
            _db = null;
            _software = null;
            _sites = null;
            _utilities = null;
            _volta = null;
            _claude = null;
            _postBootSilentStarted = false;
        }
    }

    /// <summary>在独立线程执行并施加超时。</summary>
    private static void RunWithTimeout(Action action, TimeSpan timeout)
    {
        var task = Task.Run(action);
        try
        {
            if (!task.Wait(timeout))
                throw new TimeoutException($"超过 {timeout.TotalSeconds:0} 秒未完成");
            task.GetAwaiter().GetResult();
        }
        catch (AggregateException ae)
        {
            throw ae.Flatten().InnerException ?? ae;
        }
    }
}
