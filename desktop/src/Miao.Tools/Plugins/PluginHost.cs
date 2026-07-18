using System.Text.Json;
using Miao.Common;
using Miao.Common.Jobs;
using Miao.Common.Plugins;
using Miao.Data;
using Miao.Tools.Detect;
using Miao.Tools.Handlers;
using Miao.Tools.Jobs;

namespace Miao.Tools.Plugins;

/// <summary>
/// 插件宿主：按 registry 扫描 daily/dev → SQLite → 目录与动作调度。
/// 用户目录后扫，同 id 覆盖内置。
/// </summary>
public sealed class PluginHost
{
    private readonly AppDatabase _db;
    private readonly Dictionary<string, IToolActionHandler> _handlers;
    private readonly Dictionary<string, Dictionary<string, string>> _i18nByPlugin = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _groupNames = new(StringComparer.OrdinalIgnoreCase);
    private List<PluginRegistryGroup> _groups = new();

    /// <summary>创建宿主并注册内置 Handler。</summary>
    public PluginHost(AppDatabase db)
    {
        _db = db;
        var list = new IToolActionHandler[]
        {
            new InstallerLaunchHandler(),
            new WingetInstallHandler(),
            new NpmGlobalInstallHandler(),
            new RegistryUninstallHandler(),
            new NodeInstallHandler(),
            new TerminalBuddyInstallHandler(),
            new TerminalBuddyUninstallHandler(),
        };
        _handlers = list.ToDictionary(h => h.HandlerId, StringComparer.OrdinalIgnoreCase);
    }

    /// <summary>已登记且启用的一级分类（侧栏用）。</summary>
    public IReadOnlyList<CatalogGroupDto> GetGroups(string locale)
    {
        return _groups
            .Where(g => g.Enabled)
            .OrderBy(g => g.Sort)
            .Select(g => new CatalogGroupDto(
                g.Id,
                ResolveGroupName(g, locale),
                g.Sort))
            .ToList();
    }

    /// <summary>扫描磁盘、刷新库、探测状态。</summary>
    public void RefreshFromDisk()
    {
        _i18nByPlugin.Clear();
        _groupNames.Clear();
        _groups = LoadRegistryMerged();

        foreach (var root in AppPaths.ResolvePluginRoots())
        {
            LoadRootI18n(root);
            foreach (var group in _groups.Where(g => g.Enabled))
            {
                var groupDir = Path.Combine(root, group.Id);
                if (!Directory.Exists(groupDir)) continue;

                foreach (var dir in Directory.EnumerateDirectories(groupDir))
                {
                    var manifestPath = Path.Combine(dir, "plugin.json");
                    if (!File.Exists(manifestPath)) continue;

                    var json = File.ReadAllText(manifestPath);
                    var manifest = JsonSerializer.Deserialize<PluginManifest>(json);
                    if (manifest is null || string.IsNullOrWhiteSpace(manifest.Id)) continue;

                    var id = manifest.Id.Trim();
                    if (!string.IsNullOrWhiteSpace(manifest.Group) &&
                        !string.Equals(manifest.Group, group.Id, StringComparison.OrdinalIgnoreCase))
                    {
                        // 以文件夹为准
                    }

                    _db.UpsertPlugin(id, group.Id, manifest.Sort, json, Path.GetFullPath(dir));
                    LoadPluginI18n(id, dir);
                }
            }
        }

        foreach (var row in _db.ListPlugins())
        {
            var manifest = JsonSerializer.Deserialize<PluginManifest>(row.ManifestJson);
            InstallDetector.ProbeAndStore(_db, row.Id, manifest?.Install?.Detect);
        }
    }

    /// <summary>组装目录；可按 group 过滤。</summary>
    public IReadOnlyList<CatalogItemDto> GetCatalog(string locale, string? group = null)
    {
        var items = new List<CatalogItemDto>();
        foreach (var row in _db.ListPlugins(group))
        {
            var manifest = JsonSerializer.Deserialize<PluginManifest>(row.ManifestJson);
            if (manifest is null) continue;

            var name = T(row.Id, locale, manifest.NameKey, row.Id);
            var desc = T(row.Id, locale, manifest.DescriptionKey, "");
            var state = _db.GetToolState(row.Id);
            var uiMode = manifest.Ui?.Mode ?? "generic";
            items.Add(new CatalogItemDto(
                row.Id,
                name,
                desc,
                row.Group,
                state?.Status ?? "unknown",
                state?.Version,
                manifest.Actions.Select(a => a.Id).ToArray(),
                uiMode,
                manifest.Tags.ToArray()));
        }

        return items;
    }

