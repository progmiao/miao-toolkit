using System.Diagnostics;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using Miao.Common.Software;
using Miao.Data;

namespace Miao.Software.Detect;

/// <summary>
/// 按软件声明的 update.strategy 探测是否有可用更新，并写入 tool_state.detail。
/// 有更新时 detail 形如 <c>update:{strategy}</c> 或 <c>update:{strategy}:{latestVersion}</c>。
/// </summary>
public static class UpdateProbe
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };

    /// <summary>
    /// 在已安装探测之后调用：有更新则 detail 以 <c>update:</c> 开头；否则清除旧 update: 前缀。
    /// </summary>
    public static void ProbeAndStore(AppDatabase db, string toolId, SoftwareDefinition? manifest)
    {
        var state = db.GetToolState(toolId);
        if (state is null || !string.Equals(state.Status, "installed", StringComparison.OrdinalIgnoreCase))
        {
            ClearUpdateMark(db, toolId, state);
            return;
        }

        var strategy = manifest?.Install?.Update?.Strategy?.Trim().ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(strategy) || strategy == "none")
        {
            ClearUpdateMark(db, toolId, state);
            return;
        }

        if (toolId is "node" or "pnpm" or "yarn")
        {
            ClearUpdateMark(db, toolId, state);
            return;
        }

        try
        {
            // null = 无更新；"" = 有更新但未知版本；非空 = 最新版本号
            var latest = strategy switch
            {
                "winget" => ProbeWinget(manifest!.Install!),
                "npm" => ProbeNpm(manifest!.Install!, state.Version),
                "gitee-release" => ProbeGiteeRelease(manifest!.Install!),
                "github-release" => ProbeGithubRelease(manifest!.Install!, state.Version),
                "hermes" => ProbeHermes(),
                _ => null,
            };

            // 可用版与本机版相同 → 视为无更新（winget 升级后偶发仍带 Available 列）
            if (latest is { Length: > 0 }
                && !string.IsNullOrWhiteSpace(state.Version)
                && string.Equals(
                    NormalizeTag(latest),
                    NormalizeTag(state.Version!),
                    StringComparison.OrdinalIgnoreCase))
            {
                ClearUpdateMark(db, toolId, state);
                return;
            }

            if (latest is not null)
            {
                var mark = latest.Length == 0
                    ? $"update:{strategy}"
                    : $"update:{strategy}:{latest}";
                var prior = state.Detail;
                if (prior is { Length: > 0 } && !prior.StartsWith("update:", StringComparison.OrdinalIgnoreCase))
                    mark = $"{mark}|{prior}";
                db.UpsertToolState(toolId, "installed", state.Version, mark);
            }
            else
            {
                ClearUpdateMark(db, toolId, state);
            }
        }
        catch
        {
            // 网络/超时：保留原状态
        }
    }

    /// <summary>
    /// 从 tool_state.detail 解析最新可用版本（无则 null）。
    /// </summary>
    public static string? TryParseLatestVersion(string? detail)
    {
        if (string.IsNullOrWhiteSpace(detail) ||
            !detail.StartsWith("update:", StringComparison.OrdinalIgnoreCase))
            return null;

        var body = detail["update:".Length..];
        var pipe = body.IndexOf('|');
        if (pipe >= 0) body = body[..pipe];

        var colon = body.IndexOf(':');
        if (colon < 0) return null;
        var ver = body[(colon + 1)..].Trim();
        return string.IsNullOrWhiteSpace(ver) ? null : ver;
    }

    private static void ClearUpdateMark(AppDatabase db, string toolId, ToolStateRow? state)
    {
        if (state is null) return;
        if (state.Detail is null || !state.Detail.StartsWith("update:", StringComparison.OrdinalIgnoreCase))
            return;

        var rest = state.Detail;
        var idx = rest.IndexOf('|');
        var cleaned = idx >= 0 ? rest[(idx + 1)..] : null;
        if (string.IsNullOrWhiteSpace(cleaned))
            cleaned = null;
        db.UpsertToolState(toolId, state.Status, state.Version, cleaned);
    }

    /// <summary>WinGet：有 Available 列时返回可用版本；否则 null。</summary>
    private static string? ProbeWinget(SoftwareInstallManifest install)
    {
        if (string.IsNullOrWhiteSpace(install.PackageId)) return null;

        var source = string.IsNullOrWhiteSpace(install.WingetSource)
            ? ""
            : $" --source {install.WingetSource}";

        var psi = new ProcessStartInfo
        {
            FileName = "winget",
            Arguments =
                $"list --id {install.PackageId} -e --disable-interactivity{source}",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };

        using var p = Process.Start(psi);
        if (p is null) return null;
        var output = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
        if (!p.WaitForExit(25000))
        {
            try { p.Kill(entireProcessTree: true); } catch { /* ignore */ }
            return null;
        }

        foreach (var line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (!line.Contains(install.PackageId, StringComparison.OrdinalIgnoreCase))
                continue;
            var versions = Regex.Matches(line, @"\b\d+(?:\.\d+)+\b")
                .Select(m => m.Value)
                .ToList();
            // Version + Available → 取最后一个为可用版本；两列相同则无更新
            if (versions.Count >= 2)
            {
                var installed = versions[^2];
                var available = versions[^1];
                if (string.Equals(
                        NormalizeTag(installed),
                        NormalizeTag(available),
                        StringComparison.OrdinalIgnoreCase))
                    return null;
                return available;
            }
        }

        return null;
    }

    /// <summary>Gitee Release：有更新时返回远程 tag。</summary>
    private static string? ProbeGiteeRelease(SoftwareInstallManifest install)
    {
        var owner = install.GiteeOwner ?? "updateme";
        var repo = install.GiteeRepo ?? "terminal-buddy";
        var asset = install.AssetName ?? "terminal-buddy.exe";
        var api = $"https://gitee.com/api/v5/repos/{owner}/{repo}/releases/latest";

        using var resp = Http.GetAsync(api).GetAwaiter().GetResult();
        if (!resp.IsSuccessStatusCode) return null;
        using var doc = JsonDocument.Parse(resp.Content.ReadAsStream());
        var tag = doc.RootElement.TryGetProperty("tag_name", out var t) ? t.GetString() : null;
        if (string.IsNullOrWhiteSpace(tag)) return null;

        var marker = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs", "terminal-buddy", ".miao-installed");
        string? localTag = null;
        if (File.Exists(marker))
        {
            var lines = File.ReadAllLines(marker);
            if (lines.Length >= 2) localTag = lines[1].Trim();
        }

        if (!string.IsNullOrWhiteSpace(localTag))
        {
            return !string.Equals(NormalizeTag(localTag), NormalizeTag(tag), StringComparison.OrdinalIgnoreCase)
                ? NormalizeTag(tag!)
                : null;
        }

        var exe = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs", "terminal-buddy", asset);
        if (!File.Exists(exe)) return null;

        try
        {
            var fv = FileVersionInfo.GetVersionInfo(exe).FileVersion;
            if (string.IsNullOrWhiteSpace(fv)) return null;
            var newer = !NormalizeTag(tag!).Contains(NormalizeTag(fv), StringComparison.OrdinalIgnoreCase)
                        && !NormalizeTag(fv).Contains(NormalizeTag(tag!), StringComparison.OrdinalIgnoreCase);
            return newer ? NormalizeTag(tag!) : null;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>GitHub Release：有更新时返回远程 tag。</summary>
    private static string? ProbeGithubRelease(SoftwareInstallManifest install, string? localVersion)
    {
        var owner = install.GithubOwner;
        var repo = install.GithubRepo;
        if (string.IsNullOrWhiteSpace(owner) || string.IsNullOrWhiteSpace(repo))
            return null;
        if (string.IsNullOrWhiteSpace(localVersion))
            return null;

        var api = $"https://api.github.com/repos/{owner}/{repo}/releases/latest";
        using var req = new HttpRequestMessage(HttpMethod.Get, api);
        req.Headers.TryAddWithoutValidation("User-Agent", "miao-toolkit");
        req.Headers.TryAddWithoutValidation("Accept", "application/vnd.github+json");
        using var resp = Http.Send(req);
        if (!resp.IsSuccessStatusCode) return null;
        using var doc = JsonDocument.Parse(resp.Content.ReadAsStream());
        var tag = doc.RootElement.TryGetProperty("tag_name", out var t) ? t.GetString() : null;
        if (string.IsNullOrWhiteSpace(tag)) return null;

        return !string.Equals(NormalizeTag(localVersion!), NormalizeTag(tag!), StringComparison.OrdinalIgnoreCase)
            ? NormalizeTag(tag!)
            : null;
    }

    /// <summary>npm：有更新时返回 registry 版本。</summary>
    private static string? ProbeNpm(SoftwareInstallManifest install, string? localVersion)
    {
        if (string.IsNullOrWhiteSpace(install.NpmPackage) || string.IsNullOrWhiteSpace(localVersion))
            return null;

        var pkg = install.NpmPackage!.Replace("'", "''");
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-Command");
        psi.ArgumentList.Add(
            "$env:Path=[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User'); if (-not (Get-Command npm -EA SilentlyContinue)) { exit 2 }; npm view '" +
            pkg +
            "' version");

        using var p = Process.Start(psi);
        if (p is null) return null;
        var output = (p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd()).Trim();
        if (!p.WaitForExit(25000))
        {
            try { p.Kill(entireProcessTree: true); } catch { /* ignore */ }
            return null;
        }

        if (p.ExitCode != 0 || string.IsNullOrWhiteSpace(output)) return null;
        var remote = output.Split('\n', '\r')[0].Trim().TrimStart('v', 'V');
        var local = localVersion.Trim().TrimStart('v', 'V');
        return !string.Equals(remote, local, StringComparison.OrdinalIgnoreCase) ? remote : null;
    }

    /// <summary>Hermes：有更新时返回空字符串（CLI 未给出目标版本号）。</summary>
    private static string? ProbeHermes()
    {
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-Command");
        psi.ArgumentList.Add(
            "$env:Path=[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User'); if (-not (Get-Command hermes -EA SilentlyContinue)) { exit 2 }; hermes update --check 2>&1 | Out-String");

        using var p = Process.Start(psi);
        if (p is null) return null;
        var output = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
        if (!p.WaitForExit(60000))
        {
            try { p.Kill(entireProcessTree: true); } catch { /* ignore */ }
            return null;
        }

        if (p.ExitCode != 0) return null;
        return Regex.IsMatch(output, "update available", RegexOptions.IgnoreCase) ? "" : null;
    }

    private static string NormalizeTag(string s) =>
        s.Trim().TrimStart('v', 'V');
}
