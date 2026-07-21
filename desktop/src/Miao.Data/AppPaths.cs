namespace Miao.Data;

/// <summary>
/// 应用数据与种子目录路径（LocalAppData + 打包内 seeds）。
/// 开发与安装版数据根分离；开发库每次启动重建。
/// </summary>
public static class AppPaths
{
    /// <summary>安装版用户数据目录名：%LocalAppData%\Miao\</summary>
    public const string ProductFolderName = "Miao";

    /// <summary>开发专用数据目录名：%LocalAppData%\Miao-dev\（与安装版互不影响）。</summary>
    public const string DevProductFolderName = "Miao-dev";

    /// <summary>
    /// 是否使用开发数据配置（独立目录 + 每次重建库）。
    /// 条件：环境变量 <c>MIAO_UI_DEV=1</c>，或 Debug 编译。
    /// </summary>
    public static bool IsDevDataProfile
    {
        get
        {
            var env = Environment.GetEnvironmentVariable("MIAO_UI_DEV");
            if (string.Equals(env, "1", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(env, "true", StringComparison.OrdinalIgnoreCase))
                return true;

#if DEBUG
            return true;
#else
            return false;
#endif
        }
    }

    /// <summary>
    /// 用户数据根：安装版 <c>%LocalAppData%\Miao\</c>；开发 <c>%LocalAppData%\Miao-dev\</c>。
    /// </summary>
    public static string DataRoot
    {
        get
        {
            var folder = IsDevDataProfile ? DevProductFolderName : ProductFolderName;
            var root = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                folder);
            Directory.CreateDirectory(root);
            return root;
        }
    }

    /// <summary>SQLite 数据库文件路径。</summary>
    public static string DatabasePath => Path.Combine(DataRoot, "miao.db");

    /// <summary>系统配置 JSON：<c>%LocalAppData%\Miao\system.json</c>（开发为 Miao-dev）。</summary>
    public static string SystemConfigPath => Path.Combine(DataRoot, "system.json");

    /// <summary>
    /// 开发配置下删除本地库文件（含 WAL/SHM），使下次打开走完整建库 + 种子灌入。
    /// 安装版无操作。
    /// </summary>
    public static void ResetDevDatabaseIfNeeded()
    {
        if (!IsDevDataProfile) return;

        var path = DatabasePath;
        foreach (var file in new[]
                 {
                     path,
                     path + "-wal",
                     path + "-shm",
                     path + "-journal",
                 })
        {
            try
            {
                if (File.Exists(file))
                    File.Delete(file);
            }
            catch (IOException)
            {
                // 占用时留给后续打开失败提示；不阻断启动流水线重试
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    /// <summary>
    /// 解析种子根目录：优先输出目录旁 seeds，开发期回退到仓库 desktop/seeds。
    /// </summary>
    public static string? ResolveSeedsRoot()
    {
        var besideExe = Path.Combine(AppContext.BaseDirectory, "seeds");
        if (Directory.Exists(besideExe))
            return Path.GetFullPath(besideExe);

        // bin/Debug/net10.0-windows -> Miao.App -> src -> desktop
        var desktopSeeds = Path.GetFullPath(
            Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "seeds"));
        if (Directory.Exists(desktopSeeds))
            return desktopSeeds;

        return null;
    }
}
