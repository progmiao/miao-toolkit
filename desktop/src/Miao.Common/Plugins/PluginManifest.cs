using System.Text.Json.Serialization;

namespace Miao.Common.Plugins;

/// <summary>plugin.json 根对象。</summary>
public sealed class PluginManifest
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    /// <summary>可选；权威归属以父文件夹为准，仅作校验。</summary>
    [JsonPropertyName("group")]
    public string? Group { get; set; }

    [JsonPropertyName("sort")]
    public int Sort { get; set; }

    [JsonPropertyName("nameKey")]
    public string NameKey { get; set; } = "";

    [JsonPropertyName("descriptionKey")]
    public string DescriptionKey { get; set; } = "";

    /// <summary>展示用标签，如 ai / runtime。</summary>
    [JsonPropertyName("tags")]
    public List<string> Tags { get; set; } = new();

    [JsonPropertyName("ui")]
    public PluginUiManifest? Ui { get; set; }

    /// <summary>安装/检测规格（通用 Handler 读取）。</summary>
    [JsonPropertyName("install")]
    public PluginInstallManifest? Install { get; set; }

    [JsonPropertyName("actions")]
    public List<PluginActionManifest> Actions { get; set; } = new();
}

/// <summary>插件 UI 声明。</summary>
public sealed class PluginUiManifest
{
    /// <summary><c>generic</c> 壳通用页；<c>panel</c> 插件专属面板。</summary>
    [JsonPropertyName("mode")]
    public string Mode { get; set; } = "generic";

    /// <summary>panel 入口相对路径（预留）。</summary>
    [JsonPropertyName("entry")]
    public string? Entry { get; set; }
}

/// <summary>安装与探测配置。</summary>
public sealed class PluginInstallManifest
{
    /// <summary>策略：installer-launch / winget / npm / custom。</summary>
    [JsonPropertyName("strategy")]
    public string Strategy { get; set; } = "";

    [JsonPropertyName("packageId")]
    public string? PackageId { get; set; }

    [JsonPropertyName("wingetSource")]
    public string? WingetSource { get; set; }

    [JsonPropertyName("downloadUrl")]
    public string? DownloadUrl { get; set; }

    [JsonPropertyName("installerFileName")]
    public string? InstallerFileName { get; set; }

    [JsonPropertyName("npmPackage")]
    public string? NpmPackage { get; set; }

    [JsonPropertyName("detect")]
    public PluginDetectManifest? Detect { get; set; }

    /// <summary>TerminalBuddy 等自定义字段。</summary>
    [JsonPropertyName("giteeOwner")]
    public string? GiteeOwner { get; set; }

    [JsonPropertyName("giteeRepo")]
    public string? GiteeRepo { get; set; }

    [JsonPropertyName("assetName")]
    public string? AssetName { get; set; }
}

/// <summary>已安装探测规则。</summary>
public sealed class PluginDetectManifest
{
    /// <summary>卸载项 DisplayName 子串匹配。</summary>
    [JsonPropertyName("registryUninstallNames")]
    public List<string> RegistryUninstallNames { get; set; } = new();

    /// <summary>存在即视为已安装的文件路径（支持 %LOCALAPPDATA% 等环境变量）。</summary>
    [JsonPropertyName("exePaths")]
    public List<string> ExePaths { get; set; } = new();

    /// <summary>命令行探测，如 node -v。</summary>
    [JsonPropertyName("command")]
    public string? Command { get; set; }

    [JsonPropertyName("commandArgs")]
    public string? CommandArgs { get; set; }
}

/// <summary>插件声明的一个可执行动作。</summary>
public sealed class PluginActionManifest
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    /// <summary>内置处理器键，如 node.install / generic.winget。</summary>
    [JsonPropertyName("handler")]
    public string Handler { get; set; } = "";

    [JsonPropertyName("nameKey")]
    public string? NameKey { get; set; }
}

/// <summary>_registry.json 根。</summary>
public sealed class PluginRegistryFile
{
    [JsonPropertyName("groups")]
    public List<PluginRegistryGroup> Groups { get; set; } = new();
}

/// <summary>一级分类登记项。</summary>
public sealed class PluginRegistryGroup
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("sort")]
    public int Sort { get; set; }

    [JsonPropertyName("nameKey")]
    public string NameKey { get; set; } = "";

    [JsonPropertyName("enabled")]
    public bool Enabled { get; set; } = true;
}

/// <summary>发给 Vue 的目录项 DTO。</summary>
public sealed record CatalogItemDto(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("description")] string Description,
    [property: JsonPropertyName("group")] string Group,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("version")] string? Version,
    [property: JsonPropertyName("actions")] string[] Actions,
    [property: JsonPropertyName("uiMode")] string UiMode,
    [property: JsonPropertyName("tags")] string[] Tags);

/// <summary>发给 Vue 的分组 DTO。</summary>
public sealed record CatalogGroupDto(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("sort")] int Sort);
