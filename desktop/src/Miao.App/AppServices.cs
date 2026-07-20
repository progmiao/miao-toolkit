using Miao.Data;
using Miao.Sites;
using Miao.Software.Catalog;
using Miao.Software.Claude;
using Miao.Software.Jobs;
using Miao.Software.Volta;
using Miao.Utilities;

namespace Miao.App;

/// <summary>
/// 进程级服务：数据库、软件目录、网站、工具集、Volta、Claude、JobRunner。
/// </summary>
public static class AppServices
{
    private static readonly object Gate = new();
    private static AppDatabase? _db;
    private static SoftwareCatalog? _software;
    private static SiteService? _sites;
    private static UtilitiesService? _utilities;
    private static VoltaPackageService? _volta;
    private static ClaudeCodeService? _claude;
    private static JobRunner? _jobs;

    /// <summary>本地 SQLite。</summary>
    public static AppDatabase Db
    {
        get { EnsureInitialized(); return _db!; }
    }

    /// <summary>软件目录。</summary>
    public static SoftwareCatalog Software
    {
        get { EnsureInitialized(); return _software!; }
    }

    /// <summary>常用网站。</summary>
    public static SiteService Sites
    {
        get { EnsureInitialized(); return _sites!; }
    }

    /// <summary>工具集。</summary>
    public static UtilitiesService Utilities
    {
        get { EnsureInitialized(); return _utilities!; }
    }

    /// <summary>Volta 包版本清单（node / pnpm / yarn）。</summary>
    public static VoltaPackageService Volta
    {
        get { EnsureInitialized(); return _volta!; }
    }

    /// <summary>Claude Code 配置与插件。</summary>
    public static ClaudeCodeService Claude
    {
        get { EnsureInitialized(); return _claude!; }
    }

    /// <summary>任务执行器。</summary>
    public static JobRunner Jobs
    {
        get { EnsureInitialized(); return _jobs!; }
    }

    /// <summary>幂等初始化。</summary>
    public static void EnsureInitialized()
    {
        if (_db is not null && _software is not null && _jobs is not null) return;
        lock (Gate)
        {
            if (_db is not null && _software is not null && _jobs is not null) return;
            _db = new AppDatabase(AppPaths.DatabasePath);
            SeedLoader.ApplyIfNeeded(_db);
            _claude = new ClaudeCodeService();
            _volta = new VoltaPackageService();
            _software = new SoftwareCatalog(_db, _claude, _volta);
            _software.Refresh();
            _sites = new SiteService(_db);
            _utilities = new UtilitiesService(_db);
            _jobs = new JobRunner();
        }
    }
}
