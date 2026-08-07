using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Miao.Data;

namespace Miao.Software.Dev.Claude;

/// <summary>
/// Claude Code：密钥落盘、合并 ~/.claude/settings.json、初始化与插件辅助。
/// 桌面原生实现，不调用 CLI 脚本。
/// </summary>
public sealed class ClaudeCodeService
{
    private static readonly JsonSerializerOptions JsonWrite = new()
    {
        WriteIndented = true,
    };

    private static readonly Regex AnsiRegex = new(
        @"\u001b\[[0-9;?]*[ -/]*[@-~]",
        RegexOptions.Compiled);

    /// <summary>Miao 侧密钥文件：%LocalAppData%\Miao\claude-code.json。</summary>
    public string SecretsPath => Path.Combine(AppPaths.DataRoot, "claude-code.json");

    /// <summary>用户 Claude 设置：~/.claude/settings.json。</summary>
    public string SettingsPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude", "settings.json");

    /// <summary>插件 marketplace 本地缓存目录。</summary>
    private static string MarketplacesRoot =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".claude",
            "plugins",
            "marketplaces");

    /// <summary>当前 CLI 是否可用（现场探测；装/卸后或需强制刷新时用）。</summary>
    public ClaudeStatusDto GetStatus()
    {
        var version = TryCommandVersion("claude", "--version");
        var wingetManaged = IsWingetPackagePresent("Anthropic.ClaudeCode");
        var secrets = LoadSecrets();
        return new ClaudeStatusDto(
            version is not null,
            version,
            wingetManaged,
            File.Exists(SettingsPath),
            secrets.Api?.Mode,
            secrets.Proxy?.Mode,
            HasMaskedKey(secrets));
    }

    /// <summary>
    /// 读库安装态 + 本地密钥文件；不跑 claude/winget，供面板首屏。
    /// </summary>
    public ClaudeStatusDto GetStatusCached(AppDatabase db)
    {
        var state = db.GetToolState("claude-code");
        var installed =
            state is not null
            && string.Equals(state.Status, "installed", StringComparison.OrdinalIgnoreCase);
        var secrets = LoadSecrets();
        return new ClaudeStatusDto(
            installed,
            installed ? state?.Version : null,
            false,
            File.Exists(SettingsPath),
            secrets.Api?.Mode,
            secrets.Proxy?.Mode,
            HasMaskedKey(secrets));
    }

    /// <summary>应用初始化默认：DISABLE_LOGIN_COMMAND=1，注册预设 marketplace，并同步插件目录落库。</summary>
    /// <param name="asReset">true 时日志用「重置」措辞（内容与初始化相同）。</param>
    /// <param name="onStep">每步进度回调（文案, 进度 0–100）。</param>
    /// <param name="db">非空时将插件目录写入 SQLite。</param>
    /// <returns>是否全部成功；详情为多行日志。</returns>
    public (bool Ok, string Detail) Init(
        bool asReset = false,
        Action<string, int>? onStep = null,
        AppDatabase? db = null)
    {
        onStep?.Invoke(asReset ? "写入初始化设置…" : "写入初始化设置…", 8);
        MergeEnv(new Dictionary<string, string?> { ["DISABLE_LOGIN_COMMAND"] = "1" }, Array.Empty<string>());
        var presets = LoadPresets();
        var logs = new List<string>
        {
            asReset ? "已重置 DISABLE_LOGIN_COMMAND=1" : "已写入 DISABLE_LOGIN_COMMAND=1",
        };
        onStep?.Invoke(logs[^1], 15);

        var markets = presets.Marketplaces
            .Where(mp => !string.IsNullOrWhiteSpace(mp.Source))
            .ToList();
        var allOk = true;
        for (var i = 0; i < markets.Count; i++)
        {
            var source = markets[i].Source!;
            var pct = 15 + (int)(50.0 * (i + 1) / Math.Max(1, markets.Count));
            onStep?.Invoke($"注册 marketplace {source}", pct);
            var (ok, detail) = AddMarketplace(source);
            var tag = asReset ? "marketplace 重置" : "marketplace +";
            if (ok)
            {
                logs.Add(
                    $"{tag} {source}"
                    + (string.IsNullOrWhiteSpace(detail) ? "" : $"（{detail}）"));
            }
            else
            {
                allOk = false;
                logs.Add($"marketplace 失败 {source}: {detail}");
            }

            onStep?.Invoke(logs[^1], pct);
        }

        if (db is not null)
        {
            onStep?.Invoke("同步插件目录到本地库…", 70);
            var (syncOk, syncDetail) = SyncPluginCatalog(db, onStep, updateRemote: true);
            logs.Add(syncDetail);
            if (!syncOk) allOk = false;
            else db.SetSetting("claude.initialized", "1");
            onStep?.Invoke(syncOk ? "插件目录已落库" : "插件目录同步失败", 92);
        }

        if (asReset)
            logs.Add("初始化相关设置已恢复（未改动 API / 代理 / 已装插件）");

        onStep?.Invoke(asReset ? (allOk ? "重置完成" : "重置未全部成功") : (allOk ? "初始化完成" : "初始化未全部成功"), 100);
        return (allOk, string.Join("\n", logs));
    }

    /// <summary>配置 API：official / custom / clear。</summary>
    public string ApplyApi(string mode, string? apiKey, string? baseUrl, string? authToken)
    {
        var secrets = LoadSecrets();
        var remove = new List<string> { "ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN" };
        var updates = new Dictionary<string, string?>();

        if (mode == "clear")
        {
            secrets.Api = new ClaudeApiSecrets { Mode = "clear" };
            SaveSecrets(secrets);
            MergeEnv(updates, remove);
            return SettingsPath;
        }

        if (mode == "official")
        {
            secrets.Api = new ClaudeApiSecrets { Mode = "official", ApiKey = apiKey ?? "" };
            updates["ANTHROPIC_API_KEY"] = apiKey;
            remove = ["ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN"];
        }
        else if (mode == "custom")
        {
            secrets.Api = new ClaudeApiSecrets
            {
                Mode = "custom",
                BaseUrl = baseUrl ?? "",
                AuthToken = authToken ?? "",
            };
            updates["ANTHROPIC_BASE_URL"] = baseUrl;
            if (!string.IsNullOrWhiteSpace(authToken))
            {
                if (authToken.StartsWith("sk-ant-", StringComparison.Ordinal))
                {
                    updates["ANTHROPIC_API_KEY"] = authToken;
                    remove = ["ANTHROPIC_AUTH_TOKEN"];
                }
                else
                {
                    updates["ANTHROPIC_AUTH_TOKEN"] = authToken;
                    remove = ["ANTHROPIC_API_KEY"];
                }
            }
            else
            {
                remove = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"];
            }
        }
        else
        {
            throw new ArgumentException("mode 须为 official / custom / clear");
        }

        SaveSecrets(secrets);
        MergeEnv(updates, remove);
        return SettingsPath;
    }

    /// <summary>配置代理：set / clear。</summary>
    public string ApplyProxy(string mode, string? httpProxy, string? httpsProxy)
    {
        var secrets = LoadSecrets();
        if (mode == "clear")
        {
            secrets.Proxy = new ClaudeProxySecrets { Mode = "clear" };
            SaveSecrets(secrets);
            MergeEnv(new Dictionary<string, string?>(), ["HTTP_PROXY", "HTTPS_PROXY"]);
            return SettingsPath;
        }

        if (string.IsNullOrWhiteSpace(httpsProxy) && !string.IsNullOrWhiteSpace(httpProxy))
            httpsProxy = httpProxy;

        secrets.Proxy = new ClaudeProxySecrets
        {
            Mode = "set",
            HttpProxy = httpProxy ?? "",
            HttpsProxy = httpsProxy ?? "",
        };
        SaveSecrets(secrets);
        MergeEnv(new Dictionary<string, string?>
        {
            ["HTTP_PROXY"] = httpProxy,
            ["HTTPS_PROXY"] = httpsProxy,
        }, Array.Empty<string>());
        return SettingsPath;
    }

    /// <summary>是否配置了预设插件市场名称（来自 presets，不依赖本机目录是否齐全）。</summary>
    public bool HasConfiguredPluginMarketplace() =>
        ResolveConfiguredMarketplaceNames().Count > 0;

    /// <summary>
    /// 是否已完成工具箱侧初始化：已写 DISABLE_LOGIN_COMMAND，且预设 marketplace 已登记可用。
    /// </summary>
    public bool IsInitialized(AppDatabase? db = null)
    {
        if (db is not null
            && string.Equals(db.GetSetting("claude.initialized", ""), "1", StringComparison.Ordinal))
            return true;

        if (!HasDisableLoginCommand()) return false;
        return HasUsablePresetMarketplace();
    }

    /// <summary>从库读三态插件列表（安装 / 更新 / 卸载）。</summary>
    public ClaudePluginListsDto GetPluginLists(AppDatabase db) =>
        new(
            db.ListClaudePluginsForInstall().Select(ToDto).ToList(),
            db.ListClaudePluginsForUpdate().Select(ToDto).ToList(),
            db.ListClaudePluginsForUninstall().Select(ToDto).ToList());

    private static ClaudePluginDto ToDto(ClaudePluginRow row) =>
        new(
            row.PluginId,
            string.IsNullOrWhiteSpace(row.Name) ? row.PluginId : row.Name,
            row.Featured,
            row.Description,
            row.InstalledVersion,
            row.RemoteVersion,
            row.UpdateAvailable);

    /// <summary>
    /// 同步预设 marketplace 插件目录到 SQLite，并用本地文件/CLI 校验安装态。
    /// 远端已删但本机仍装着的插件会保留为已装。
    /// </summary>
    /// <param name="updateRemote">true 时先 marketplace update 拉远端清单。</param>
    public (bool Ok, string Detail) SyncPluginCatalog(
        AppDatabase db,
        Action<string, int>? onStep = null,
        bool updateRemote = true)
    {
        try
        {
            var marketNames = ResolveConfiguredMarketplaceNames();
            if (marketNames.Count == 0)
                return (true, "未配置插件市场，跳过目录同步");

            onStep?.Invoke("解析已配置 marketplace…", 72);
            if (updateRemote)
            {
                foreach (var name in marketNames)
                {
                    onStep?.Invoke($"更新 marketplace {name}…", 75);
                    _ = RunClaude($"plugin marketplace update {EscapeArg(name)}");
                }
            }

            onStep?.Invoke("读取插件目录…", 80);
            var catalog = LoadCatalogFromMarketplaces(marketNames);
            // CLI 兜底：本地 marketplace.json 缺失时
            if (catalog.Count == 0)
                MergeAvailableFromCli(catalog, marketNames);

            if (catalog.Count == 0)
                return (false, $"未能读取插件目录（市场：{string.Join(", ", marketNames)}）。请重新执行初始化。");

            onStep?.Invoke("校验本机安装状态…", 88);
            var installedMap = DiscoverInstalledPlugins(marketNames);
            var featured = new HashSet<string>(
                LoadPresets().FeaturedPlugins
                    .Select(p => p.Id)
                    .Where(id => !string.IsNullOrWhiteSpace(id)),
                StringComparer.OrdinalIgnoreCase);
            var checkedAt = DateTimeOffset.UtcNow.ToString("O");
            var rows = new Dictionary<string, ClaudePluginRow>(StringComparer.OrdinalIgnoreCase);

            foreach (var (pluginId, entry) in catalog)
            {
                var isInstalled = installedMap.TryGetValue(pluginId, out var instVer);
                var update = isInstalled
                             && !string.IsNullOrWhiteSpace(entry.Version)
                             && !string.IsNullOrWhiteSpace(instVer)
                             && !VersionsEqual(entry.Version!, instVer!);
                rows[pluginId] = new ClaudePluginRow(
                    pluginId,
                    entry.Name,
                    entry.Marketplace,
                    entry.Description,
                    featured.Contains(pluginId),
                    entry.Version,
                    isInstalled,
                    isInstalled ? instVer : null,
                    update,
                    InCatalog: true,
                    checkedAt);
                if (isInstalled) installedMap.Remove(pluginId);
            }

            // 远端已删但仍本机安装：保留展示
            foreach (var (pluginId, instVer) in installedMap)
            {
                SplitPluginId(pluginId, out var name, out var mp);
                if (!string.IsNullOrEmpty(mp)
                    && !marketNames.Contains(mp, StringComparer.OrdinalIgnoreCase))
                {
                    continue;
                }

                rows[pluginId] = new ClaudePluginRow(
                    pluginId,
                    name,
                    mp,
                    Description: null,
                    Featured: featured.Contains(pluginId),
                    RemoteVersion: null,
                    Installed: true,
                    InstalledVersion: instVer,
                    UpdateAvailable: false,
                    InCatalog: false,
                    checkedAt);
            }

            db.ReplaceClaudePlugins(rows.Values);
            onStep?.Invoke($"已同步 {rows.Count} 个插件", 95);
            return (true, $"插件目录已同步（{rows.Count}）");
        }
        catch (Exception ex)
        {
            return (false, $"插件目录同步失败: {ex.Message}");
        }
    }

    /// <summary>安装插件（需已装 claude）。</summary>
    public (bool Ok, string Detail) InstallPlugin(string pluginId)
    {
        if (string.IsNullOrWhiteSpace(pluginId))
            return (false, "缺少 pluginId");
        return RunClaude($"plugin install {EscapeArg(pluginId)}");
    }

    /// <summary>卸载插件。</summary>
    public (bool Ok, string Detail) UninstallPlugin(string pluginId)
    {
        if (string.IsNullOrWhiteSpace(pluginId))
            return (false, "缺少 pluginId");
        return RunClaude($"plugin uninstall {EscapeArg(pluginId)}");
    }

    /// <summary>更新已装插件；若 CLI 判定未安装则改为 install（兼容缓存误判后的修复路径）。</summary>
    public (bool Ok, string Detail) UpdatePlugin(string pluginId)
    {
        if (string.IsNullOrWhiteSpace(pluginId))
            return (false, "缺少 pluginId");
        var (ok, detail) = RunClaude($"plugin update {EscapeArg(pluginId)}");
        if (ok) return (ok, detail);
        if (LooksLikeNotInstalled(detail))
        {
            var (ok2, detail2) = RunClaude($"plugin install {EscapeArg(pluginId)}");
            if (ok2)
                return (true, $"update 时未安装，已改为 install：{detail2}");
            return (false, $"update 失败：{detail}\ninstall 失败：{detail2}");
        }

        return (ok, detail);
    }

    private static bool LooksLikeNotInstalled(string detail) =>
        detail.Contains("is not installed", StringComparison.OrdinalIgnoreCase)
        || detail.Contains("not installed", StringComparison.OrdinalIgnoreCase)
        || detail.Contains("未安装", StringComparison.OrdinalIgnoreCase);

    /// <summary>读取脱敏后的密钥摘要（不回传明文密钥）。</summary>
    public ClaudeSecretsPublicDto GetSecretsPublic()
    {
        var s = LoadSecrets();
        return new ClaudeSecretsPublicDto(
            s.Api?.Mode,
            Mask(s.Api?.ApiKey),
            s.Api?.BaseUrl,
            Mask(s.Api?.AuthToken),
            s.Proxy?.Mode,
            s.Proxy?.HttpProxy,
            s.Proxy?.HttpsProxy);
    }

    private IReadOnlyList<string> ResolveConfiguredMarketplaceNames()
    {
        var presets = LoadPresets();
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var known = LoadKnownMarketplaces();

        foreach (var mp in presets.Marketplaces.Where(m => !string.IsNullOrWhiteSpace(m.Source)))
        {
            var normalized = NormalizeMarketplaceSource(mp.Source!);
            var repo = ExtractGithubRepo(normalized);

            // Claude 侧市场名通常是仓库名（superpowers-marketplace），始终纳入以便 CLI 兜底
            if (repo is not null)
            {
                var shortName = repo.Contains('/') ? repo[(repo.LastIndexOf('/') + 1)..] : repo;
                if (!string.IsNullOrWhiteSpace(shortName))
                    names.Add(shortName);
            }

            foreach (var (name, entry) in known)
            {
                if (repo is not null
                    && string.Equals(entry.Repo, repo, StringComparison.OrdinalIgnoreCase))
                    names.Add(name);
            }
        }

        // 精选插件 id 中的 marketplace 后缀
        foreach (var id in presets.FeaturedPlugins.Select(p => p.Id))
        {
            SplitPluginId(id, out _, out var mp);
            if (!string.IsNullOrEmpty(mp))
                names.Add(mp);
        }

        return names.ToList();
    }

    private bool HasDisableLoginCommand()
    {
        if (!File.Exists(SettingsPath)) return false;
        try
        {
            var root = JsonNode.Parse(File.ReadAllText(SettingsPath)) as JsonObject;
            var env = root?["env"] as JsonObject;
            var node = env?["DISABLE_LOGIN_COMMAND"];
            if (node is null) return false;
            var v = node.GetValueKind() == JsonValueKind.String
                ? node.GetValue<string>()
                : node.ToString();
            return string.Equals(v, "1", StringComparison.Ordinal)
                   || string.Equals(v, "true", StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    private bool HasUsablePresetMarketplace()
    {
        var names = ResolveConfiguredMarketplaceNames();
        if (names.Count == 0) return false;
        var known = LoadKnownMarketplaces();
        foreach (var name in names)
        {
            if (known.TryGetValue(name, out var entry)
                && MarketplaceHasManifest(entry.InstallLocation ?? Path.Combine(MarketplacesRoot, name)))
                return true;
            if (MarketplaceHasManifest(Path.Combine(MarketplacesRoot, name)))
                return true;
        }

        return false;
    }

    private static bool MarketplaceHasManifest(string? dir)
    {
        if (string.IsNullOrWhiteSpace(dir) || !Directory.Exists(dir)) return false;
        return File.Exists(Path.Combine(dir, ".claude-plugin", "marketplace.json"));
    }

    private static Dictionary<string, KnownMarketplaceEntry> LoadKnownMarketplaces()
    {
        var path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".claude",
            "plugins",
            "known_marketplaces.json");
        var map = new Dictionary<string, KnownMarketplaceEntry>(StringComparer.OrdinalIgnoreCase);
        if (!File.Exists(path)) return map;
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return map;
            foreach (var prop in doc.RootElement.EnumerateObject())
            {
                string? repo = null;
                string? install = null;
                if (prop.Value.TryGetProperty("source", out var src)
                    && src.ValueKind == JsonValueKind.Object
                    && src.TryGetProperty("repo", out var r))
                    repo = r.GetString();
                if (prop.Value.TryGetProperty("installLocation", out var loc))
                    install = loc.GetString();
                map[prop.Name] = new KnownMarketplaceEntry(repo, install);
            }
        }
        catch
        {
            /* ignore */
        }

        return map;
    }

    private static string? ExtractGithubRepo(string normalized)
    {
        try
        {
            if (!Uri.TryCreate(normalized.Split('#')[0], UriKind.Absolute, out var uri))
                return null;
            if (!uri.Host.Contains("github", StringComparison.OrdinalIgnoreCase))
                return null;
            var segs = uri.AbsolutePath.Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
            if (segs.Length < 2) return null;
            var repo = segs[1];
            if (repo.EndsWith(".git", StringComparison.OrdinalIgnoreCase))
                repo = repo[..^4];
            return $"{segs[0]}/{repo}";
        }
        catch
        {
            return null;
        }
    }

    private Dictionary<string, CatalogPluginEntry> LoadCatalogFromMarketplaces(IReadOnlyList<string> marketNames)
    {
        var catalog = new Dictionary<string, CatalogPluginEntry>(StringComparer.OrdinalIgnoreCase);
        var known = LoadKnownMarketplaces();
        foreach (var market in marketNames)
        {
            var dir = known.TryGetValue(market, out var entry) && !string.IsNullOrWhiteSpace(entry.InstallLocation)
                ? entry.InstallLocation!
                : Path.Combine(MarketplacesRoot, market);
            var manifest = Path.Combine(dir, ".claude-plugin", "marketplace.json");
            if (!File.Exists(manifest)) continue;
            try
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(manifest));
                var root = doc.RootElement;
                var mpName = root.TryGetProperty("name", out var n) ? n.GetString() ?? market : market;
                if (!root.TryGetProperty("plugins", out var plugins) || plugins.ValueKind != JsonValueKind.Array)
                    continue;
                foreach (var p in plugins.EnumerateArray())
                {
                    var name = p.TryGetProperty("name", out var pn) ? pn.GetString() : null;
                    if (string.IsNullOrWhiteSpace(name)) continue;
                    var pluginId = $"{name}@{mpName}";
                    var desc = p.TryGetProperty("description", out var d) ? d.GetString() : null;
                    var ver = p.TryGetProperty("version", out var v) ? v.GetString() : null;
                    catalog[pluginId] = new CatalogPluginEntry(name!, mpName, desc, ver);
                }
            }
            catch
            {
                /* skip broken manifest */
            }
        }

        return catalog;
    }

    private static void MergeAvailableFromCli(
        Dictionary<string, CatalogPluginEntry> catalog,
        IReadOnlyList<string> marketNames)
    {
        var (ok, raw) = RunClaude("plugin list --available --json");
        if (!ok || string.IsNullOrWhiteSpace(raw)) return;
        try
        {
            using var doc = JsonDocument.Parse(ExtractJsonPayload(raw));
            var root = doc.RootElement;
            JsonElement available = default;
            if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("available", out var av))
                available = av;
            else if (root.ValueKind == JsonValueKind.Array)
                available = root;
            else
                return;

            if (available.ValueKind != JsonValueKind.Array) return;
            var allow = new HashSet<string>(marketNames, StringComparer.OrdinalIgnoreCase);
            foreach (var item in available.EnumerateArray())
            {
                var mp = item.TryGetProperty("marketplaceName", out var m) ? m.GetString() : null;
                if (string.IsNullOrEmpty(mp) || !allow.Contains(mp)) continue;
                var pluginId = item.TryGetProperty("pluginId", out var idEl) ? idEl.GetString() : null;
                var name = item.TryGetProperty("name", out var nEl) ? nEl.GetString() : null;
                if (string.IsNullOrWhiteSpace(pluginId) && !string.IsNullOrWhiteSpace(name))
                    pluginId = $"{name}@{mp}";
                if (string.IsNullOrWhiteSpace(pluginId)) continue;
                name ??= SplitPluginId(pluginId, out var n2, out _) ? n2 : pluginId;
                var desc = item.TryGetProperty("description", out var d) ? d.GetString() : null;
                string? ver = null;
                if (item.TryGetProperty("version", out var v)) ver = v.GetString();
                else if (item.TryGetProperty("source", out var src) && src.ValueKind == JsonValueKind.Object
                         && src.TryGetProperty("ref", out var r))
                    ver = r.GetString();
                catalog[pluginId!] = new CatalogPluginEntry(name!, mp!, desc, ver);
            }
        }
        catch
        {
            /* ignore */
        }
    }

    /// <summary>本地校验已装插件：仅信任 CLI 与 installed_plugins.json（cache 目录是下载缓存，不能当已装）。</summary>
    private Dictionary<string, string?> DiscoverInstalledPlugins(IReadOnlyList<string> marketNames)
    {
        var map = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
        MergeInstalledFromCli(map);
        MergeInstalledFromJsonFile(map);
        // cache 仅补全「确已安装」条目的版本号，避免 marketplace 下载缓存冒充已装（导致更新失败：not installed）
        EnrichInstalledVersionsFromCacheDirs(map, marketNames);
        return map;
    }

    private static void MergeInstalledFromCli(Dictionary<string, string?> map)
    {
        var (ok, raw) = RunClaude("plugin list --json");
        if (!ok || string.IsNullOrWhiteSpace(raw)) return;
        try
        {
            using var doc = JsonDocument.Parse(ExtractJsonPayload(raw));
            var root = doc.RootElement;
            JsonElement list = default;
            if (root.ValueKind == JsonValueKind.Array) list = root;
            else if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("installed", out var inst))
                list = inst;
            else if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("plugins", out var plugins))
                list = plugins;
            else return;

            if (list.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in list.EnumerateArray())
                    TryAddInstalledItem(map, item);
            }
            else if (list.ValueKind == JsonValueKind.Object)
            {
                foreach (var prop in list.EnumerateObject())
                {
                    if (prop.Value.ValueKind == JsonValueKind.Array && prop.Value.GetArrayLength() > 0)
                    {
                        var ver = prop.Value[0].TryGetProperty("version", out var v) ? v.GetString() : null;
                        map[prop.Name] = ver ?? map.GetValueOrDefault(prop.Name);
                    }
                    else
                        map[prop.Name] = map.GetValueOrDefault(prop.Name);
                }
            }
        }
        catch
        {
            /* ignore */
        }
    }

    private static void TryAddInstalledItem(Dictionary<string, string?> map, JsonElement item)
    {
        if (item.ValueKind == JsonValueKind.String)
        {
            var id = item.GetString();
            if (!string.IsNullOrWhiteSpace(id)) map[id!] = map.GetValueOrDefault(id!);
            return;
        }

        if (item.ValueKind != JsonValueKind.Object) return;
        var pluginId = item.TryGetProperty("pluginId", out var idEl) ? idEl.GetString() : null;
        if (string.IsNullOrWhiteSpace(pluginId))
        {
            var name = item.TryGetProperty("name", out var n) ? n.GetString() : null;
            var mp = item.TryGetProperty("marketplaceName", out var m) ? m.GetString() : null;
            if (!string.IsNullOrWhiteSpace(name) && !string.IsNullOrWhiteSpace(mp))
                pluginId = $"{name}@{mp}";
        }

        if (string.IsNullOrWhiteSpace(pluginId)) return;
        var ver = item.TryGetProperty("version", out var v) ? v.GetString() : null;
        if (string.IsNullOrWhiteSpace(ver) && item.TryGetProperty("installedVersion", out var iv))
            ver = iv.GetString();
        map[pluginId!] = ver ?? map.GetValueOrDefault(pluginId!);
    }

    private static void MergeInstalledFromJsonFile(Dictionary<string, string?> map)
    {
        var path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".claude",
            "plugins",
            "installed_plugins.json");
        if (!File.Exists(path)) return;
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            if (!doc.RootElement.TryGetProperty("plugins", out var plugins)) return;
            if (plugins.ValueKind == JsonValueKind.Object)
            {
                foreach (var prop in plugins.EnumerateObject())
                {
                    string? ver = null;
                    if (prop.Value.ValueKind == JsonValueKind.Array && prop.Value.GetArrayLength() > 0)
                    {
                        var first = prop.Value[0];
                        if (first.ValueKind == JsonValueKind.Object && first.TryGetProperty("version", out var v))
                            ver = v.GetString();
                        else if (first.ValueKind == JsonValueKind.String)
                            ver = first.GetString();
                    }
                    else if (prop.Value.ValueKind == JsonValueKind.Object
                             && prop.Value.TryGetProperty("version", out var v2))
                        ver = v2.GetString();

                    map[prop.Name] = ver ?? map.GetValueOrDefault(prop.Name);
                }
            }
        }
        catch
        {
            /* ignore */
        }
    }

    private static void EnrichInstalledVersionsFromCacheDirs(
        Dictionary<string, string?> map,
        IReadOnlyList<string> marketNames)
    {
        if (map.Count == 0) return;

        var cacheRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".claude",
            "plugins",
            "cache");
        if (!Directory.Exists(cacheRoot)) return;

        IEnumerable<string> markets = marketNames.Count > 0
            ? marketNames
            : Directory.EnumerateDirectories(cacheRoot)
                .Select(Path.GetFileName)
                .Where(n => !string.IsNullOrWhiteSpace(n))
                .Select(n => n!);

        foreach (var market in markets)
        {
            if (string.IsNullOrWhiteSpace(market)) continue;
            var mpDir = Path.Combine(cacheRoot, market);
            if (!Directory.Exists(mpDir)) continue;
            foreach (var pluginDir in Directory.EnumerateDirectories(mpDir))
            {
                var name = Path.GetFileName(pluginDir);
                if (string.IsNullOrWhiteSpace(name)) continue;
                var pluginId = $"{name}@{market}";
                if (!map.ContainsKey(pluginId)) continue;
                if (!string.IsNullOrWhiteSpace(map[pluginId])) continue;

                // 跳过已标记 orphaned 的缓存版本
                var versions = Directory.EnumerateDirectories(pluginDir)
                    .Where(dir => !File.Exists(Path.Combine(dir, ".orphaned_at")))
                    .Select(Path.GetFileName)
                    .Where(v => !string.IsNullOrWhiteSpace(v))
                    .Cast<string>()
                    .OrderByDescending(v => v, StringComparer.OrdinalIgnoreCase)
                    .ToList();
                if (versions.Count == 0) continue;
                map[pluginId] = versions[0];
            }
        }
    }

    private static string ExtractJsonPayload(string raw)
    {
        var text = SanitizeCliText(raw);
        var startObj = text.IndexOf('{');
        var startArr = text.IndexOf('[');
        if (startObj < 0 && startArr < 0) return text;
        if (startObj < 0) return text[startArr..];
        if (startArr < 0) return text[startObj..];
        return text[Math.Min(startObj, startArr)..];
    }

    private static bool SplitPluginId(string pluginId, out string name, out string marketplace)
    {
        name = pluginId;
        marketplace = "";
        var at = pluginId.LastIndexOf('@');
        if (at <= 0 || at >= pluginId.Length - 1) return false;
        name = pluginId[..at];
        marketplace = pluginId[(at + 1)..];
        return true;
    }

    private static bool VersionsEqual(string a, string b)
    {
        static string Norm(string s) => s.Trim().TrimStart('v', 'V');
        return string.Equals(Norm(a), Norm(b), StringComparison.OrdinalIgnoreCase);
    }

    private readonly record struct CatalogPluginEntry(
        string Name,
        string Marketplace,
        string? Description,
        string? Version);

    private readonly record struct KnownMarketplaceEntry(string? Repo, string? InstallLocation);

    private ClaudePresetsFile LoadPresets()
    {
        var root = AppPaths.ResolveSeedsRoot();
        if (root is null) return new ClaudePresetsFile();
        var path = Path.Combine(root, "dev", "claude", "presets.json");
        if (!File.Exists(path))
            path = Path.Combine(root, "tools", "claude", "presets.json");
        if (!File.Exists(path))
            path = Path.Combine(root, "claude", "presets.json");
        if (!File.Exists(path)) return new ClaudePresetsFile();
        try
        {
            return JsonSerializer.Deserialize<ClaudePresetsFile>(File.ReadAllText(path)) ?? new();
        }
        catch
        {
            return new ClaudePresetsFile();
        }
    }

    private ClaudeSecretsFile LoadSecrets()
    {
        if (!File.Exists(SecretsPath)) return new ClaudeSecretsFile();
        try
        {
            return JsonSerializer.Deserialize<ClaudeSecretsFile>(File.ReadAllText(SecretsPath))
                   ?? new ClaudeSecretsFile();
        }
        catch
        {
            return new ClaudeSecretsFile();
        }
    }

    private void SaveSecrets(ClaudeSecretsFile secrets)
    {
        File.WriteAllText(SecretsPath, JsonSerializer.Serialize(secrets, JsonWrite));
    }

    private void MergeEnv(Dictionary<string, string?> updates, IEnumerable<string> removeKeys)
    {
        var dir = Path.GetDirectoryName(SettingsPath)!;
        Directory.CreateDirectory(dir);

        JsonObject root;
        if (File.Exists(SettingsPath))
        {
            try
            {
                root = JsonNode.Parse(File.ReadAllText(SettingsPath)) as JsonObject ?? new JsonObject();
            }
            catch
            {
                root = new JsonObject();
            }
        }
        else
        {
            root = new JsonObject();
        }

        var env = root["env"] as JsonObject ?? new JsonObject();
        foreach (var key in removeKeys)
            env.Remove(key);

        foreach (var (k, v) in updates)
        {
            if (string.IsNullOrWhiteSpace(v))
                env.Remove(k);
            else
                env[k] = v;
        }

        if (env.Count == 0)
            root.Remove("env");
        else
            root["env"] = env;

        File.WriteAllText(SettingsPath, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    private static (bool Ok, string Detail) RunClaude(string args)
    {
        try
        {
            var utf8 = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);
            var psi = new ProcessStartInfo
            {
                FileName = "claude",
                Arguments = args,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                StandardOutputEncoding = utf8,
                StandardErrorEncoding = utf8,
            };
            // 避免 git 在无交互环境下卡在 SSH/凭据提示；强制 github SSH → HTTPS
            psi.Environment["GIT_TERMINAL_PROMPT"] = "0";
            psi.Environment["LANG"] = "en_US.UTF-8";
            psi.Environment["LC_ALL"] = "en_US.UTF-8";
            psi.Environment["GIT_CONFIG_COUNT"] = "2";
            psi.Environment["GIT_CONFIG_KEY_0"] = "url.https://github.com/.insteadOf";
            psi.Environment["GIT_CONFIG_VALUE_0"] = "git@github.com:";
            psi.Environment["GIT_CONFIG_KEY_1"] = "url.https://github.com/.insteadOf";
            psi.Environment["GIT_CONFIG_VALUE_1"] = "ssh://git@github.com/";

            using var p = Process.Start(psi);
            if (p is null) return (false, "无法启动 claude");

            // 并行读 stdout/stderr，避免管道互锁卡死
            var stdoutTask = p.StandardOutput.ReadToEndAsync();
            var stderrTask = p.StandardError.ReadToEndAsync();
            if (!p.WaitForExit(60_000))
            {
                try { p.Kill(entireProcessTree: true); } catch { /* ignore */ }
                return (false, "claude 执行超时（60s）");
            }

            var stdout = stdoutTask.GetAwaiter().GetResult();
            var stderr = stderrTask.GetAwaiter().GetResult();
            var detail = SanitizeCliText(stdout + "\n" + stderr);
            return (p.ExitCode == 0, detail.Length > 0 ? detail : $"exit={p.ExitCode}");
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
    }

    /// <summary>
    /// 注册 marketplace：HTTPS 拉仓，避开 SSH known_hosts；已存在/文件占用则跳过或重试。
    /// 网络瞬时失败会自动重试。
    /// </summary>
    private static (bool Ok, string Detail) AddMarketplace(string source)
    {
        var normalized = NormalizeMarketplaceSource(source);
        var folderHint = MarketplaceFolderHint(normalized);

        if (IsMarketplacePresent(normalized, folderHint))
            return (true, "已存在，跳过");

        string detail = "";
        for (var attempt = 1; attempt <= 3; attempt++)
        {
            if (attempt > 1)
                Thread.Sleep(1000 * attempt);

            var (ok, raw) = RunClaude($"plugin marketplace add {EscapeArg(normalized)}");
            detail = raw;
            if (ok) return (true, SummarizeCliDetail(detail));
            if (LooksAlreadyPresent(detail))
                return (true, "已存在，跳过");

            if (LooksBusy(detail))
            {
                try
                {
                    if (!string.IsNullOrEmpty(folderHint))
                        TryClearStaleMarketplaceDir(folderHint);
                }
                catch
                {
                    /* ignore */
                }

                Thread.Sleep(800);
                (ok, detail) = RunClaude($"plugin marketplace add {EscapeArg(normalized)}");
                if (ok || LooksAlreadyPresent(detail))
                    return (true, ok ? SummarizeCliDetail(detail) : "已存在，跳过");

                return (
                    false,
                    "本地 marketplace 目录被占用（EBUSY）。请关闭其它 Claude/相关终端后重试，或手动删除："
                    + (string.IsNullOrEmpty(folderHint)
                        ? Path.Combine(MarketplacesRoot, "…")
                        : Path.Combine(MarketplacesRoot, folderHint)));
            }

            if (detail.Contains("Host key verification failed", StringComparison.OrdinalIgnoreCase)
                || detail.Contains("known_hosts", StringComparison.OrdinalIgnoreCase))
            {
                return (
                    false,
                    "Git 仍在使用 SSH 且未信任 github.com。已改用 HTTPS 源；若仍失败请检查 git 全局 url.insteadOf，或先执行：ssh -T git@github.com");
            }

            if (!LooksTransientNetwork(detail))
                break;
        }

        return (false, SummarizeCliDetail(detail));
    }

    private static bool LooksTransientNetwork(string detail) =>
        detail.Contains("Connection was reset", StringComparison.OrdinalIgnoreCase)
        || detail.Contains("Recv failure", StringComparison.OrdinalIgnoreCase)
        || detail.Contains("unable to access", StringComparison.OrdinalIgnoreCase)
        || detail.Contains("Could not resolve", StringComparison.OrdinalIgnoreCase)
        || detail.Contains("Failed to connect", StringComparison.OrdinalIgnoreCase)
        || detail.Contains("timed out", StringComparison.OrdinalIgnoreCase)
        || detail.Contains("TLS", StringComparison.OrdinalIgnoreCase)
        || detail.Contains("SSL", StringComparison.OrdinalIgnoreCase);

    /// <summary>owner/repo → https://github.com/owner/repo.git，强制走 HTTPS。</summary>
    internal static string NormalizeMarketplaceSource(string source)
    {
        var s = source.Trim();
        if (s.Length == 0) return s;
        if (s.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
            || s.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || s.StartsWith("git@", StringComparison.OrdinalIgnoreCase)
            || s.StartsWith("ssh://", StringComparison.OrdinalIgnoreCase)
            || s.StartsWith("file:", StringComparison.OrdinalIgnoreCase)
            || Directory.Exists(s))
        {
            // git@github.com:owner/repo.git → https
            if (s.StartsWith("git@github.com:", StringComparison.OrdinalIgnoreCase))
            {
                var path = s["git@github.com:".Length..].TrimEnd('/');
                if (path.EndsWith(".git", StringComparison.OrdinalIgnoreCase))
                    path = path[..^4];
                return $"https://github.com/{path}.git";
            }

            return s;
        }

        // GitHub shorthand owner/repo[@ref]
        var at = s.IndexOf('@');
        var repoPart = at > 0 ? s[..at] : s;
        var refPart = at > 0 ? s[(at + 1)..] : null;
        repoPart = repoPart.Trim('/');
        if (repoPart.Count(c => c == '/') == 1)
        {
            var url = $"https://github.com/{repoPart}.git";
            if (!string.IsNullOrWhiteSpace(refPart))
                url += $"#{refPart.Trim()}";
            return url;
        }

        return s;
    }

    private static string? MarketplaceFolderHint(string normalized)
    {
        // Claude 本地目录名多为仓库名：superpowers-marketplace
        try
        {
            if (Uri.TryCreate(normalized.Split('#')[0], UriKind.Absolute, out var uri)
                && uri.Host.Contains("github", StringComparison.OrdinalIgnoreCase))
            {
                var segs = uri.AbsolutePath.Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
                if (segs.Length >= 2)
                {
                    var repo = segs[1];
                    if (repo.EndsWith(".git", StringComparison.OrdinalIgnoreCase))
                        repo = repo[..^4];
                    return repo;
                }
            }
        }
        catch
        {
            /* ignore */
        }

        return null;
    }

    /// <summary>以本地 marketplace.json 为准；登记了但 clone 缺失视为未就绪。</summary>
    private static bool IsMarketplacePresent(string normalized, string? folderHint)
    {
        var known = LoadKnownMarketplaces();
        var repo = ExtractGithubRepo(normalized);
        var candidates = new List<string>();
        if (!string.IsNullOrEmpty(folderHint)) candidates.Add(folderHint);
        if (repo is not null)
        {
            var shortName = repo.Contains('/') ? repo[(repo.LastIndexOf('/') + 1)..] : repo;
            if (!string.IsNullOrWhiteSpace(shortName)) candidates.Add(shortName);
        }

        foreach (var (name, entry) in known)
        {
            if (repo is null || !string.Equals(entry.Repo, repo, StringComparison.OrdinalIgnoreCase))
                continue;
            var dir = entry.InstallLocation ?? Path.Combine(MarketplacesRoot, name);
            return MarketplaceHasManifest(dir);
        }

        foreach (var name in candidates.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (MarketplaceHasManifest(Path.Combine(MarketplacesRoot, name)))
                return true;
        }

        return false;
    }

    private static void TryClearStaleMarketplaceDir(string folderHint)
    {
        var dir = Path.Combine(MarketplacesRoot, folderHint);
        if (!Directory.Exists(dir)) return;
        try
        {
            Directory.Delete(dir, recursive: true);
        }
        catch
        {
            /* 仍被占用则留给上层报可读错误 */
        }
    }

    private static bool LooksAlreadyPresent(string detail) =>
        detail.Contains("already", StringComparison.OrdinalIgnoreCase)
        || detail.Contains("exists", StringComparison.OrdinalIgnoreCase)
        || detail.Contains("已存在", StringComparison.Ordinal);

    private static bool LooksBusy(string detail) =>
        detail.Contains("EBUSY", StringComparison.OrdinalIgnoreCase)
        || detail.Contains("resource busy", StringComparison.OrdinalIgnoreCase)
        || detail.Contains("locked", StringComparison.OrdinalIgnoreCase);

    private static string SanitizeCliText(string raw)
    {
        if (string.IsNullOrEmpty(raw)) return "";
        var text = AnsiRegex.Replace(raw, "");
        text = text.Replace("\r\n", "\n").Replace('\r', '\n');
        while (text.Contains("\n\n\n", StringComparison.Ordinal))
            text = text.Replace("\n\n\n", "\n\n", StringComparison.Ordinal);
        return text.Trim();
    }

    private static string SummarizeCliDetail(string detail)
    {
        if (string.IsNullOrWhiteSpace(detail)) return "";
        var lines = detail.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var take = Math.Min(6, lines.Length);
        return string.Join(" ", lines.Skip(lines.Length - take));
    }

    private static string? TryCommandVersion(string cmd, string args)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = cmd,
                Arguments = args,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var p = Process.Start(psi);
            if (p is null) return null;
            var text = (p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd()).Trim();
            p.WaitForExit(8000);
            return p.ExitCode == 0 || text.Length > 0 ? text.Split('\n')[0].Trim() : null;
        }
        catch
        {
            return null;
        }
    }

    private static bool IsWingetPackagePresent(string packageId)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "winget",
                Arguments = $"list --id {packageId} -e",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var p = Process.Start(psi);
            if (p is null) return false;
            var outText = p.StandardOutput.ReadToEnd();
            p.WaitForExit(15000);
            return p.ExitCode == 0 && outText.Contains(packageId, StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    private static bool HasMaskedKey(ClaudeSecretsFile s) =>
        !string.IsNullOrWhiteSpace(s.Api?.ApiKey) || !string.IsNullOrWhiteSpace(s.Api?.AuthToken);

    private static string? Mask(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        if (value.Length <= 8) return "****";
        return value[..3] + "…" + value[^2..];
    }

    private static string EscapeArg(string s) =>
        s.Contains(' ', StringComparison.Ordinal) ? $"\"{s.Replace("\"", "\\\"")}\"" : s;
}

