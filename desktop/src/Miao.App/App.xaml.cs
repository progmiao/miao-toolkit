using System.Windows;

namespace Miao.App;

/// <summary>
/// WPF 应用程序入口类（对应 App.xaml）。
/// 出窗后再做库与服务初始化，避免启动白屏长时间无反馈。
/// </summary>
public partial class App : Application
{
    /// <summary>
    /// 应用启动：尽快进入默认流程以显示主窗口（初始化在 MainWindow 流水线中完成）。
    /// </summary>
    /// <param name="e">启动参数。</param>
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
    }
}
