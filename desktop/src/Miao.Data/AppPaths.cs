using System.IO;
using Microsoft.Data.Sqlite;

namespace Miao.Data;

/// <summary>
/// 应用数据与插件目录路径（LocalAppData + 内置 plugins + 用户自定义 plugins）。
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
    /// 用户自定义插件根：%LocalAppData%\Miao\plugins\（结构同 daily/dev）。
    /// 目录始终确保存在，便于后续放入插件而无需改扫描逻辑。
    /// </summary>
    public static string UserPluginsRoot
    {
        get
        {
            var root = Path.Combine(DataRoot, "plugins");
            Directory.CreateDirectory(root);
            // 预留分类空目录，方便用户直接丢插件
            Directory.CreateDirectory(Path.Combine(root, "daily"));
            Directory.CreateDirectory(Path.Combine(root, "dev"));
            return root;
        }
    }

    /// <summary>
    /// 解析插件扫描根：先内置（输出目录 / 开发期仓库），再用户目录（同 id 后者覆盖）。
    /// </summary>
    public static IReadOnlyList<string> ResolvePluginRoots()
    {
        var list = new List<string>();

        var besideExe = Path.Combine(AppContext.BaseDirectory, "plugins");
        if (Directory.Exists(besideExe))
            list.Add(Path.GetFullPath(besideExe));

        // bin/Debug/net10.0-windows -> Miao.App -> src -> desktop
        var desktopPlugins = Path.GetFullPath(
            Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "plugins"));
        if (Directory.Exists(desktopPlugins) &&
            !list.Any(p => string.Equals(p, desktopPlugins, StringComparison.OrdinalIgnoreCase)))
        {
            list.Add(desktopPlugins);
        }

        var user = Path.GetFullPath(UserPluginsRoot);
        if (!list.Any(p => string.Equals(p, user, StringComparison.OrdinalIgnoreCase)))
            list.Add(user);

        return list;
    }
}