/// <summary>Claude 状态。</summary>
public sealed record ClaudeStatusDto(
    [property: JsonPropertyName("installed")] bool Installed,
    [property: JsonPropertyName("version")] string? Version,
    [property: JsonPropertyName("wingetManaged")] bool WingetManaged,
    [property: JsonPropertyName("settingsExists")] bool SettingsExists,
    [property: JsonPropertyName("apiMode")] string? ApiMode,
    [property: JsonPropertyName("proxyMode")] string? ProxyMode,
    [property: JsonPropertyName("hasSecrets")] bool HasSecrets);

/// <summary>脱敏密钥摘要。</summary>
public sealed record ClaudeSecretsPublicDto(
    [property: JsonPropertyName("apiMode")] string? ApiMode,
    [property: JsonPropertyName("apiKeyMasked")] string? ApiKeyMasked,
    [property: JsonPropertyName("baseUrl")] string? BaseUrl,
    [property: JsonPropertyName("authTokenMasked")] string? AuthTokenMasked,
    [property: JsonPropertyName("proxyMode")] string? ProxyMode,
    [property: JsonPropertyName("httpProxy")] string? HttpProxy,
    [property: JsonPropertyName("httpsProxy")] string? HttpsProxy);

/// <summary>插件列表项。</summary>
public sealed record ClaudePluginDto(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("label")] string Label,
    [property: JsonPropertyName("featured")] bool Featured,
    [property: JsonPropertyName("description")] string? Description = null,
    [property: JsonPropertyName("installedVersion")] string? InstalledVersion = null,
    [property: JsonPropertyName("remoteVersion")] string? RemoteVersion = null,
    [property: JsonPropertyName("updateAvailable")] bool UpdateAvailable = false);

