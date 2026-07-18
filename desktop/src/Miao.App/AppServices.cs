using Miao.Data;
using Miao.Tools.Jobs;
using Miao.Tools.Plugins;

namespace Miao.App;

/// <summary>
/// 进程级服务：数据库、插件宿主、JobRunner（启动时初始化一次）。
/// </summary>
public static class AppServices
{
    private static readonly object Gate = new();
    private static AppDatabase? _db;
    private static PluginHost? _plugins;
    private static JobRunner? _jobs;

    /// <summary>本地 SQLite。</summary>
    public static AppDatabase Db
    {
        get { EnsureInitialized(); return _db!; }
    }

    /// <summary>插件宿主。</summary>
    public static PluginHost Plugins
    {
        get { EnsureInitialized(); return _plugins!; }
    }

    /// <summary>任务执行器（单例，供 Bridge 订阅事件）。</summary>
    public static JobRunner Jobs
    {
        get { EnsureInitialized(); return _jobs!; }
    }

    /// <summary>幂等初始化。</summary>
    public static void EnsureInitialized()
    {
        if (_db is not null && _plugins is not null && _jobs is not null) return;
        lock (Gate)
        {
            if (_db is not null && _plugins is not null && _jobs is not null) return;
            _ = AppPaths.UserPluginsRoot; // 确保自定义插件目录与 daily/dev 占位存在
            _db = new AppDatabase(AppPaths.DatabasePath);
            _plugins = new PluginHost(_db);
            _plugins.RefreshFromDisk();
            _jobs = new JobRunner();
        }
    }
}
