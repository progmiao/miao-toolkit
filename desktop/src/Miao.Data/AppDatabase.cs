using Microsoft.Data.Sqlite;

namespace Miao.Data;

/// <summary>
/// 本地 SQLite：设置、软件清单、i18n、网站、工具安装状态。
/// </summary>
public sealed class AppDatabase : IDisposable
{
    private readonly SqliteConnection _conn;

    /// <summary>打开（或创建）数据库并执行迁移。</summary>
    /// <param name="dbPath">数据库文件绝对路径。</param>
    public AppDatabase(string dbPath)
    {
        var dir = Path.GetDirectoryName(dbPath);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);

        _conn = new SqliteConnection($"Data Source={dbPath}");
        _conn.Open();
        Migrate();
    }

    /// <summary>建表与轻量迁移（schema 3：软件/i18n/网站）。</summary>
    private void Migrate()
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            """
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY NOT NULL,
              value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS software (
              id TEXT PRIMARY KEY NOT NULL,
              group_name TEXT NOT NULL,
              sort_order INTEGER NOT NULL DEFAULT 0,
              enabled INTEGER NOT NULL DEFAULT 1,
              manifest_json TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS i18n_entries (
              locale TEXT NOT NULL,
              key TEXT NOT NULL,
              value TEXT NOT NULL,
              PRIMARY KEY (locale, key)
            );

            CREATE TABLE IF NOT EXISTS site_categories (
              id TEXT PRIMARY KEY NOT NULL,
              name TEXT NOT NULL,
              sort_order INTEGER NOT NULL DEFAULT 0,
              source TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS sites (
              id TEXT PRIMARY KEY NOT NULL,
              category_id TEXT NOT NULL,
              title TEXT NOT NULL,
              url TEXT NOT NULL,
              sort_order INTEGER NOT NULL DEFAULT 0,
              source TEXT NOT NULL,
              note TEXT
            );

            CREATE TABLE IF NOT EXISTS tool_state (
              tool_id TEXT PRIMARY KEY NOT NULL,
              status TEXT NOT NULL,
              version TEXT,
              detail TEXT,
              checked_at TEXT NOT NULL
            );
            """;
        cmd.ExecuteNonQuery();

        // 去掉旧 plugins 表（一步到位，无双轨）
        using (var drop = _conn.CreateCommand())
        {
            drop.CommandText = "DROP TABLE IF EXISTS plugins;";
            drop.ExecuteNonQuery();
        }

        SetSettingIfMissing("locale", "zh");
        var prevSchema = GetSetting("schema_version", "0");
        if (prevSchema != "3")
        {
            // 旧库升级到 seeds 模型时强制重灌
            SetSetting("seed_version", "0");
        }

        SetSetting("schema_version", "3");
    }

    /// <summary>读取设置；不存在返回 <paramref name="fallback"/>。</summary>
    public string GetSetting(string key, string fallback = "")
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText = "SELECT value FROM settings WHERE key = $k LIMIT 1";
        cmd.Parameters.AddWithValue("$k", key);
        var v = cmd.ExecuteScalar() as string;
        return string.IsNullOrEmpty(v) ? fallback : v;
    }

    /// <summary>写入设置（存在则覆盖）。</summary>
    public void SetSetting(string key, string value)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            """
            INSERT INTO settings(key, value) VALUES($k, $v)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """;
        cmd.Parameters.AddWithValue("$k", key);
        cmd.Parameters.AddWithValue("$v", value);
        cmd.ExecuteNonQuery();
    }

    private void SetSettingIfMissing(string key, string value)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText = "INSERT OR IGNORE INTO settings(key, value) VALUES($k, $v)";
        cmd.Parameters.AddWithValue("$k", key);
        cmd.Parameters.AddWithValue("$v", value);
        cmd.ExecuteNonQuery();
    }

    /// <summary>清空并重写全部软件行（种子全量覆盖）。</summary>
    public void ReplaceAllSoftware(IEnumerable<SoftwareRow> rows)
    {
        using var tx = _conn.BeginTransaction();
        using (var del = _conn.CreateCommand())
        {
            del.Transaction = tx;
            del.CommandText = "DELETE FROM software;";
            del.ExecuteNonQuery();
        }

        foreach (var row in rows)
        {
            using var cmd = _conn.CreateCommand();
            cmd.Transaction = tx;
            cmd.CommandText =
                """
                INSERT INTO software(id, group_name, sort_order, enabled, manifest_json, updated_at)
                VALUES($id, $g, $s, 1, $m, $t)
                """;
            cmd.Parameters.AddWithValue("$id", row.Id);
            cmd.Parameters.AddWithValue("$g", row.Group);
            cmd.Parameters.AddWithValue("$s", row.SortOrder);
            cmd.Parameters.AddWithValue("$m", row.ManifestJson);
            cmd.Parameters.AddWithValue("$t", DateTimeOffset.UtcNow.ToString("O"));
            cmd.ExecuteNonQuery();
        }

        tx.Commit();
    }

    /// <summary>读取全部已启用软件；可按 group 过滤。</summary>
    public IReadOnlyList<SoftwareRow> ListSoftware(string? group = null)
    {
        using var cmd = _conn.CreateCommand();
        if (string.IsNullOrWhiteSpace(group))
        {
            cmd.CommandText =
                """
                SELECT id, group_name, sort_order, manifest_json
                FROM software WHERE enabled = 1
                ORDER BY sort_order ASC, id ASC
                """;
        }
        else
        {
            cmd.CommandText =
                """
                SELECT id, group_name, sort_order, manifest_json
                FROM software WHERE enabled = 1 AND group_name = $g
                ORDER BY sort_order ASC, id ASC
                """;
            cmd.Parameters.AddWithValue("$g", group);
        }

        var list = new List<SoftwareRow>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            list.Add(new SoftwareRow(
                reader.GetString(0),
                reader.GetString(1),
                reader.GetInt32(2),
                reader.GetString(3)));
        }

        return list;
    }

    /// <summary>按 id 取软件；没有则 null。</summary>
    public SoftwareRow? GetSoftware(string toolId)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            """
            SELECT id, group_name, sort_order, manifest_json
            FROM software WHERE id = $id LIMIT 1
            """;
        cmd.Parameters.AddWithValue("$id", toolId);
        using var reader = cmd.ExecuteReader();
        if (!reader.Read()) return null;
        return new SoftwareRow(
            reader.GetString(0),
            reader.GetString(1),
            reader.GetInt32(2),
            reader.GetString(3));
    }

    /// <summary>清空并重写全部 i18n（种子全量覆盖）。</summary>
    public void ReplaceAllI18n(IEnumerable<(string Locale, string Key, string Value)> entries)
    {
        using var tx = _conn.BeginTransaction();
        using (var del = _conn.CreateCommand())
        {
            del.Transaction = tx;
            del.CommandText = "DELETE FROM i18n_entries;";
            del.ExecuteNonQuery();
        }

        foreach (var (locale, key, value) in entries)
        {
            using var cmd = _conn.CreateCommand();
            cmd.Transaction = tx;
            cmd.CommandText =
                """
                INSERT INTO i18n_entries(locale, key, value) VALUES($l, $k, $v)
                """;
            cmd.Parameters.AddWithValue("$l", locale);
            cmd.Parameters.AddWithValue("$k", key);
            cmd.Parameters.AddWithValue("$v", value);
            cmd.ExecuteNonQuery();
        }

        tx.Commit();
    }

    /// <summary>读取某语言全部文案。</summary>
    public IReadOnlyDictionary<string, string> GetI18nMap(string locale)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText = "SELECT key, value FROM i18n_entries WHERE locale = $l";
        cmd.Parameters.AddWithValue("$l", locale);
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
            map[reader.GetString(0)] = reader.GetString(1);
        return map;
    }

    /// <summary>解析文案；缺省回退 zh，再回退 fallback。</summary>
    public string T(string locale, string key, string fallback = "")
    {
        if (string.IsNullOrWhiteSpace(key)) return fallback;
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            """
            SELECT value FROM i18n_entries
            WHERE key = $k AND locale IN ($l, 'zh')
            ORDER BY CASE locale WHEN $l THEN 0 ELSE 1 END
            LIMIT 1
            """;
        cmd.Parameters.AddWithValue("$k", key);
        cmd.Parameters.AddWithValue("$l", locale);
        var v = cmd.ExecuteScalar() as string;
        return string.IsNullOrEmpty(v) ? fallback : v;
    }

    /// <summary>删除全部系统网站分类与条目（保留用户数据）。</summary>
    public void DeleteSystemSites()
    {
        using var tx = _conn.BeginTransaction();
        using (var c1 = _conn.CreateCommand())
        {
            c1.Transaction = tx;
            c1.CommandText = "DELETE FROM sites WHERE source = 'system';";
            c1.ExecuteNonQuery();
        }

        using (var c2 = _conn.CreateCommand())
        {
            c2.Transaction = tx;
            c2.CommandText = "DELETE FROM site_categories WHERE source = 'system';";
            c2.ExecuteNonQuery();
        }

        tx.Commit();
    }

    /// <summary>写入网站分类。</summary>
    public void UpsertSiteCategory(string id, string name, int sort, string source)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            """
            INSERT INTO site_categories(id, name, sort_order, source)
            VALUES($id, $n, $s, $src)
            ON CONFLICT(id) DO UPDATE SET
              name = excluded.name,
              sort_order = excluded.sort_order,
              source = excluded.source
            """;
        cmd.Parameters.AddWithValue("$id", id);
        cmd.Parameters.AddWithValue("$n", name);
        cmd.Parameters.AddWithValue("$s", sort);
        cmd.Parameters.AddWithValue("$src", source);
        cmd.ExecuteNonQuery();
    }

    /// <summary>写入网站。</summary>
    public void UpsertSite(string id, string categoryId, string title, string url, int sort, string source, string? note)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            """
            INSERT INTO sites(id, category_id, title, url, sort_order, source, note)
            VALUES($id, $c, $t, $u, $s, $src, $note)
            ON CONFLICT(id) DO UPDATE SET
              category_id = excluded.category_id,
              title = excluded.title,
              url = excluded.url,
              sort_order = excluded.sort_order,
              source = excluded.source,
              note = excluded.note
            """;
        cmd.Parameters.AddWithValue("$id", id);
        cmd.Parameters.AddWithValue("$c", categoryId);
        cmd.Parameters.AddWithValue("$t", title);
        cmd.Parameters.AddWithValue("$u", url);
        cmd.Parameters.AddWithValue("$s", sort);
        cmd.Parameters.AddWithValue("$src", source);
        cmd.Parameters.AddWithValue("$note", (object?)note ?? DBNull.Value);
        cmd.ExecuteNonQuery();
    }

    /// <summary>列出全部分类。</summary>
    public IReadOnlyList<SiteCategoryRow> ListSiteCategories()
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            "SELECT id, name, sort_order, source FROM site_categories ORDER BY sort_order ASC, name ASC";
        var list = new List<SiteCategoryRow>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            list.Add(new SiteCategoryRow(
                reader.GetString(0),
                reader.GetString(1),
                reader.GetInt32(2),
                reader.GetString(3)));
        }

        return list;
    }

    /// <summary>列出全部网站。</summary>
    public IReadOnlyList<SiteRow> ListSites()
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            """
            SELECT id, category_id, title, url, sort_order, source, note
            FROM sites ORDER BY sort_order ASC, title ASC
            """;
        var list = new List<SiteRow>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            list.Add(new SiteRow(
                reader.GetString(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetInt32(4),
                reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetString(6)));
        }

        return list;
    }

    /// <summary>按 id 取网站。</summary>
    public SiteRow? GetSite(string id)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            """
            SELECT id, category_id, title, url, sort_order, source, note
            FROM sites WHERE id = $id LIMIT 1
            """;
        cmd.Parameters.AddWithValue("$id", id);
        using var reader = cmd.ExecuteReader();
        if (!reader.Read()) return null;
        return new SiteRow(
            reader.GetString(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetString(3),
            reader.GetInt32(4),
            reader.GetString(5),
            reader.IsDBNull(6) ? null : reader.GetString(6));
    }

    /// <summary>按 id 取分类。</summary>
    public SiteCategoryRow? GetSiteCategory(string id)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            "SELECT id, name, sort_order, source FROM site_categories WHERE id = $id LIMIT 1";
        cmd.Parameters.AddWithValue("$id", id);
        using var reader = cmd.ExecuteReader();
        if (!reader.Read()) return null;
        return new SiteCategoryRow(
            reader.GetString(0),
            reader.GetString(1),
            reader.GetInt32(2),
            reader.GetString(3));
    }

    /// <summary>删除用户网站；系统项拒绝。</summary>
    public bool DeleteUserSite(string id)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText = "DELETE FROM sites WHERE id = $id AND source = 'user'";
        cmd.Parameters.AddWithValue("$id", id);
        return cmd.ExecuteNonQuery() > 0;
    }

    /// <summary>删除用户分类及其下用户网站；系统项拒绝。</summary>
    public bool DeleteUserSiteCategory(string id)
    {
        var cat = GetSiteCategory(id);
        if (cat is null || cat.Source != "user") return false;

        using var tx = _conn.BeginTransaction();
        using (var d1 = _conn.CreateCommand())
        {
            d1.Transaction = tx;
            d1.CommandText = "DELETE FROM sites WHERE category_id = $id AND source = 'user'";
            d1.Parameters.AddWithValue("$id", id);
            d1.ExecuteNonQuery();
        }

        using (var d2 = _conn.CreateCommand())
        {
            d2.Transaction = tx;
            d2.CommandText = "DELETE FROM site_categories WHERE id = $id AND source = 'user'";
            d2.Parameters.AddWithValue("$id", id);
            d2.ExecuteNonQuery();
        }

        tx.Commit();
        return true;
    }

    /// <summary>更新工具安装状态。</summary>
    public void UpsertToolState(string toolId, string status, string? version, string? detail = null)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            """
            INSERT INTO tool_state(tool_id, status, version, detail, checked_at)
            VALUES($id, $st, $ver, $detail, $t)
            ON CONFLICT(tool_id) DO UPDATE SET
              status = excluded.status,
              version = excluded.version,
              detail = excluded.detail,
              checked_at = excluded.checked_at
            """;
        cmd.Parameters.AddWithValue("$id", toolId);
        cmd.Parameters.AddWithValue("$st", status);
        cmd.Parameters.AddWithValue("$ver", (object?)version ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$detail", (object?)detail ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$t", DateTimeOffset.UtcNow.ToString("O"));
        cmd.ExecuteNonQuery();
    }

    /// <summary>读取某工具状态；无记录返回 null。</summary>
    public ToolStateRow? GetToolState(string toolId)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            "SELECT tool_id, status, version, detail, checked_at FROM tool_state WHERE tool_id = $id LIMIT 1";
        cmd.Parameters.AddWithValue("$id", toolId);
        using var reader = cmd.ExecuteReader();
        if (!reader.Read()) return null;
        return new ToolStateRow(
            reader.GetString(0),
            reader.GetString(1),
            reader.IsDBNull(2) ? null : reader.GetString(2),
            reader.IsDBNull(3) ? null : reader.GetString(3),
            reader.GetString(4));
    }

    /// <inheritdoc />
    public void Dispose() => _conn.Dispose();
}

/// <summary>software 表一行。</summary>
public sealed record SoftwareRow(
    string Id,
    string Group,
    int SortOrder,
    string ManifestJson);

/// <summary>tool_state 表一行。</summary>
public sealed record ToolStateRow(
    string ToolId,
    string Status,
    string? Version,
    string? Detail,
    string CheckedAt);

/// <summary>网站分类一行。</summary>
public sealed record SiteCategoryRow(
    string Id,
    string Name,
    int SortOrder,
    string Source);

/// <summary>网站一行。</summary>
public sealed record SiteRow(
    string Id,
    string CategoryId,
    string Title,
    string Url,
    int SortOrder,
    string Source,
    string? Note);
