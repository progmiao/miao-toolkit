using System.Text.Json;
using Miao.Common.Jobs;
using Miao.Common.Software;
using Miao.Data;
using Miao.Software.Claude;
using Miao.Software.Detect;
using Miao.Software.Handlers;
using Miao.Software.Jobs;
using Miao.Software.Volta;

namespace Miao.Software.Catalog;

/// <summary>
/// 软件目录：从 DB（由 seeds 灌入）组装清单并调度 Handler。
/// </summary>
public sealed class SoftwareCatalog
{
    private readonly AppDatabase _db;
    private readonly VoltaPackageService _volta;
    private readonly Dictionary<string, IToolActionHandler> _handlers;
    private List<SoftwareGroupDefinition> _groups = new();

    /// <summary>
    /// 创建目录并注册内置 Handler。
    /// </summary>
    /// <param name="db">数据库。</param>
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
            new ClaudePluginInstallHandler(claude),
            new ClaudePluginUninstallHandler(claude),
            new HermesInstallHandler(),
            new HermesUninstallHandler(),
            new TerminalBuddyInstallHandler(),
            new TerminalBuddyUninstallHandler(),
        };
        _handlers = list.ToDictionary(h => h.HandlerId, StringComparer.OrdinalIgnoreCase);
        ReloadGroupsFromSeeds();
    }

    /// <summary>已登记且启用的软件分组。</summary>
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

    /// <summary>种子灌库后刷新分组定义并探测安装状态。</summary>
    public void Refresh()
    {
        ReloadGroupsFromSeeds();
        foreach (var row in _db.ListSoftware())
        {
            ProbeTool(row.Id);
        }
    }

    /// <summary>组装目录；可按 group 过滤。</summary>
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
            var updateAvailable = string.Equals(state?.Status, "installed", StringComparison.OrdinalIgnoreCase)
                && state?.Detail is { Length: > 0 } d
                && d.StartsWith("update:", StringComparison.OrdinalIgnoreCase);

            // 多版本运行时：永不展示目录级「有更新」
            if (row.Id is "node" or "pnpm" or "yarn")
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
                manifest.Tags.ToArray(),
                updateAvailable));
        }

        return items;
    }

    /// <summary>是否存在软件条目。</summary>
    public bool Contains(string toolId) => _db.GetSoftware(toolId) is not null;

    /// <summary>执行软件动作。</summary>
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
            return Task.FromResult(new JobResult(jobId, false, 1, $"软件未声明动作: {toolId}/{action}"));

        if (!_handlers.TryGetValue(act.Handler, out var handler))
        {
            return Task.FromResult(new JobResult(
                jobId, false, 1, $"未注册处理器: {act.Handler}（软件 {toolId}）"));
        }

        var seedsRoot = AppPaths.ResolveSeedsRoot() ?? "";
        var ctx = new ToolActionContext(jobId, toolId, action, manifest!, seedsRoot, jobs, _db, versions, options);
        return handler.ExecuteAsync(ctx, cancellationToken);
    }

    /// <summary>安装后刷新单工具状态（含 Volta 系展示版本回写）。</summary>
    public void ProbeTool(string toolId)
    {
        var row = _db.GetSoftware(toolId);
        if (row is null) return;
        var manifest = JsonSerializer.Deserialize<SoftwareDefinition>(row.ManifestJson);
        InstallDetector.ProbeAndStore(_db, toolId, manifest?.Install?.Detect);

        // 分工具更新探测（node/pnpm/yarn 等无 update 策略则清除）
        UpdateProbe.ProbeAndStore(_db, toolId, manifest);

        var state = _db.GetToolState(toolId);
        if (state is null || !string.Equals(state.Status, "installed", StringComparison.OrdinalIgnoreCase))
            return;

        var display = _volta.GetCatalogDisplayVersion(toolId);
        if (!string.IsNullOrWhiteSpace(display) &&
            !string.Equals(display, state.Version, StringComparison.OrdinalIgnoreCase))
        {
            // 保留 update: 标记
            state = _db.GetToolState(toolId);
            _db.UpsertToolState(toolId, "installed", display, state?.Detail);
        }
    }

    /// <summary>
    /// 解析列表展示版本：volta=当前装；node/pnpm/yarn=默认版；其它用探测结果。
    /// </summary>
    private string? ResolveDisplayVersion(string toolId, ToolStateRow? state)
    {
        if (state is null || !string.Equals(state.Status, "installed", StringComparison.OrdinalIgnoreCase))
            return null;

        if (toolId is "volta" or "node" or "pnpm" or "yarn")
            return _volta.GetCatalogDisplayVersion(toolId) ?? state.Version;

        return state.Version;
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

        var path = Path.Combine(root, "groups.json");
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
