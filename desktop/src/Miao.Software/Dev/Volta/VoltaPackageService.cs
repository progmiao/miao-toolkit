using System.Diagnostics;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Miao.Data;

namespace Miao.Software.Dev.Volta;

/// <summary>
/// Volta 托管包（node / pnpm / yarn）：远程版本清单 + 本机已装/默认/当前。
/// 版本优先读 SQLite 缓存；刷新/静默任务按「从新到旧，直到碰到库中已有版本」增量写入。
/// </summary>
public sealed class VoltaPackageService
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(45) };

    private readonly AppDatabase _db;

    /// <summary>创建服务。</summary>
    public VoltaPackageService(AppDatabase db) => _db = db;

    /// <summary>支持的工具 id → Volta 包名。</summary>
    public static bool IsSupported(string toolId) =>
        toolId is "node" or "pnpm" or "yarn";

    /// <summary>
    /// 列出远程与本机合并后的版本。
    /// </summary>
    /// <param name="toolId">node | pnpm | yarn。</param>
    /// <param name="ltsOnly">兼容字段（已忽略）。</param>
    /// <param name="forceRemote">true 强制与远程增量同步；false 且有缓存则只读库。</param>
    /// <param name="ct">取消令牌。</param>
    public async Task<IReadOnlyList<VoltaVersionDto>> ListAsync(
        string toolId,
        bool ltsOnly,
        bool forceRemote = true,
        CancellationToken ct = default)
    {
        if (!IsSupported(toolId))
            throw new ArgumentException($"不支持的 Volta 工具: {toolId}", nameof(toolId));

        _ = ltsOnly;

        if (toolId == "node")
        {
            var cached = _db.ListPackageVersions("node");
            if (forceRemote || cached.Count == 0)
                await SyncNodeRemoteIncrementalAsync(ct).ConfigureAwait(false);
        }
        else if (forceRemote || _db.ListPackageVersions(toolId).Count == 0)
        {
            await SyncNpmPackageCacheAsync(toolId, ct).ConfigureAwait(false);
        }

        var remote = _db.ListPackageVersions(toolId)
            .Select(r => new VoltaVersionDto(r.Version, r.Lts, r.ReleaseDate, false, false, false))
            .ToList();

        var local = GetVoltaInstalled(toolId);
        var active = GetActiveCommandVersion(toolId);

        var map = new Dictionary<string, VoltaVersionDto>(StringComparer.OrdinalIgnoreCase);
        foreach (var r in remote)
        {
            local.Installed.TryGetValue(r.Version, out var installed);
            map[r.Version] = r with
            {
                Installed = installed,
                IsDefault = string.Equals(local.Default, r.Version, StringComparison.OrdinalIgnoreCase),
                IsCurrent = string.Equals(active, r.Version, StringComparison.OrdinalIgnoreCase),
            };
        }

        foreach (var ver in local.Installed.Keys)
        {
            if (map.ContainsKey(ver)) continue;
            map[ver] = new VoltaVersionDto(
                ver, null, null, true,
                string.Equals(local.Default, ver, StringComparison.OrdinalIgnoreCase),
                string.Equals(active, ver, StringComparison.OrdinalIgnoreCase));
        }

        return map.Values.OrderByDescending(v => ParseVersion(v.Version)).ToList();
    }

    /// <summary>
    /// 拉取 nodejs.org/dist/index.json，按新→旧写入，直到碰到库中已有版本即停止。
    /// </summary>
    private async Task SyncNodeRemoteIncrementalAsync(CancellationToken ct)
    {
        var releases = await Http
            .GetFromJsonAsync<List<NodeReleaseJson>>("https://nodejs.org/dist/index.json", ct)
            .ConfigureAwait(false) ?? [];

        var now = DateTimeOffset.UtcNow.ToString("O");
        var batch = new List<PackageVersionRow>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var r in releases)
        {
            var ver = (r.Version ?? "").TrimStart('v');
            if (string.IsNullOrWhiteSpace(ver) || !seen.Add(ver)) continue;

            if (_db.HasPackageVersion("node", ver))
                break;

            batch.Add(new PackageVersionRow("node", ver, ParseLts(r.Lts), r.Date, now));
        }

        if (batch.Count > 0)
            _db.UpsertPackageVersions(batch);
    }

    /// <summary>
    /// 拉取 npm registry，按新→旧增量写入，直到碰到库中已有版本即停止（首同步最多 80 条）。
    /// </summary>
    private async Task SyncNpmPackageCacheAsync(string package, CancellationToken ct)
    {
        using var resp = await Http.GetAsync($"https://registry.npmjs.org/{package}", ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        await using var stream = await resp.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct).ConfigureAwait(false);

        var root = doc.RootElement;
        if (!root.TryGetProperty("versions", out var versions) || versions.ValueKind != JsonValueKind.Object)
            return;

        string? latest = null;
        if (root.TryGetProperty("dist-tags", out var tags) &&
            tags.TryGetProperty("latest", out var latestEl))
        {
            latest = latestEl.GetString();
        }

        var now = DateTimeOffset.UtcNow.ToString("O");
        var candidates = new List<(string Ver, string? Tag)>();
        foreach (var prop in versions.EnumerateObject())
        {
            var ver = prop.Name;
            if (ver.Contains('-', StringComparison.Ordinal)) continue;
            var tag = string.Equals(ver, latest, StringComparison.OrdinalIgnoreCase) ? "latest" : null;
            candidates.Add((ver, tag));
        }

        var batch = new List<PackageVersionRow>();
        foreach (var (ver, tag) in candidates.OrderByDescending(c => ParseVersion(c.Ver)))
        {
            if (_db.HasPackageVersion(package, ver))
                break;

            batch.Add(new PackageVersionRow(package, ver, tag, null, now));
            // 首同步保护：避免一次写入数千条历史版本
            if (batch.Count >= 80)
                break;
        }

        if (batch.Count > 0)
            _db.UpsertPackageVersions(batch);
    }

    /// <summary>检测是否存在 nvm / fnm。</summary>
    public IReadOnlyList<string> DetectConflicts()
    {
        var list = new List<string>();
        if (GetCommandPath("nvm") is not null) list.Add("nvm");
        if (GetCommandPath("fnm") is not null) list.Add("fnm");
        return list;
    }

    /// <summary>Volta 是否在 PATH 中。</summary>
    public bool IsVoltaAvailable() => GetCommandPath("volta") is not null;

    /// <summary>目录列表展示用版本。</summary>
    public string? GetCatalogDisplayVersion(string toolId)
    {
        if (string.Equals(toolId, "volta", StringComparison.OrdinalIgnoreCase))
            return GetActiveCommandVersion("volta");

        if (!IsSupported(toolId))
            return null;

        var local = GetVoltaInstalled(toolId);
        if (!string.IsNullOrWhiteSpace(local.Default))
            return local.Default;

        return GetActiveCommandVersion(toolId);
    }

    private static string? ParseLts(JsonElement el) =>
        el.ValueKind == JsonValueKind.String ? el.GetString() : null;

    private static (Dictionary<string, bool> Installed, string? Default) GetVoltaInstalled(string toolId)
    {
        var installed = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        string? defaultVer = null;
        if (GetCommandPath("volta") is null) return (installed, null);

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "volta",
                Arguments = $"list {toolId}",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var p = Process.Start(psi);
            if (p is null) return (installed, null);
            var raw = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
            p.WaitForExit(8000);
            var pattern = $@"{Regex.Escape(toolId)}@([0-9]+(?:\.[0-9]+)*)";
            foreach (var line in raw.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                var m = Regex.Match(line, pattern, RegexOptions.IgnoreCase);
                if (!m.Success) continue;
                var ver = m.Groups[1].Value;
                installed[ver] = true;
                if (line.Contains("(default)", StringComparison.OrdinalIgnoreCase))
                    defaultVer = ver;
            }
        }
        catch
        {
            /* ignore */
        }

        return (installed, defaultVer);
    }

    private static string? GetActiveCommandVersion(string toolId)
    {
        try
        {
            RefreshProcessPath();
            if (GetCommandPath(toolId) is null) return null;

            var args = toolId == "node" ? "-v" : "--version";
            var psi = new ProcessStartInfo
            {
                FileName = toolId,
                Arguments = args,
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var p = Process.Start(psi);
            if (p is null) return null;
            var v = p.StandardOutput.ReadToEnd().Trim();
            p.WaitForExit(5000);
            var m = Regex.Match(v, @"([0-9]+(?:\.[0-9]+)*)");
            return m.Success ? m.Groups[1].Value : null;
        }
        catch
        {
            return null;
        }
    }

    private static string? GetCommandPath(string name)
    {
        try
        {
            RefreshProcessPath();
            var psi = new ProcessStartInfo
            {
                FileName = "where.exe",
                Arguments = name,
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var p = Process.Start(psi);
            if (p is null) return null;
            var line = p.StandardOutput.ReadLine();
            p.WaitForExit(3000);
            return string.IsNullOrWhiteSpace(line) ? null : line.Trim();
        }
        catch
        {
            return null;
        }
    }

    private static void RefreshProcessPath()
    {
        try
        {
            var machine = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.Machine) ?? "";
            var user = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User) ?? "";
            Environment.SetEnvironmentVariable("Path", machine + ";" + user);
        }
        catch
        {
            /* ignore */
        }
    }

    private static Version ParseVersion(string v)
    {
        var core = v.Split('-')[0];
        return Version.TryParse(core, out var ver) ? ver : new Version(0, 0);
    }

    private sealed class NodeReleaseJson
    {
        [JsonPropertyName("version")]
        public string? Version { get; set; }

        [JsonPropertyName("lts")]
        public JsonElement Lts { get; set; }

        [JsonPropertyName("date")]
        public string? Date { get; set; }
    }
}

/// <summary>Volta 版本行 DTO。</summary>
public sealed record VoltaVersionDto(
    [property: JsonPropertyName("version")] string Version,
    [property: JsonPropertyName("lts")] string? Lts,
    [property: JsonPropertyName("date")] string? Date,
    [property: JsonPropertyName("installed")] bool Installed,
    [property: JsonPropertyName("isDefault")] bool IsDefault,
    [property: JsonPropertyName("isCurrent")] bool IsCurrent);
