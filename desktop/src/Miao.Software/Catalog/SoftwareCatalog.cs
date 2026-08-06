using System.Text.Json;
using Miao.Common.Jobs;
using Miao.Common.Software;
using Miao.Data;
using Miao.Software.Detect;
using Miao.Software.Jobs;
using Miao.Software.Dev.Claude;
using Miao.Software.Dev.Hermes;
using Miao.Software.Dev.TerminalBuddy;
using Miao.Software.Dev.Volta;
using Miao.Software.Install;

namespace Miao.Software.Catalog;

/// <summary>
/// 软件目录：从 DB（由 seeds 灌入）组装清单，并按 action.handler 调度到对应 Handler。
/// </summary>
public sealed class SoftwareCatalog
{
    private readonly AppDatabase _db;
    private readonly VoltaPackageService _volta;
    private readonly Dictionary<string, IToolActionHandler> _handlers;
    private List<SoftwareGroupDefinition> _groups = new();

    /// <summary>
    /// 创建目录并注册全部内置 Handler。
    /// </summary>
    /// <param name="db">应用数据库。</param>
    /// <param name="claude">Claude Code 服务。</param>
    /// <param name="volta">Volta 版本查询（目录展示默认/当前版）。</param>
    public SoftwareCatalog(AppDatabase db, ClaudeCodeService claude, VoltaPackageService volta)
    {
        _db = db;
        _volta = volta;
        var list = new IToolActionHandler[]
        {
            new InstallerLaunchHandler(),
            new WingetInstallHandler(),
            new WingetUninstallHandler(),
            new NpmGlobalInstallHandler(),
            new RegistryUninstallHandler(),
            new VoltaInstallHandler(),
            new VoltaUninstallHandler(),
            new VoltaSetDefaultHandler(),
            new VoltaPinHandler(),
            new ClaudeInstallHandler(),
            new ClaudeUninstallHandler(),
            new ClaudeInitHandler(claude),
            new ClaudeResetHandler(claude),
            new ClaudePluginInstallHandler(claude),
            new ClaudePluginUpdateHandler(claude),
            new ClaudePluginUninstallHandler(claude),
            new HermesInstallHandler(),
            new HermesUninstallHandler(),
            new TerminalBuddyInstallHandler(),
            new TerminalBuddyUninstallHandler(),
        };
        _handlers = list.ToDictionary(h => h.HandlerId, StringComparer.OrdinalIgnoreCase);
        ReloadGroupsFromSeeds();
    }

    /// <summary>返回已启用的一级分组（按 sort）。</summary>
    /// <param name="locale">界面语言，用于解析 nameKey。</param>
    public IReadOnlyList<CatalogGroupDto> GetGroups(string locale)
    {
        return _groups
            .Where(g => g.Enabled)
            .OrderBy(g => g.Sort)
            .Select(g => new CatalogGroupDto(
                g.Id,
                _db.T(locale, g.NameKey, FallbackGroupName(g.Id)),
                g.Sort))
            .ToList();
    }

    /// <summary>重新加载分组种子并对库中每条软件做探测。</summary>
    /// <param name="probeUpdates">是否探测更新（winget/网络）；启动期建议 false，进主壳后再后台补探。</param>
    /// <param name="onTool">每探测完一个工具回调 (toolId, index1Based, total)。</param>
    public void Refresh(bool probeUpdates = true, Action<string, int, int>? onTool = null)
    {
        ReloadGroupsFromSeeds();
        var rows = _db.ListSoftware();
        var total = Math.Max(1, rows.Count);
        var i = 0;
        foreach (var row in rows)
        {
            i++;
            ProbeTool(row.Id, probeUpdates);
            onTool?.Invoke(row.Id, i, total);
        }
    }

    /// <summary>仅补探测更新标记（不重复安装态探测）。后台静默调用。</summary>
    public void ProbeUpdatesOnly()
    {
        foreach (var row in _db.ListSoftware())
        {
            var manifest = JsonSerializer.Deserialize<SoftwareDefinition>(row.ManifestJson);
            if (IsUpdateSuppressed(manifest, row.Id)) continue;
            UpdateProbe.ProbeAndStore(_db, row.Id, manifest);
        }
    }