    /// <summary>是否存在插件。</summary>
    public bool Contains(string toolId) => _db.GetPlugin(toolId) is not null;

    /// <summary>执行插件动作。</summary>
    public Task<JobResult> ExecuteAsync(
        string jobId,
        string toolId,
        string action,
        JobRunner jobs,
        CancellationToken cancellationToken = default)
    {
        var row = _db.GetPlugin(toolId);
        if (row is null)
            return Task.FromResult(new JobResult(jobId, false, 1, $"未知插件: {toolId}"));

        var manifest = JsonSerializer.Deserialize<PluginManifest>(row.ManifestJson);
        var act = manifest?.Actions.FirstOrDefault(a =>
            string.Equals(a.Id, action, StringComparison.OrdinalIgnoreCase));
        if (act is null || string.IsNullOrWhiteSpace(act.Handler))
            return Task.FromResult(new JobResult(jobId, false, 1, $"插件未声明动作: {toolId}/{action}"));

        if (!_handlers.TryGetValue(act.Handler, out var handler))
        {
            return Task.FromResult(new JobResult(
                jobId, false, 1, $"未注册处理器: {act.Handler}（插件 {toolId}）"));
        }

        var ctx = new ToolActionContext(jobId, toolId, action, manifest!, row.DirPath, jobs, _db);
        return handler.ExecuteAsync(ctx, cancellationToken);
    }

    /// <summary>安装后刷新单工具状态。</summary>
    public void ProbeTool(string toolId)
    {
        var row = _db.GetPlugin(toolId);
        if (row is null) return;
        var manifest = JsonSerializer.Deserialize<PluginManifest>(row.ManifestJson);
        InstallDetector.ProbeAndStore(_db, toolId, manifest?.Install?.Detect);
    }

    private List<PluginRegistryGroup> LoadRegistryMerged()
    {
        // 默认：日常 + 开发
        var defaults = new List<PluginRegistryGroup>
        {
            new() { Id = PluginGroups.Daily, Sort = 10, NameKey = "group.daily", Enabled = true },
            new() { Id = PluginGroups.Dev, Sort = 20, NameKey = "group.dev", Enabled = true },
        };

        foreach (var root in AppPaths.ResolvePluginRoots())
        {
            var path = Path.Combine(root, "_registry.json");
            if (!File.Exists(path)) continue;
            try
            {
                var file = JsonSerializer.Deserialize<PluginRegistryFile>(File.ReadAllText(path));
                if (file?.Groups is { Count: > 0 })
                    return file.Groups;
            }
            catch
            {
                /* 忽略坏文件，用默认 */
            }
        }

        return defaults;
    }

    private void LoadRootI18n(string root)
    {
        foreach (var locale in new[] { "zh", "en" })
        {
            var path = Path.Combine(root, "i18n", $"{locale}.json");
            if (!File.Exists(path)) continue;
            try
            {
                var dict = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(path));
                if (dict is null) continue;
                foreach (var (k, v) in dict)
                    _groupNames[$"{locale}:{k}"] = v;
            }
            catch { /* ignore */ }
        }
    }

    private string ResolveGroupName(PluginRegistryGroup g, string locale)
    {
        if (_groupNames.TryGetValue($"{locale}:{g.NameKey}", out var hit) && !string.IsNullOrWhiteSpace(hit))
            return hit;
        if (_groupNames.TryGetValue($"zh:{g.NameKey}", out var zh) && !string.IsNullOrWhiteSpace(zh))
            return zh;
        return g.Id switch
        {
            PluginGroups.Daily => "日常工具",
            PluginGroups.Dev => "开发工具",
            _ => g.Id,
        };
    }

    private void LoadPluginI18n(string pluginId, string dir)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var locale in new[] { "zh", "en" })
        {
            var path = Path.Combine(dir, "i18n", $"{locale}.json");
            if (!File.Exists(path)) continue;
            try
            {
                var dict = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(path));
                if (dict is null) continue;
                foreach (var (k, v) in dict)
                    map[$"{locale}:{k}"] = v;
            }
            catch { /* ignore */ }
        }

        _i18nByPlugin[pluginId] = map;
    }

    private string T(string pluginId, string locale, string key, string fallback)
    {
        if (string.IsNullOrWhiteSpace(key)) return fallback;
        if (_i18nByPlugin.TryGetValue(pluginId, out var map))
        {
            if (map.TryGetValue($"{locale}:{key}", out var hit) && !string.IsNullOrWhiteSpace(hit))
                return hit;
            if (map.TryGetValue($"zh:{key}", out var zh) && !string.IsNullOrWhiteSpace(zh))
                return zh;
        }

        return fallback;
    }
}
