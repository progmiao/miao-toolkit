using System.Text.Json;
using System.Text.Json.Serialization;

namespace Miao.Data;

/// <summary>
/// 从 seeds/ 灌库：软件与 i18n 全量覆盖；网站仅替换 system，保留 user。
/// </summary>
public static class SeedLoader
{
    /// <summary>当前打包种子版本（与 seeds 内容同步递增）。</summary>
    public const int PackagedSeedVersion = 13;

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
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // 优先：按侧栏分区 seeds/{daily,dev}/<toolId>/software.json
        foreach (var section in new[] { "daily", "dev" })
        {
            var sectionRoot = Path.Combine(root, section);
            if (!Directory.Exists(sectionRoot)) continue;
            foreach (var path in Directory.EnumerateFiles(sectionRoot, "software.json", SearchOption.AllDirectories)
                         .OrderBy(p => p, StringComparer.OrdinalIgnoreCase))
            {
                var fallbackGroup = section;
                CollectSoftwareFile(path, fallbackGroup, rows, seen);
            }
        }

        // 兼容：旧 seeds/tools/*/software.json
        var legacyTools = Path.Combine(root, "tools");
        if (Directory.Exists(legacyTools))
        {
            foreach (var path in Directory.EnumerateFiles(legacyTools, "software.json", SearchOption.AllDirectories)
                         .OrderBy(p => p, StringComparer.OrdinalIgnoreCase))
            {
                CollectSoftwareFile(path, fallbackGroup: "dev", rows, seen);
            }
        }

        // 兼容：旧版 seeds/software/{daily,dev}.json
        foreach (var file in new[] { "daily.json", "dev.json" })
        {
            var path = Path.Combine(root, "software", file);
            if (!File.Exists(path)) continue;
            CollectSoftwareFile(path, fallbackGroup: Path.GetFileNameWithoutExtension(file), rows, seen);
        }

        db.ReplaceAllSoftware(rows);
    }

    /// <summary>
    /// 从单个 software.json 收集工具行；已存在的 id 跳过（工具包优先）。
    /// </summary>
    private static void CollectSoftwareFile(
        string path,
        string fallbackGroup,
        List<SoftwareRow> rows,
        HashSet<string> seen)
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        if (!doc.RootElement.TryGetProperty("tools", out var tools) ||
            tools.ValueKind != JsonValueKind.Array)
        {
            return;
        }

        foreach (var el in tools.EnumerateArray())
        {
            if (el.ValueKind != JsonValueKind.Object) continue;
            if (!el.TryGetProperty("id", out var idEl)) continue;
            var id = idEl.GetString()?.Trim();
            if (string.IsNullOrWhiteSpace(id)) continue;
            if (!seen.Add(id!)) continue;

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

    private static void ApplyI18n(AppDatabase db, string root)
    {
        var entries = new List<(string, string, string)>();
        foreach (var locale in new[] { "zh", "en" })
        {
            var path = FirstExisting(
                Path.Combine(root, "shell", "i18n", $"{locale}.json"),
                Path.Combine(root, "i18n", $"{locale}.json"));
            if (path is null) continue;
            var dict = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(path), JsonOptions);
            if (dict is null) continue;
            foreach (var (k, v) in dict)
                entries.Add((locale, k, v));
        }

        db.ReplaceAllI18n(entries);
    }

    private static void ApplySites(AppDatabase db, string root)
    {
        var path = FirstExisting(
            Path.Combine(root, "sites", "seed.json"),
            Path.Combine(root, "tools", "sites", "seed.json"));
        if (path is null) return;

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

    /// <summary>返回第一个存在的路径；都没有则 null。</summary>
    private static string? FirstExisting(params string[] candidates)
    {
        foreach (var c in candidates)
        {
            if (File.Exists(c)) return c;
        }

        return null;
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