    /// <summary>
    /// 校准安装态与展示版本：跳过 <paramref name="maxAge"/> 内已探测过的工具。
    /// </summary>
    public void CalibrateInstallStates(
        IProgress<int>? progress,
        CancellationToken cancellationToken,
        TimeSpan maxAge)
    {
        var rows = _db.ListSoftware();
        var total = Math.Max(1, rows.Count);
        var i = 0;
        foreach (var row in rows)
        {
            cancellationToken.ThrowIfCancellationRequested();
            i++;
            progress?.Report((int)Math.Clamp(Math.Round(100.0 * i / total), 1, 99));
            if (IsToolStateFresh(row.Id, maxAge))
                continue;
            ProbeTool(row.Id, probeUpdates: false);
        }

        progress?.Report(100);
    }

    /// <summary>tool_state.checked_at 是否在新鲜期内。</summary>
    public bool IsToolStateFresh(string toolId, TimeSpan maxAge)
    {
        var state = _db.GetToolState(toolId);
        if (state is null) return false;
        if (string.Equals(state.Status, "unknown", StringComparison.OrdinalIgnoreCase))
            return false;
        if (!DateTimeOffset.TryParse(state.CheckedAt, out var at))
            return false;
        return DateTimeOffset.UtcNow - at < maxAge;
    }

    /// <summary>组装发给 UI 的目录项列表。</summary>
    /// <param name="locale">界面语言。</param>
    /// <param name="group">可选过滤：daily / dev；null 表示全部。</param>
    public IReadOnlyList<CatalogItemDto> GetCatalog(string locale, string? group = null)
    {
        var items = new List<CatalogItemDto>();
        foreach (var row in _db.ListSoftware(group))
        {
            var manifest = JsonSerializer.Deserialize<SoftwareDefinition>(row.ManifestJson);
            if (manifest is null) continue;

            var name = _db.T(locale, manifest.NameKey, row.Id);
            var desc = _db.T(locale, manifest.DescriptionKey, "");
            var state = _db.GetToolState(row.Id);
            var uiMode = manifest.Ui?.Mode ?? "generic";
            var uiEntry = string.IsNullOrWhiteSpace(manifest.Ui?.Entry)
                ? null
                : manifest.Ui!.Entry!.Trim();
            var updateAvailable = string.Equals(state?.Status, "installed", StringComparison.OrdinalIgnoreCase)
                && state?.Detail is { Length: > 0 } d
                && d.StartsWith("update:", StringComparison.OrdinalIgnoreCase);

            // 种子声明 update.strategy=none 时不展示「有更新」
            if (IsUpdateSuppressed(manifest, row.Id))
                updateAvailable = false;

            var version = ResolveDisplayVersion(row.Id, state);

            items.Add(new CatalogItemDto(
                row.Id,
                name,
                desc,
                row.Group,
                state?.Status ?? "unknown",
                version,
                manifest.Actions.Select(a => a.Id).ToArray(),
                uiMode,
                uiEntry,
                manifest.Tags.ToArray(),
                updateAvailable));
        }

        return items;
    }

    /// <summary>库中是否存在该软件 id。</summary>
    public bool Contains(string toolId) => _db.GetSoftware(toolId) is not null;

    /// <summary>
    /// 按种子 actions[].handler 执行动作。
    /// </summary>
    /// <param name="jobId">任务 id（与 UI 约定）。</param>
    /// <param name="toolId">软件 id。</param>
    /// <param name="action">动作 id（如 install）。</param>
    /// <param name="jobs">任务运行器。</param>
    /// <param name="versions">可选版本列表（Volta 类动作）。</param>
    /// <param name="options">可选键值（如 projectPath）。</param>
    /// <param name="cancellationToken">取消令牌。</param>
    /// <returns>任务结果；找不到工具/动作/Handler 时 ok=false。</returns>
    public Task<JobResult> ExecuteAsync(
        string jobId,
        string toolId,
        string action,
        JobRunner jobs,
        IReadOnlyList<string>? versions = null,
        IReadOnlyDictionary<string, string>? options = null,
        CancellationToken cancellationToken = default)
    {
        var row = _db.GetSoftware(toolId);
        if (row is null)
            return Task.FromResult(new JobResult(jobId, false, 1, $"未知软件: {toolId}"));

        var manifest = JsonSerializer.Deserialize<SoftwareDefinition>(row.ManifestJson);
        var act = manifest?.Actions.FirstOrDefault(a =>
            string.Equals(a.Id, action, StringComparison.OrdinalIgnoreCase));
        if (act is null || string.IsNullOrWhiteSpace(act.Handler))
            return Task.FromResult(new JobResult(jobId, false, 1, $"未知动作: {toolId}/{action}"));

        if (!_handlers.TryGetValue(act.Handler, out var handler))
        {
            return Task.FromResult(new JobResult(
                jobId, false, 1, $"未注册 Handler: {act.Handler}（工具 {toolId}）"));
        }

        var seedsRoot = AppPaths.ResolveSeedsRoot() ?? "";
        var ctx = new ToolActionContext(jobId, toolId, action, manifest!, seedsRoot, jobs, _db, versions, options);
        return handler.ExecuteAsync(ctx, cancellationToken);
    }

