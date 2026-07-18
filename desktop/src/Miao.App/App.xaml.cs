using System.Windows;

namespace Miao.App;

/// <summary>
/// WPF 应用程序入口类（对应 App.xaml）。
/// 启动时初始化 SQLite 与插件扫描，再打开主窗口承载 WebView2 UI。
/// </summary>
public partial class App : Application
{
    /// <summary>
    /// 应用启动：先打开本地库并扫描 <c>plugins/</c>，再进入默认启动流程。
    /// </summary>
    /// <param name="e">启动参数。</param>
    protected override void OnStartup(StartupEventArgs e)
    {
        AppServices.EnsureInitialized();
        base.OnStartup(e);
    }
}
