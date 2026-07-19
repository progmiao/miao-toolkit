namespace Miao.Data;

/// <summary>
/// 应用数据与种子目录路径（LocalAppData + 打包内 seeds）。
/// </summary>
public static class AppPaths
{
    /// <summary>产品在 LocalAppData 下的根目录名。</summary>
    public const string ProductFolderName = "Miao";

    /// <summary>用户数据根：%LocalAppData%\Miao\</summary>
    public static string DataRoot
    {
        get
        {
            var root = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                ProductFolderName);
            Directory.CreateDirectory(root);
            return root;
        }
    }

    /// <summary>SQLite 数据库文件路径。</summary>
    public static string DatabasePath => Path.Combine(DataRoot, "miao.db");

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