    /// <summary>探测安装状态，并同步 Volta 管理工具的展示版本。</summary>
    /// <param name="toolId">软件 id。</param>
    /// <param name="probeUpdates">是否同时探测更新。</param>
    public void ProbeTool(string toolId, bool probeUpdates = true)
    {
        var row = _db.GetSoftware(toolId);
        if (row is null) return;
        var manifest = JsonSerializer.Deserialize<SoftwareDefinition>(row.ManifestJson);
        InstallDetector.ProbeAndStore(_db, toolId, manifest?.Install?.Detect);

        if (probeUpdates && !IsUpdateSuppressed(manifest, toolId))
            UpdateProbe.ProbeAndStore(_db, toolId, manifest);

        var state = _db.GetToolState(toolId);
        if (state is null || !string.Equals(state.Status, "installed", StringComparison.OrdinalIgnoreCase))
            return;

        var display = _volta.GetCatalogDisplayVersion(toolId);
        if (!string.IsNullOrWhiteSpace(display) &&
            !string.Equals(display, state.Version, StringComparison.OrdinalIgnoreCase))
        {
            // 保留既有 detail（如 update:…），只刷新展示版本
            state = _db.GetToolState(toolId);
            _db.UpsertToolState(toolId, "installed", display, state?.Detail);
        }
    }

    /// <summary>
    /// 列表展示版本：只读库，避免 get-catalog 时起进程。
    /// Volta 系展示版本由静默校准 / Job 后的 ProbeTool 写入。
    /// </summary>
    private static string? ResolveDisplayVersion(string toolId, ToolStateRow? state)
    {
        _ = toolId;
        if (state is null || !string.Equals(state.Status, "installed", StringComparison.OrdinalIgnoreCase))
            return null;
        return state.Version;
    }

    /// <summary>
    /// 是否抑制更新探测/角标：种子 <c>install.update.strategy=none</c>，
    /// 或未声明 update 且为 Volta 管理的 node/pnpm/yarn。
    /// </summary>
    /// <param name="manifest">清单；可空。</param>
    /// <param name="toolId">软件 id（以库行为准）。</param>
    private static bool IsUpdateSuppressed(SoftwareDefinition? manifest, string toolId)
    {
        var strategy = manifest?.Install?.Update?.Strategy;
        if (string.Equals(strategy, "none", StringComparison.OrdinalIgnoreCase))
            return true;
        // 兼容尚未写 update 块的旧种子
        if (strategy is null && toolId is "node" or "pnpm" or "yarn")
            return true;
        return false;
    }

    private void ReloadGroupsFromSeeds()
    {
        var defaults = new List<SoftwareGroupDefinition>
        {
            new() { Id = SoftwareGroups.Daily, Sort = 10, NameKey = "group.daily", Enabled = true },
            new() { Id = SoftwareGroups.Dev, Sort = 20, NameKey = "group.dev", Enabled = true },
        };

        var root = AppPaths.ResolveSeedsRoot();
        if (root is null)
        {
            _groups = defaults;
            return;
        }

        var path = Path.Combine(root, "shell", "groups.json");
        if (!File.Exists(path))
            path = Path.Combine(root, "groups.json");
        if (!File.Exists(path))
        {
            _groups = defaults;
            return;
        }

        try
        {
            var file = JsonSerializer.Deserialize<SoftwareGroupsFile>(File.ReadAllText(path));
            _groups = file?.Groups is { Count: > 0 } ? file.Groups : defaults;
        }
        catch
        {
            _groups = defaults;
        }
    }

    private static string FallbackGroupName(string id) => id switch
    {
        SoftwareGroups.Daily => "日常工具",
        SoftwareGroups.Dev => "开发工具",
        _ => id,
    };
}
