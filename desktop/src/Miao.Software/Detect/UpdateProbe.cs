using System.Diagnostics;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using Miao.Common.Software;
using Miao.Data;

namespace Miao.Software.Detect;

/// <summary>
/// 按软件声明的 update.strategy 探测是否有可用更新，并写入 tool_state.detail（update:…）。
/// node / pnpm / yarn 等未声明策略的工具永不标记更新。
/// </summary>
public static class UpdateProbe
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };

    /// <summary>
    /// 在已安装探测之后调用：有更新则 detail 以 <c>update:</c> 开头；否则清除旧 update: 前缀。
    /// </summary>
    /// <param name="db">数据库。</param>
    /// <param name="toolId">软件 id。</param>
    /// <param name="manifest">软件定义。</param>
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

        // Volta 托管的多版本工具：目录层不提供「本体更新」
        if (toolId is "node" or "pnpm" or "yarn")
        {
            ClearUpdateMark(db, toolId, state);
            return;
        }

        try
        {
            var available = strategy switch
            {
                "winget" => ProbeWinget(manifest!.Install!),
                "gitee-release" => ProbeGiteeRelease(manifest!.Install!),
                "hermes" => ProbeHermes(),
                _ => false,
            };

            if (available)
            {
                var detail = state.Detail is { Length: > 0 } d && !d.StartsWith("update:", StringComparison.OrdinalIgnoreCase)
                    ? $"update:{strategy}|{d}"
                    : $"update:{strategy}";
                db.UpsertToolState(toolId, "installed", state.Version, detail);
            }
            else
            {
                ClearUpdateMark(db, toolId, state);
            }
        }
        catch
        {
            // 网络/超时：保留原状态，勿误清「有更新」也不误报
        }
    }

    private static void ClearUpdateMark(AppDatabase db, string toolId, ToolStateRow? state)
    {
        if (state is null) return;
        if (state.Detail is null || !state.Detail.StartsWith("update:", StringComparison.OrdinalIgnoreCase))
            return;

        // 去掉 update: 前缀，保留其后非策略说明（| 后）
        var rest = state.Detail;
        var idx = rest.IndexOf('|');
        var cleaned = idx >= 0 ? rest[(idx + 1)..] : null;
        if (string.IsNullOrWhiteSpace(cleaned))
            cleaned = null;
        db.UpsertToolState(toolId, state.Status, state.Version, cleaned);
    }

    /// <summary>WinGet：list 输出 Available 列有版本则视为可更新。</summary>
    private static bool ProbeWinget(SoftwareInstallManifest install)
    {
        if (string.IsNullOrWhiteSpace(install.PackageId)) return false;

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
        if (p is null) return false;
        var output = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
        if (!p.WaitForExit(25000))
        {
            try { p.Kill(entireProcessTree: true); } catch { /* ignore */ }
            return false;
        }

        // 有 Available 列且该行含包 id 时，取 Available 版本号
        foreach (var line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (!line.Contains(install.PackageId, StringComparison.OrdinalIgnoreCase))
                continue;
            // 典型：Name Id Version Available Source —— Available 为倒数第二或中间版本号
            var versions = Regex.Matches(line, @"\b\d+(?:\.\d+)+\b")
                .Select(m => m.Value)
                .ToList();
            // 仅 Version 一列时不算有更新；出现两个及以上版本号通常为 Version + Available
            if (versions.Count >= 2)
                return true;
        }

        return false;
    }

    /// <summary>Gitee Release：远程 tag 与本地标记/文件版本不一致则有更新。</summary>
    private static bool ProbeGiteeRelease(SoftwareInstallManifest install)
    {
        var owner = install.GiteeOwner ?? "updateme";
        var repo = install.GiteeRepo ?? "terminal-buddy";
        var asset = install.AssetName ?? "terminal-buddy.exe";
        var api = $"https://gitee.com/api/v5/repos/{owner}/{repo}/releases/latest";

        using var resp = Http.GetAsync(api).GetAwaiter().GetResult();
        if (!resp.IsSuccessStatusCode) return false;
        using var doc = JsonDocument.Parse(resp.Content.ReadAsStream());
        var tag = doc.RootElement.TryGetProperty("tag_name", out var t) ? t.GetString() : null;
        if (string.IsNullOrWhiteSpace(tag)) return false;

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
            return !string.Equals(NormalizeTag(localTag), NormalizeTag(tag), StringComparison.OrdinalIgnoreCase);

        // 无标记：有 exe 且远程 tag 存在时，用 FileVersion 粗比（无法比则保守认为无更新提示需装过一次）
        var exe = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs", "terminal-buddy", asset);
        if (!File.Exists(exe)) return false;

        try
        {
            var fv = FileVersionInfo.GetVersionInfo(exe).FileVersion;
            if (string.IsNullOrWhiteSpace(fv)) return false;
            return !NormalizeTag(tag!).Contains(NormalizeTag(fv), StringComparison.OrdinalIgnoreCase)
                   && !NormalizeTag(fv).Contains(NormalizeTag(tag!), StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    /// <summary>Hermes：<c>hermes update --check</c> 输出含 update available。</summary>
    private static bool ProbeHermes()
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
        if (p is null) return false;
        var output = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
        if (!p.WaitForExit(60000))
        {
            try { p.Kill(entireProcessTree: true); } catch { /* ignore */ }
            return false;
        }

        if (p.ExitCode != 0) return false;
        return Regex.IsMatch(output, "update available", RegexOptions.IgnoreCase);
    }

    private static string NormalizeTag(string s) =>
        s.Trim().TrimStart('v', 'V');
}
