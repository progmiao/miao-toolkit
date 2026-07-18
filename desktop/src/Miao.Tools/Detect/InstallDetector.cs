using System.Diagnostics;
using System.Text.RegularExpressions;
using Miao.Common.Plugins;
using Miao.Data;
using Microsoft.Win32;

namespace Miao.Tools.Detect;

/// <summary>
/// 根据 plugin.json 的 detect 规则探测本机是否已安装。
/// </summary>
public static class InstallDetector
{
    /// <summary>
    /// 探测并写入 tool_state。
    /// </summary>
    /// <param name="db">数据库。</param>
    /// <param name="toolId">工具 id。</param>
    /// <param name="detect">探测规则；null 则标为 unknown。</param>
    public static void ProbeAndStore(AppDatabase db, string toolId, PluginDetectManifest? detect)
    {
        if (detect is null)
        {
            db.UpsertToolState(toolId, "unknown", null, "未配置 detect");
            return;
        }

        try
        {
            if (!string.IsNullOrWhiteSpace(detect.Command))
            {
                var (ok, version) = ProbeCommand(detect.Command!, detect.CommandArgs ?? "");
                if (ok)
                {
                    db.UpsertToolState(toolId, "installed", version, null);
                    return;
                }
            }

            foreach (var raw in detect.ExePaths)
            {
                var path = Environment.ExpandEnvironmentVariables(raw);
                if (File.Exists(path))
                {
                    string? ver = null;
                    try
                    {
                        var info = FileVersionInfo.GetVersionInfo(path);
                        ver = info.ProductVersion ?? info.FileVersion;
                    }
                    catch { /* ignore */ }

                    db.UpsertToolState(toolId, "installed", ver, path);
                    return;
                }
            }

            if (detect.RegistryUninstallNames.Count > 0 &&
                TryFindUninstall(detect.RegistryUninstallNames, out var displayVersion))
            {
                db.UpsertToolState(toolId, "installed", displayVersion, null);
                return;
            }

            db.UpsertToolState(toolId, "missing", null, null);
        }
        catch (Exception ex)
        {
            db.UpsertToolState(toolId, "unknown", null, ex.Message);
        }
    }

    private static (bool Ok, string? Version) ProbeCommand(string fileName, string args)
    {
        try
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
            var cmd = string.IsNullOrWhiteSpace(args)
                ? $"$env:Path=[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User'); & '{fileName.Replace("'", "''")}'"
                : $"$env:Path=[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User'); & '{fileName.Replace("'", "''")}' {args}";
            psi.ArgumentList.Add(cmd);

            using var p = Process.Start(psi);
            if (p is null) return (false, null);
            var output = p.StandardOutput.ReadToEnd().Trim();
            if (!p.WaitForExit(8000))
            {
                try { p.Kill(entireProcessTree: true); } catch { /* ignore */ }
                return (false, null);
            }

            if (p.ExitCode != 0 || string.IsNullOrWhiteSpace(output))
                return (false, null);

            var ver = Regex.Match(output, @"\d+(\.\d+)+").Value;
            if (string.IsNullOrEmpty(ver))
                ver = output.TrimStart('v', 'V').Split('\n', '\r')[0].Trim();
            return (true, ver);
        }
        catch
        {
            return (false, null);
        }
    }

    private static bool TryFindUninstall(IReadOnlyList<string> nameParts, out string? version)
    {
        version = null;
        foreach (var hive in new[] { Registry.LocalMachine, Registry.CurrentUser })
        {
            foreach (var sub in new[]
                     {
                         @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                         @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
                     })
            {
                using var key = hive.OpenSubKey(sub);
                if (key is null) continue;
                foreach (var name in key.GetSubKeyNames())
                {
                    using var item = key.OpenSubKey(name);
                    var display = item?.GetValue("DisplayName") as string;
                    if (string.IsNullOrWhiteSpace(display)) continue;
                    if (!nameParts.Any(p => display.Contains(p, StringComparison.OrdinalIgnoreCase)))
                        continue;
                    version = item?.GetValue("DisplayVersion") as string;
                    return true;
                }
            }
        }

        return false;
    }
}
