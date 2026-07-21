using System.Text.Json;
using System.Text.Json.Serialization;
using Miao.Data;

namespace Miao.Utilities;

/// <summary>
/// 工具集：从 seeds/utilities/registry.json 读注册表，小工具可在 UI 侧即时执行（如 GUID）。
/// </summary>
public sealed class UtilitiesService
{
    private readonly AppDatabase _db;

    /// <summary>创建服务。</summary>
    public UtilitiesService(AppDatabase db) => _db = db;

    /// <summary>
    /// 返回工具集标题、说明与已注册小工具列表。
    /// </summary>
    /// <param name="locale">语言代码（zh / en）。</param>
    public UtilitiesPageDto GetPage(string locale)
    {
        var items = LoadRegistry()
            .Select(r => new UtilityItemDto(
                r.Id,
                _db.T(locale, r.NameKey, r.Id),
                _db.T(locale, r.DescriptionKey, "")))
            .ToArray();

        return new UtilitiesPageDto(
            _db.T(locale, "utilities.title", "工具集"),
            _db.T(locale, "utilities.subtitle", "应用内小工具：GUID 生成等，无需安装额外软件。"),
            items);
    }

    /// <summary>
    /// 生成若干 GUID 字符串。
    /// </summary>
    /// <param name="count">数量，钳制到 1–100。</param>
    /// <param name="uppercase">是否大写十六进制。</param>
    /// <param name="braces">是否加花括号。</param>
    /// <returns>生成结果 DTO。</returns>
    public GuidBatchDto GenerateGuids(int count, bool uppercase, bool braces)
    {
        count = Math.Clamp(count, 1, 100);
        var list = new List<string>(count);
        for (var i = 0; i < count; i++)
        {
            var g = Guid.NewGuid().ToString(uppercase ? "D" : "D");
            if (uppercase) g = g.ToUpperInvariant();
            else g = g.ToLowerInvariant();
            if (braces) g = "{" + g + "}";
            list.Add(g);
        }

        return new GuidBatchDto(list.ToArray());
    }

    private static List<UtilityRegistryItem> LoadRegistry()
    {
        var root = AppPaths.ResolveSeedsRoot();
        if (root is null) return [];

        var path = Path.Combine(root, "utilities", "registry.json");
        if (!File.Exists(path)) return [];

        try
        {
            var file = JsonSerializer.Deserialize<UtilityRegistryFile>(File.ReadAllText(path));
            return file?.Items ?? [];
        }
        catch
        {
            return [];
        }
    }

    private sealed class UtilityRegistryFile
    {
        [JsonPropertyName("items")]
        public List<UtilityRegistryItem> Items { get; set; } = [];
    }

    private sealed class UtilityRegistryItem
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = "";

        [JsonPropertyName("nameKey")]
        public string NameKey { get; set; } = "";

        [JsonPropertyName("descriptionKey")]
        public string DescriptionKey { get; set; } = "";
    }
}

/// <summary>工具集页 DTO。</summary>
public sealed record UtilitiesPageDto(
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("body")] string Body,
    [property: JsonPropertyName("items")] UtilityItemDto[] Items);

/// <summary>单个小工具注册项。</summary>
public sealed record UtilityItemDto(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("description")] string Description);

/// <summary>GUID 批量生成结果。</summary>
public sealed record GuidBatchDto(
    [property: JsonPropertyName("values")] string[] Values);
