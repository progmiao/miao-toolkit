using System.Diagnostics;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Miao.Software.Volta;

/// <summary>
/// Volta 托管包（node / pnpm / yarn）：远程版本清单 + 本机已装/默认/当前。
/// </summary>
public sealed class VoltaPackageService
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(45) };

    /// <summary>支持的工具 id → Volta 包名。</summary>
    public static bool IsSupported(string toolId) =>
        toolId is "node" or "pnpm" or "yarn";

    /// <summary>
    /// 列出远程与本机合并后的版本。
    /// </summary>
    /// <param name="toolId">node | pnpm | yarn。</param>
    /// <param name="ltsOnly">仅 node 有效：只显示 LTS（仍附带本机已装非 LTS）。</param>
    /// <param name="ct">取消令牌。</param>
    public async Task<IReadOnlyList<VoltaVersionDto>> ListAsync(
        string toolId,
        bool ltsOnly,
        CancellationToken ct = default)
    {
        if (!IsSupported(toolId))
            throw new ArgumentException($"不支持的 Volta 工具: {toolId}", nameof(toolId));

        var remote = toolId == "node"
            ? await FetchNodeRemoteAsync(ltsOnly, ct).ConfigureAwait(false)
            : await FetchNpmPackageVersionsAsync(toolId, ct).ConfigureAwait(false);

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

    /// <summary>检测是否存在 nvm / fnm（与 Volta 冲突提示用）。</summary>
    public IReadOnlyList<string> DetectConflicts()
    {
        var list = new List<string>();
        if (GetCommandPath("nvm") is not null) list.Add("nvm");
        if (GetCommandPath("fnm") is not null) list.Add("fnm");
        return list;
    }

    /// <summary>Volta 是否在 PATH 中。</summary>
    public bool IsVoltaAvailable() => GetCommandPath("volta") is not null;

    private static async Task<List<VoltaVersionDto>> FetchNodeRemoteAsync(bool ltsOnly, CancellationToken ct)
    {
        var releases = await Http
            .GetFromJsonAsync<List<NodeReleaseJson>>("https://nodejs.org/dist/index.json", ct)
            .ConfigureAwait(false) ?? [];

        var list = new List<VoltaVersionDto>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var r in releases)
        {
            var ver = (r.Version ?? "").TrimStart('v');
            if (string.IsNullOrWhiteSpace(ver) || !seen.Add(ver)) continue;
            var ltsName = ParseLts(r.Lts);
            if (ltsOnly && string.IsNullOrWhiteSpace(ltsName)) continue;
            list.Add(new VoltaVersionDto(ver, ltsName, r.Date, false, false, false));
        }

        return list;
    }

    private static async Task<List<VoltaVersionDto>> FetchNpmPackageVersionsAsync(string package, CancellationToken ct)
    {
        using var resp = await Http.GetAsync($"https://registry.npmjs.org/{package}", ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        await using var stream = await resp.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct).ConfigureAwait(false);

        var root = doc.RootElement;
        var list = new List<VoltaVersionDto>();
        if (!root.TryGetProperty("versions", out var versions) || versions.ValueKind != JsonValueKind.Object)
            return list;

        string? latest = null;
        if (root.TryGetProperty("dist-tags", out var tags) &&
            tags.TryGetProperty("latest", out var latestEl))
        {
            latest = latestEl.GetString();
        }

        foreach (var prop in versions.EnumerateObject())
        {
            var ver = prop.Name;
            if (ver.Contains('-', StringComparison.Ordinal)) continue; // 跳过预发布，降低噪声
            var tag = string.Equals(ver, latest, StringComparison.OrdinalIgnoreCase) ? "latest" : null;
            list.Add(new VoltaVersionDto(ver, tag, null, false, false, false));
        }

        // npm 版本很多：保留最近 80 个稳定版
        return list
            .OrderByDescending(v => ParseVersion(v.Version))
            .Take(80)
            .ToList();
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
        if (GetCommandPath(toolId) is null) return null;
        try
        {
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
            // yarn/pnpm 可能输出多行，取首个版本号
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
