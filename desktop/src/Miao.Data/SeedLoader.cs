using System.Text.Json;
using System.Text.Json.Serialization;

namespace Miao.Data;

/// <summary>
/// 从 seeds/ 灌库：软件与 i18n 全量覆盖；网站仅替换 system，保留 user。
/// </summary>
public static class SeedLoader
{
    /// <summary>当前打包种子版本（与 seeds 内容同步递增）。</summary>
    public const int PackagedSeedVersion = 7;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    /// <summary>
    /// 若种子版本变化则灌库；返回是否执行了灌入。
    /// </summary>
    public static bool ApplyIfNeeded(AppDatabase db)
    {
        var current = db.GetSetting("seed_version", "0");
        if (int.TryParse(current, out var ver) && ver >= PackagedSeedVersion)
            return false;

        var root = AppPaths.ResolveSeedsRoot();
        if (root is null)
            throw new InvalidOperationException("未找到 seeds 目录，无法初始化。");

        ApplySoftware(db, root);
        ApplyI18n(db, root);
        ApplySites(db, root);
        db.SetSetting("seed_version", PackagedSeedVersion.ToString());
        return true;
    }

    private static void ApplySoftware(AppDatabase db, string root)
    {
        var rows = new List<SoftwareRow>();
        foreach (var file in new[] { "daily.json", "dev.json" })
        {
            var path = Path.Combine(root, "software", file);
            if (!File.Exists(path)) continue;

            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            if (!doc.RootElement.TryGetProperty("tools", out var tools) ||
                tools.ValueKind != JsonValueKind.Array)
            {
                continue;
            }

            var fallbackGroup = Path.GetFileNameWithoutExtension(file);
            foreach (var el in tools.EnumerateArray())
            {
                if (el.ValueKind != JsonValueKind.Object) continue;
                if (!el.TryGetProperty("id", out var idEl)) continue;
                var id = idEl.GetString()?.Trim();
                if (string.IsNullOrWhiteSpace(id)) continue;

                var group = fallbackGroup;
                if (el.TryGetProperty("group", out var gEl))
                {
                    var g = gEl.GetString();
                    if (!string.IsNullOrWhiteSpace(g)) group = g!;
                }

                var sort = 0;
                if (el.TryGetProperty("sort", out var sEl) && sEl.TryGetInt32(out var s))
                    sort = s;

                rows.Add(new SoftwareRow(id!, group, sort, el.GetRawText()));
            }
        }

        db.ReplaceAllSoftware(rows);
    }

    private static void ApplyI18n(AppDatabase db, string root)
    {
        var entries = new List<(string, string, string)>();
        foreach (var locale in new[] { "zh", "en" })
        {
            var path = Path.Combine(root, "i18n", $"{locale}.json");
            if (!File.Exists(path)) continue;
            var dict = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(path), JsonOptions);
            if (dict is null) continue;
            foreach (var (k, v) in dict)
                entries.Add((locale, k, v));
        }

        db.ReplaceAllI18n(entries);
    }

    private static void ApplySites(AppDatabase db, string root)
    {
        var path = Path.Combine(root, "sites", "seed.json");
        if (!File.Exists(path)) return;

        var seed = JsonSerializer.Deserialize<SitesSeedFile>(File.ReadAllText(path), JsonOptions);
        if (seed is null) return;

        db.DeleteSystemSites();
        foreach (var c in seed.Categories ?? [])
        {
            if (string.IsNullOrWhiteSpace(c.Id)) continue;
            db.UpsertSiteCategory(c.Id.Trim(), c.Name, c.Sort, "system");
        }

        foreach (var s in seed.Sites ?? [])
        {
            if (string.IsNullOrWhiteSpace(s.Id)) continue;
            db.UpsertSite(s.Id.Trim(), s.CategoryId, s.Title, s.Url, s.Sort, "system", s.Note);
        }
    }

    private sealed class SitesSeedFile
    {
        [JsonPropertyName("categories")]
        public List<SiteCategorySeed>? Categories { get; set; }

        [JsonPropertyName("sites")]
        public List<SiteSeed>? Sites { get; set; }
    }

    private sealed class SiteCategorySeed
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = "";

        [JsonPropertyName("name")]
        public string Name { get; set; } = "";

        [JsonPropertyName("sort")]
        public int Sort { get; set; }
    }

    private sealed class SiteSeed
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

        [JsonPropertyName("note")]
        public string? Note { get; set; }
    }
}
