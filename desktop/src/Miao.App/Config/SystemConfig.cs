using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using Miao.Data;

namespace Miao.App.Config;

/// <summary>
/// 系统配置（<see cref="AppPaths.SystemConfigPath"/>）。
/// 缺失时写入默认文件，便于手工调配。
/// </summary>
public static class SystemConfig
{
    private static readonly object Gate = new();
    private static SystemConfigRoot? _current;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    /// <summary>当前已加载配置（先调用 <see cref="EnsureLoaded"/>）。</summary>
    public static SystemConfigRoot Current
    {
        get
        {
            EnsureLoaded();
            return _current!;
        }
    }

    /// <summary>从磁盘加载；不存在则创建默认 <c>system.json</c>。</summary>
    public static SystemConfigRoot EnsureLoaded(bool forceReload = false)
    {
        lock (Gate)
        {
            if (_current is not null && !forceReload)
                return _current;

            var path = AppPaths.SystemConfigPath;
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);

            if (!File.Exists(path))
            {
                _current = SystemConfigRoot.CreateDefault();
                WriteFile(path, _current);
                return _current;
            }

            try
            {
                var raw = File.ReadAllText(path);
                var parsed = JsonSerializer.Deserialize<SystemConfigRoot>(raw, JsonOptions);
                _current = parsed ?? SystemConfigRoot.CreateDefault();
                // 补全缺省段，避免旧文件缺字段
                _current.Boot ??= new BootConfigSection();
                return _current;
            }
            catch
            {
                _current = SystemConfigRoot.CreateDefault();
                return _current;
            }
        }
    }

    private static void WriteFile(string path, SystemConfigRoot root)
    {
        var json = JsonSerializer.Serialize(root, JsonOptions);
        File.WriteAllText(path, json + Environment.NewLine);
    }
}

/// <summary>系统配置根文档。</summary>
public sealed class SystemConfigRoot
{
    /// <summary>启动流水线。</summary>
    public BootConfigSection Boot { get; set; } = new();

    public static SystemConfigRoot CreateDefault() => new()
    {
        Boot = new BootConfigSection(),
    };
}

/// <summary>启动相关可调项。</summary>
public sealed class BootConfigSection
{
    /// <summary>单任务失败时最大尝试次数（含首次）。</summary>
    public int MaxRetryCount { get; set; } = 5;

    /// <summary>单任务执行超时（秒）。</summary>
    public int TaskTimeoutSeconds { get; set; } = 30;
}
