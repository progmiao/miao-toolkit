using System.Text.Json.Serialization;

namespace Miao.Common.Sites;

/// <summary>发给 UI 的网站分类。</summary>
public sealed record SiteCategoryDto(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("sort")] int Sort,
    [property: JsonPropertyName("source")] string Source,
    [property: JsonPropertyName("editable")] bool Editable);

/// <summary>发给 UI 的网站项。</summary>
public sealed record SiteDto(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("categoryId")] string CategoryId,
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("url")] string Url,
    [property: JsonPropertyName("sort")] int Sort,
    [property: JsonPropertyName("source")] string Source,
    [property: JsonPropertyName("note")] string? Note,
    [property: JsonPropertyName("editable")] bool Editable);

/// <summary>导入导出包（系统+用户全量导出；导入仅写入用户项）。</summary>
public sealed class SitesExportFile
{
    [JsonPropertyName("version")]
    public int Version { get; set; } = 1;

    [JsonPropertyName("categories")]
    public List<SitesExportCategory> Categories { get; set; } = new();

    [JsonPropertyName("sites")]
    public List<SitesExportSite> Sites { get; set; } = new();
}

/// <summary>导出用分类。</summary>
public sealed class SitesExportCategory
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("sort")]
    public int Sort { get; set; }

    [JsonPropertyName("source")]
    public string Source { get; set; } = "user";
}

/// <summary>导出用网站。</summary>
public sealed class SitesExportSite
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("categoryId")]
    public string CategoryId { get; set; } = "";

    [JsonPropertyName("title")]
    public string Title { get; set; } = "";

    [JsonPropertyName("url")]
    public string Url { get; set; } = "";

    [JsonPropertyName("sort")]
    public int Sort { get; set; }

    [JsonPropertyName("source")]
    public string Source { get; set; } = "user";

    [JsonPropertyName("note")]
    public string? Note { get; set; }
}
