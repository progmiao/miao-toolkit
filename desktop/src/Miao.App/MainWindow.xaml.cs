using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Windows;
using Microsoft.Web.WebView2.Core;
using Miao.App.Bridge;

namespace Miao.App;

/// <summary>
/// 主窗口：内嵌 WebView2，加��? Vue UI，并通过 JSON 消息��? <see cref="HostBridge"/> 通信��?
/// </summary>
/// <remarks>
/// UI 加载优先级：
/// 1) ��?��? Vite 开发服务器 http://localhost:5173/（热更新）；
/// 2) 输出��?录或工程内的 wwwroot（经虚拟主机映射，避��? file:// 无法加载 ES module）；
/// 3) 均不��?用时显示说明页��?
/// </remarks>
public partial class MainWindow : Window
{
    /// <summary>
    /// WebView2 虚拟主机名，映射到本��? wwwroot/dist 文件夹��?
    /// 必须使用 https 形式导航，才能�?�确加载 Vite 构建的模块脚��?��?
    /// </summary>
    private const string AppHost = "app.miao.local";

    /// <summary>Vue �� C# ��Ϣ�ţ��� WebView2 �����󴴽���</summary>
    private HostBridge? _bridge;

    /// <summary>���������ڲ��ҽ� Loaded���Ա��첽��ʼ�� WebView2��</summary>
    public MainWindow()
    {
        InitializeComponent();
        AppServices.EnsureInitialized();
        Loaded += OnLoaded;
    }

    /// <summary>
    /// 窗口加载完成后初始化 WebView2、消��?桥，并�?�航��? Vue UI��?
    /// </summary>
    /// <param name="sender">事件源（��?窗口）��?</param>
    /// <param name="e">��?由事件参数��?</param>
    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            await WebView.EnsureCoreWebView2Async();
            WebView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = true;
            WebView.CoreWebView2.Settings.AreDevToolsEnabled = true;
            WebView.CoreWebView2.NavigationCompleted += OnNavigationCompleted;

            _bridge = new HostBridge(AppServices.Jobs, Dispatcher);
            WebView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;

            var uiUrl = await ResolveUiUrlAsync().ConfigureAwait(true);
            if (uiUrl is null)
            {
                ShowMissingUiHtml();
                return;
            }

            WebView.CoreWebView2.Navigate(uiUrl);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"WebView2 初�?�化失败\n{ex.Message}",
                "Miao",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    /// <summary>
    /// 导航结束后回调；失败时用内嵌 HTML 提示开��?/发布如何恢�?? UI��?
    /// </summary>
    /// <param name="sender">WebView2 核心对象��?</param>
    /// <param name="args">��?否成功及 <see cref="CoreWebView2WebErrorStatus"/>��?</param>
    private void OnNavigationCompleted(object? sender, CoreWebView2NavigationCompletedEventArgs args)
    {
        if (args.IsSuccess) return;

        var detail = args.WebErrorStatus.ToString();
        WebView.CoreWebView2.NavigateToString(
            "<html><body style='font-family:sans-serif;padding:2rem;background:#111;color:#eee'>" +
            "<h1>Miao</h1>" +
            $"<p>页面加载失败：{System.Net.WebUtility.HtmlEncode(detail)}</p>" +
            "<p>开发模式：先在 <code>desktop/ui</code> 执�?? <code>npm run dev</code>��?" +
            "再�?�置 <code>MIAO_UI_DEV=1</code> 后启动本程序��?</p>" +
            "<p>发布模式：先��? <code>desktop\\build.ps1</code>，确��? wwwroot 已打入��?</p>" +
            "</body></html>");
    }