/// <summary>三态插件列表（安装 / 更新 / 卸载）。</summary>
public sealed record ClaudePluginListsDto(
    [property: JsonPropertyName("install")] IReadOnlyList<ClaudePluginDto> Install,
    [property: JsonPropertyName("update")] IReadOnlyList<ClaudePluginDto> Update,
    [property: JsonPropertyName("uninstall")] IReadOnlyList<ClaudePluginDto> Uninstall);

internal sealed class ClaudeSecretsFile
{
    [JsonPropertyName("api")]
    public ClaudeApiSecrets? Api { get; set; }

    [JsonPropertyName("proxy")]
    public ClaudeProxySecrets? Proxy { get; set; }
}

internal sealed class ClaudeApiSecrets
{
    [JsonPropertyName("mode")]
    public string? Mode { get; set; }

    [JsonPropertyName("apiKey")]
    public string? ApiKey { get; set; }

    [JsonPropertyName("baseUrl")]
    public string? BaseUrl { get; set; }

    [JsonPropertyName("authToken")]
    public string? AuthToken { get; set; }
}

internal sealed class ClaudeProxySecrets
{
    [JsonPropertyName("mode")]
    public string? Mode { get; set; }

    [JsonPropertyName("httpProxy")]
    public string? HttpProxy { get; set; }

    [JsonPropertyName("httpsProxy")]
    public string? HttpsProxy { get; set; }
}

internal sealed class ClaudePresetsFile
{
    [JsonPropertyName("marketplaces")]
    public List<ClaudeMarketplace> Marketplaces { get; set; } = [];

    [JsonPropertyName("featuredPlugins")]
    public List<ClaudeFeaturedPlugin> FeaturedPlugins { get; set; } = [];
}

internal sealed class ClaudeMarketplace
{
    [JsonPropertyName("source")]
    public string Source { get; set; } = "";
}

internal sealed class ClaudeFeaturedPlugin
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";
}
