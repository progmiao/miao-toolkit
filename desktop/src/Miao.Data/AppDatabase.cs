using System.IO;
using Microsoft.Data.Sqlite;

namespace Miao.Data;

/// <summary>
/// 本地 SQLite：设置、插件缓存、工具安装状态。对外通过本类方法操作，业务勿直接拼 SQL。
/// </summary>
public sealed class AppDatabase : IDisposable
{
    private readonly SqliteConnection _conn;

    /// <summary>
    /// 打开（或创建）数据库并执行迁移。
    /// </summary>
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

    /// <summary>建表与轻量迁移。</summary>
    private void Migrate()
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            """
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY NOT NULL,
              value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS plugins (
              id TEXT PRIMARY KEY NOT NULL,
              group_name TEXT NOT NULL,
              sort_order INTEGER NOT NULL DEFAULT 0,
              enabled INTEGER NOT NULL DEFAULT 1,
              manifest_json TEXT NOT NULL,
              dir_path TEXT NOT NULL,
              updated_at TEXT NOT NULL
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

        SetSettingIfMissing("locale", "zh");
        SetSettingIfMissing("schema_version", "2");
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

    /// <summary>写入/更新插件缓存行。</summary>
    public void UpsertPlugin(string id, string group, int sort, string manifestJson, string dirPath)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            """
            INSERT INTO plugins(id, group_name, sort_order, enabled, manifest_json, dir_path, updated_at)
            VALUES($id, $g, $s, 1, $m, $d, $t)
            ON CONFLICT(id) DO UPDATE SET
              group_name = excluded.group_name,
              sort_order = excluded.sort_order,
              manifest_json = excluded.manifest_json,
              dir_path = excluded.dir_path,
              updated_at = excluded.updated_at
            """;
        cmd.Parameters.AddWithValue("$id", id);
        cmd.Parameters.AddWithValue("$g", group);
        cmd.Parameters.AddWithValue("$s", sort);
        cmd.Parameters.AddWithValue("$m", manifestJson);
        cmd.Parameters.AddWithValue("$d", dirPath);
        cmd.Parameters.AddWithValue("$t", DateTimeOffset.UtcNow.ToString("O"));
        cmd.ExecuteNonQuery();
    }

    /// <summary>读取全部已启用插件；可按 group 过滤。</summary>
    /// <param name="group">为 null 时返回全部。</param>
    public IReadOnlyList<PluginRow> ListPlugins(string? group = null)
    {
        using var cmd = _conn.CreateCommand();
        if (string.IsNullOrWhiteSpace(group))
        {
            cmd.CommandText =
                """
                SELECT id, group_name, sort_order, manifest_json, dir_path
                FROM plugins WHERE enabled = 1
                ORDER BY sort_order ASC, id ASC
                """;
        }
        else
        {
            cmd.CommandText =
                """
                SELECT id, group_name, sort_order, manifest_json, dir_path
                FROM plugins WHERE enabled = 1 AND group_name = $g
                ORDER BY sort_order ASC, id ASC
                """;
            cmd.Parameters.AddWithValue("$g", group);
        }

        var list = new List<PluginRow>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            list.Add(new PluginRow(
                reader.GetString(0),
                reader.GetString(1),
                reader.GetInt32(2),
                reader.GetString(3),
                reader.GetString(4)));
        }

        return list;
    }

    /// <summary>按 id 取一行插件；没有则 null。</summary>
    public PluginRow? GetPlugin(string toolId)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText =
            """
            SELECT id, group_name, sort_order, manifest_json, dir_path
            FROM plugins WHERE id = $id LIMIT 1
            """;
        cmd.Parameters.AddWithValue("$id", toolId);
        using var reader = cmd.ExecuteReader();
        if (!reader.Read()) return null;
        return new PluginRow(
            reader.GetString(0),
            reader.GetString(1),
            reader.GetInt32(2),
            reader.GetString(3),
            reader.GetString(4));
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

/// <summary>plugins 表一行。</summary>
public sealed record PluginRow(
    string Id,
    string Group,
    int SortOrder,
    string ManifestJson,
    string DirPath);

/// <summary>tool_state 表一行。</summary>
public sealed record ToolStateRow(
    string ToolId,
    string Status,
    string? Version,
    string? Detail,
    string CheckedAt);
