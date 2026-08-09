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
    private static bool _postBootSilentStarted;
    /// <summary>本次启动开始时已有 <c>package_versions</c> 缓存的工具 id（仅这些会进后台增量）。</summary>
    private static HashSet<string>? _versionCacheExistedAtBoot;

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
    /// 含安装态校准；若版本目录无缓存则首次远端同步也在此完成。
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

        bool RunTask(
            string name,
            BootTaskSeverity severity,
            Action action,
            out string? failMessage,
            TimeSpan? timeoutOverride = null)
        {
            failMessage = null;
            var taskTimeout = timeoutOverride ?? timeout;
            for (var attempt = 1; attempt <= maxRetry; attempt++)
            {
                try
                {
                    RunWithTimeout(action, taskTimeout);
                    if (attempt > 1)
                        Log($"{name}：第 {attempt} 次成功");
                    return true;
                }
                catch (Exception ex)
                {
                    failMessage = ex.Message;
                    var detail = ex is TimeoutException
                        ? $"超时（>{taskTimeout.TotalSeconds:0}s）"
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

        // 核心 3 + 安装态 1 + 版本目录（无缓存时）1
        // 版本目录步在服务就绪后确定是否需要，先按上限占位，跳过时仍 Tick 说明。
        const int total = 5;
        var done = 0;

        void Tick(string stage, string message)
        {
            done++;
            var percent = (int)Math.Clamp(Math.Round(100.0 * done / total), 0, 100);
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
        _ = toolIds;

        // 1) 安装态：本地探测，进主壳前完成，避免进工具再等静默任务
        if (!RunTask(
                "校准工具安装状态",
                BootTaskSeverity.Data,
                () =>
                {
                    // maxAge=0：每次启动都校准，保证进工具即见准确已装/未装
                    _software!.CalibrateInstallStates(
                        progress: null,
                        cancellationToken: CancellationToken.None,
                        maxAge: TimeSpan.Zero);
                },
                out var installErr))
        {
            degraded = true;
            Log($"安装态校准跳过：{installErr}");
            Tick("detect.install", $"安装态校准跳过：{installErr}");
        }
        else
        {
            Tick("detect.install", "已校准工具安装状态");
        }

        // 2) 远端版本目录：仅「启动时库中尚无缓存」首次拉取；已有缓存的留给后台增量（不含本次刚灌入的）
        var versionTools = new[] { "node", "pnpm", "yarn" };
        var hadVersionCacheAtBoot = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var firstVersionTools = new List<string>();
        foreach (var id in versionTools)
        {
            if (_db!.ListPackageVersions(id).Count > 0)
                hadVersionCacheAtBoot.Add(id);
            else
                firstVersionTools.Add(id);
        }

        lock (Gate)
        {
            _versionCacheExistedAtBoot = hadVersionCacheAtBoot;
        }

        if (firstVersionTools.Count == 0)
        {
            Tick("cache.versions", "版本目录已有缓存，跳过首次同步");
        }
        else if (!RunTask(
                     "同步版本目录（首次）",
                     BootTaskSeverity.Data,
                     () =>
                     {
                         foreach (var id in firstVersionTools)
                         {
                             Log($"首次同步版本目录：{id}");
                             _volta!.ListAsync(id, ltsOnly: false, forceRemote: true)
                                 .GetAwaiter()
                                 .GetResult();
                         }
                     },
                     out var verErr,
                     timeoutOverride: TimeSpan.FromMinutes(3)))
        {
            degraded = true;
            Log($"版本目录首次同步跳过：{verErr}");
            Tick("cache.versions", $"版本目录首次同步跳过：{verErr}");
        }
        else
        {
            Tick("cache.versions", $"已首次同步版本目录（{string.Join("/", firstVersionTools)}）");
        }

        report?.Invoke(
            "ready",
            degraded
                ? "服务就绪（部分数据任务已跳过；更新检查将在后台进行）"
                : "服务就绪（更新检查将在后台进行）",
            100);
        return BootInitResult.Success(degraded);
    }

    /// <summary>
    /// 主壳就绪后：更新探测；已有缓存的版本目录做后台增量；Claude 插件目录视状态入队。
    /// 安装态与「首次」版本目录已在 <see cref="InitializeWithProgress"/> 完成。
    /// </summary>
    public static void StartPostBootSilentTasks()
    {
        if (_postBootSilentStarted) return;
        if (_volta is null || _software is null || _db is null) return;
        _postBootSilentStarted = true;

        var catalog = _software;
        var volta = _volta;

        Silent.Enqueue(
            "detect.update",
            "检查工具更新",
            async (progress, ct) =>
            {
                await Task.Run(
                        () =>
                        {
                            progress.Report(8);
                            catalog.ProbeUpdatesOnly();
                            progress.Report(100);
                        },
                        ct)
                    .ConfigureAwait(false);
            });

        // 仅对「启动时已有缓存」的包做后台增量；本次刚首次灌入的不入队
        EnqueueVersionCacheIfExistedAtBoot(volta, "node", "cache.versions.node", "同步 Node.js 版本目录");
        EnqueueVersionCacheIfExistedAtBoot(volta, "pnpm", "cache.versions.pnpm", "同步 pnpm 版本目录");
        EnqueueVersionCacheIfExistedAtBoot(volta, "yarn", "cache.versions.yarn", "同步 Yarn 版本目录");
        EnqueueClaudePluginCache();
    }

    /// <summary>
    /// 进入工具箱后：Claude 已安装且已初始化时，后台同步插件目录并校验安装态后落库。
    /// </summary>
    public static void EnqueueClaudePluginCache()
    {
        if (_claude is null || _db is null) return;
        var claude = _claude;
        var db = _db;

        var state = db.GetToolState("claude-code");
        var installed =
            state is not null
            && string.Equals(state.Status, "installed", StringComparison.OrdinalIgnoreCase);
        if (!installed) return;

        // 未初始化则跳过：无 marketplace / 无 DISABLE_LOGIN，同步无效
        if (!claude.IsInitialized(db)) return;

        Silent.Enqueue(
            "cache.claude.plugins",
            "同步 Claude 插件目录",
            async (progress, ct) =>
            {
                await Task.Run(
                        () =>
                        {
                            progress.Report(8);
                            var (ok, detail) = claude.SyncPluginCatalog(
                                db,
                                onStep: (_, pct) => progress.Report(Math.Clamp(pct, 8, 99)),
                                updateRemote: true);
                            if (!ok)
                                throw new InvalidOperationException(detail);
                            db.SetSetting("claude.initialized", "1");
                            progress.Report(100);
                        },
                        ct)
                    .ConfigureAwait(false);
            });
    }

    /// <summary>启动时已有该包版本缓存 → 入队后台增量同步。</summary>
    private static void EnqueueVersionCacheIfExistedAtBoot(
        VoltaPackageService volta,
        string toolId,
        string taskId,
        string title)
    {
        var existed = _versionCacheExistedAtBoot;
        if (existed is null || !existed.Contains(toolId)) return;
        EnqueueOneVersionCache(volta, toolId, taskId, title);
    }

    /// <summary>入队单个 Volta 包的远程增量同步。</summary>
    private static void EnqueueOneVersionCache(
        VoltaPackageService volta,
        string toolId,
        string taskId,
        string title)
    {
        Silent.Enqueue(
            taskId,
            title,
            async (progress, ct) =>
            {
                progress.Report(8);
                await volta.ListAsync(toolId, ltsOnly: false, forceRemote: true, ct).ConfigureAwait(false);
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
            _versionCacheExistedAtBoot = null;
        }
    }

    /// <summary>在独立线程执行并施加超时。</summary>
    /// <param name="action">要执行的工作。</param>
    /// <param name="timeout">超时时长。</param>
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
