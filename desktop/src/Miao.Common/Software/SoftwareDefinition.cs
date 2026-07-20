using System.Text.Json.Serialization;

namespace Miao.Common.Software;

/// <summary>software definition 根对象。</summary>
public sealed class SoftwareDefinition
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
    public SoftwareUiManifest? Ui { get; set; }

    /// <summary>安装/检测规格（通用 Handler 读取）。</summary>
    [JsonPropertyName("install")]
    public SoftwareInstallManifest? Install { get; set; }

    [JsonPropertyName("actions")]
    public List<SoftwareActionManifest> Actions { get; set; } = new();
}

/// <summary>软件 UI 声明。</summary>
public sealed class SoftwareUiManifest
{
    /// <summary><c>generic</c> 壳通用页；<c>panel</c> 专用面板。</summary>
    [JsonPropertyName("mode")]
    public string Mode { get; set; } = "generic";

    /// <summary>
    /// panel 入口路由段：前端跳转 `/dev/{entry}`（如 node / pnpm / yarn / claude）。
    /// 与 `ui/src/dev/<entry>/index.vue` 及 router 注册保持一致。
    /// </summary>
    [JsonPropertyName("entry")]
    public string? Entry { get; set; }
}

/// <summary>安装与探测配置。</summary>
public sealed class SoftwareInstallManifest
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
    public SoftwareDetectManifest? Detect { get; set; }

    /// <summary>
    /// 更新检测；缺省或 strategy=none 表示不提供「有更新」能力（如 node/pnpm/yarn）。
    /// </summary>
    [JsonPropertyName("update")]
    public SoftwareUpdateManifest? Update { get; set; }

    /// <summary>TerminalBuddy 等自定义字段。</summary>
    [JsonPropertyName("giteeOwner")]
    public string? GiteeOwner { get; set; }

    [JsonPropertyName("giteeRepo")]
    public string? GiteeRepo { get; set; }

    [JsonPropertyName("assetName")]
    public string? AssetName { get; set; }
}

/// <summary>已安装探测规则。</summary>
public sealed class SoftwareDetectManifest
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

/// <summary>更新检测配置（各工具策略不同）。</summary>
public sealed class SoftwareUpdateManifest
{
    /// <summary>
    /// 策略：<c>winget</c> / <c>gitee-release</c> / <c>hermes</c> / <c>none</c>。
    /// </summary>
    [JsonPropertyName("strategy")]
    public string Strategy { get; set; } = "none";
}

/// <summary>软件声明的一个可执行动作。</summary>
public sealed class SoftwareActionManifest
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
public sealed class SoftwareGroupsFile
{
    [JsonPropertyName("groups")]
    public List<SoftwareGroupDefinition> Groups { get; set; } = new();
}

/// <summary>一级分类登记项。</summary>
public sealed class SoftwareGroupDefinition
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
/// <param name="Id">软件 id。</param>
/// <param name="Name">显示名。</param>
/// <param name="Description">说明（列表可隐藏）。</param>
/// <param name="Group">分组 daily / dev。</param>
/// <param name="Status">installed / missing / unknown。</param>
/// <param name="Version">探测到的版本；可空。</param>
/// <param name="Actions">可用动作 id。</param>
/// <param name="UiMode">generic | panel。</param>
/// <param name="UiEntry">panel 路由段：与前端 `/dev/{entry}` 对应；generic 时可空。</param>
/// <param name="Tags">分类标签。</param>
/// <param name="UpdateAvailable">已安装且检测到可更新时为 true（驱动「更新」按钮）。</param>
public sealed record CatalogItemDto(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("description")] string Description,
    [property: JsonPropertyName("group")] string Group,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("version")] string? Version,
    [property: JsonPropertyName("actions")] string[] Actions,
    [property: JsonPropertyName("uiMode")] string UiMode,
    [property: JsonPropertyName("uiEntry")] string? UiEntry,
    [property: JsonPropertyName("tags")] string[] Tags,
    [property: JsonPropertyName("updateAvailable")] bool UpdateAvailable);

/// <summary>发给 Vue 的分组 DTO。</summary>
public sealed record CatalogGroupDto(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("sort")] int Sort);