    /// <summary>
    /// 接收 Vue 通过 chrome.webview.postMessage 发来��? JSON，交��? <see cref="HostBridge"/>��?
    /// </summary>
    /// <param name="sender">事件源��?</param>
    /// <param name="args">原�?? WebMessage；优先用字�?�串 JSON��?</param>
    private void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs args)
    {
        try
        {
            var json = args.TryGetWebMessageAsString();
            if (string.IsNullOrWhiteSpace(json) || _bridge is null)
            {
                return;
            }

            _ = _bridge.HandleWebMessageAsync(json, PostToUi);
        }
        catch (Exception ex)
        {
            PostToUi(new { type = "error", message = ex.Message });
        }
    }

    /// <summary>
    /// 将�?�主对象序列化为 JSON，投递回 Vue（必须在 UI 线程调用 PostWebMessageAsJson）��?
    /// </summary>
    /// <param name="payload">��?��? System.Text.Json 序列化的匿名对象��? DTO��?</param>
    private void PostToUi(object payload)
    {
        var json = JsonSerializer.Serialize(payload);
        Dispatcher.Invoke(() =>
        {
            WebView.CoreWebView2?.PostWebMessageAsJson(json);
        });
    }

    /// <summary>
    /// 解析当前应加载的 UI 地址��?
    /// </summary>
    /// <returns>
    /// Vite 或虚拟主��? URL；若找不到任何静态资源则返回 <c>null</c>（由调用方显示缺 UI 页）��?
    /// </returns>
    private async Task<string?> ResolveUiUrlAsync()
    {
        if (await IsViteUpAsync().ConfigureAwait(true))
        {
            return "http://localhost:5173/";
        }

        var www = FindWwwRoot();
        if (www is null)
        {
            return null;
        }

        // file:// 无法��? WebView2 ��?加载 Vite ES module；映射虚��? HTTPS 主机��?
        WebView.CoreWebView2.SetVirtualHostNameToFolderMapping(
            AppHost,
            www,
            CoreWebView2HostResourceAccessKind.Allow);

        return $"https://{AppHost}/index.html";
    }

    /// <summary>��? WebView ��?显示「未找到 UI」的操作说明（开��? / 发布两条��?径）��?</summary>
    private void ShowMissingUiHtml()
    {
        WebView.CoreWebView2.NavigateToString(
            "<html><body style='font-family:sans-serif;padding:2rem;background:#111;color:#eee'>" +
            "<h1>Miao</h1><p>��?找到 UI��?</p>" +
            "<p>开发：<code>cd desktop/ui && npm run dev</code>，然��? " +
            "<code>$env:MIAO_UI_DEV='1'; dotnet run --project src/Miao.App</code></p>" +
            "<p>发布��?<code>.\\desktop\\build.ps1</code></p>" +
            "</body></html>");
    }

    /// <summary>
    /// 按优先级查找包含 index.html 的前��?静态目录��?
    /// </summary>
    /// <returns>绝�?�路径；都未找到时返��? <c>null</c>��?</returns>
    /// <remarks>
    /// 查找顺序��?
    /// 1) 输出��?录旁 wwwroot（Content 复制）；
    /// 2) 工程��?��? wwwroot（src/Miao.App/wwwroot）；
    /// 3) ui/dist（本地刚 build 尚未拷贝时）��?
    /// BaseDirectory 形�?? .../bin/Debug/net10.0-windows/��?
    /// </remarks>
    private static string? FindWwwRoot()
    {
        var baseDir = AppContext.BaseDirectory;
        var inOutput = Path.Combine(baseDir, "wwwroot");
        if (File.Exists(Path.Combine(inOutput, "index.html")))
        {
            return inOutput;
        }

        var inProject = Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "wwwroot"));
        if (File.Exists(Path.Combine(inProject, "index.html")))
        {
            return inProject;
        }

        var dist = Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "..", "ui", "dist"));
        if (File.Exists(Path.Combine(dist, "index.html")))
        {
            return dist;
        }

        return null;
    }

    /// <summary>
    /// 探测 Vite 开发服务器��?否已��? 5173 ��?口就��?��?
    /// </summary>
    /// <returns>HTTP 成功��? <c>true</c>；超时或连接失败��? <c>false</c>（不抛异常）��?</returns>
    private static async Task<bool> IsViteUpAsync()
    {
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromMilliseconds(400) };
            using var resp = await client.GetAsync("http://localhost:5173/").ConfigureAwait(false);
            return resp.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }
}
