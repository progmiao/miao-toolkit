using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using Miao.Data;

namespace Miao.Software.Claude;

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

    /// <summary>Miao 侧密钥文件：%LocalAppData%\Miao\claude-code.json。</summary>
    public string SecretsPath => Path.Combine(AppPaths.DataRoot, "claude-code.json");

    /// <summary>用户 Claude 设置：~/.claude/settings.json。</summary>
    public string SettingsPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude", "settings.json");

    /// <summary>当前 CLI 是否可用。</summary>
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

    /// <summary>应用初始化默认：DISABLE_LOGIN_COMMAND=1，并注册预设 marketplace。</summary>
    public string Init()
    {
        MergeEnv(new Dictionary<string, string?> { ["DISABLE_LOGIN_COMMAND"] = "1" }, Array.Empty<string>());
        var presets = LoadPresets();
        var logs = new List<string> { "已写入 DISABLE_LOGIN_COMMAND=1" };
        foreach (var mp in presets.Marketplaces)
        {
            var source = mp.Source;
            if (string.IsNullOrWhiteSpace(source)) continue;
            var (ok, detail) = RunClaude($"plugin marketplace add {EscapeArg(source)}");
            logs.Add(ok ? $"marketplace + {source}" : $"marketplace 跳过/失败 {source}: {detail}");
        }

        return string.Join("\n", logs);
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

    /// <summary>预设 + 精选插件列表（供 UI 勾选）。</summary>
    public IReadOnlyList<ClaudePluginDto> ListFeaturedPlugins()
    {
        var presets = LoadPresets();
        return presets.FeaturedPlugins
            .Select(p => new ClaudePluginDto(p.Id, p.Id, true))
            .ToList();
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

    private ClaudePresetsFile LoadPresets()
    {
        var root = AppPaths.ResolveSeedsRoot();
        if (root is null) return new ClaudePresetsFile();
        var path = Path.Combine(root, "claude", "presets.json");
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
            var psi = new ProcessStartInfo
            {
                FileName = "claude",
                Arguments = args,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var p = Process.Start(psi);
            if (p is null) return (false, "无法启动 claude");
            var stdout = p.StandardOutput.ReadToEnd();
            var stderr = p.StandardError.ReadToEnd();
            p.WaitForExit(120_000);
            var detail = (stdout + "\n" + stderr).Trim();
            return (p.ExitCode == 0, detail.Length > 0 ? detail : $"exit={p.ExitCode}");
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
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
    [property: JsonPropertyName("featured")] bool Featured);

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
