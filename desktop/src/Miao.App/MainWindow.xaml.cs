using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Windows;
using Microsoft.Web.WebView2.Core;
using Miao.App.Boot;
using Miao.App.Bridge;
using Miao.App.Config;
using Miao.Data;

namespace Miao.App;

/// <summary>
/// 主窗口：内嵌 WebView2，加载 Vue UI，并通过 JSON 消息与 <see cref="HostBridge"/> 通信。
/// 启动：主窗 + 遮罩窗 → 导航 /boot → 后台初始化并推送进度 → 收遮罩进入主壳。
/// </summary>
public partial class MainWindow : Window
{
    private const string AppHost = "app.miao.local";
    private static readonly TimeSpan FastPathThreshold = TimeSpan.FromMilliseconds(320);

    private HostBridge? _bridge;
    private BootSplashWindow? _bootSplash;
    private readonly List<object> _bootBuffer = new();
    private bool _bootSubscriberReady;
    private bool _pipelineRunning;
    private bool _bootSplashDismissed;
    private bool _bootDoneSent;
    private CancellationTokenSource? _pipelineCts;

    public MainWindow()
    {
        InitializeComponent();
        SourceInitialized += OnSourceInitialized;
        Loaded += OnLoaded;
    }

    /// <summary>源句柄就绪后立刻盖上遮罩，避免首帧露出 WebView 空底。</summary>
    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        _bootSplash = new BootSplashWindow(this);
        _bootSplash.Show();
        _bootSplash.SyncToOwner();
    }

    private void ShowHostBootError(string message)
    {
        _bootSplash?.ShowError(message);
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            // 锁定外框 DIP，防止 WebView 初始化过程中外框被改尺寸
            if (ActualWidth > 1) Width = ActualWidth;
            if (ActualHeight > 1) Height = ActualHeight;

            // 布局稳定后再对齐客户区遮罩
            _bootSplash?.SyncToOwner();

            await WebView.EnsureCoreWebView2Async().ConfigureAwait(true);

            WebView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = true;
            WebView.CoreWebView2.Settings.AreDevToolsEnabled = true;
            WebView.CoreWebView2.NavigationCompleted += OnNavigationCompleted;

            _bridge = new HostBridge(AppServices.EnsureJobRunner());
            WebView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;

            WebView.CoreWebView2.Settings.IsWebMessageEnabled = true;

            var uiUrl = await ResolveUiUrlAsync().ConfigureAwait(true);
            if (uiUrl is null)
            {
                ShowMissingUiHtml();
                ShowHostBootError("未找到 UI 资源");
                return;
            }

            WebView.CoreWebView2.Navigate(AppendBootHash(uiUrl));
            _ = RunStartupPipelineAsync();
        }
        catch (Exception ex)
        {
            ShowHostBootError("WebView2 初始化失败");
            EmitBootError(ex.Message);
            MessageBox.Show(
                $"WebView2 初始化失败\n{ex.Message}",
                "Miao",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    private void OnNavigationCompleted(object? sender, CoreWebView2NavigationCompletedEventArgs args)
    {
        if (args.IsSuccess)
        {
            // 成功时不收遮罩：等 boot.ui-ready（页面已画好 HTML S0）
            return;
        }

        var detail = args.WebErrorStatus.ToString();
        WebView.CoreWebView2.NavigateToString(
            "<html><body style='font-family:sans-serif;padding:2rem;background:#070b14;color:#e8f4ff'>" +
            "<h1>Miao</h1>" +
            $"<p>页面加载失败：{System.Net.WebUtility.HtmlEncode(detail)}</p>" +
            "<p>开发模式：先在 <code>desktop/ui</code> 执行 <code>npm run dev</code>，" +
            "再设置 <code>MIAO_UI_DEV=1</code> 后启动本程序。</p>" +
            "<p>发布模式：先运行 <code>desktop\\build.ps1</code>，确保 wwwroot 已打入。</p>" +
            "</body></html>");
        // 保留遮罩并显示错误，勿先关掉
        ShowHostBootError("页面加载失败");
    }

    private void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs args)
    {
        try
        {
            var json = args.TryGetWebMessageAsString();
            if (string.IsNullOrWhiteSpace(json)) return;

            if (TryHandleBootMessage(json)) return;

            if (_bridge is null) return;
            _ = _bridge.HandleWebMessageAsync(json, PostToUi);
        }
        catch (Exception ex)
        {
            PostToUi(new { type = "error", message = ex.Message });
        }
    }

    private bool TryHandleBootMessage(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var type = doc.RootElement.TryGetProperty("type", out var t)
                ? t.GetString()
                : null;

            switch (type)
            {
                case "boot.subscribe":
                    _bootSubscriberReady = true;
                    FlushBootBuffer();
                    if (AppServices.IsInitialized && !_pipelineRunning && !_bootDoneSent)
                        EmitBootDone(fastPath: true);
                    else if (!_pipelineRunning && !AppServices.IsInitialized)
                        _ = RunStartupPipelineAsync();
                    return true;

                case "boot.ui-ready":
                    Dispatcher.BeginInvoke(
                        RevealWebViewOverHostSplash,
                        System.Windows.Threading.DispatcherPriority.Loaded);
                    return true;

                default:
                    return false;
            }
        }
        catch
        {
            return false;
        }
    }

    private async Task RunStartupPipelineAsync()
    {
        if (_pipelineRunning) return;
        if (AppServices.IsInitialized)
        {
            EmitBootDone(fastPath: true);
            return;
        }

        _pipelineRunning = true;
        _pipelineCts?.Cancel();
        _pipelineCts = new CancellationTokenSource();
        var sw = Stopwatch.StartNew();

        try
        {
            EmitBootProgress("runtime", "正在连接界面…", 0, phase: "loading");
            SystemConfig.EnsureLoaded();
            EmitBootLog(
                $"启动流水线开始（重试上限 {BootOptions.MaxRetryCount}，单任务超时 {BootOptions.TaskTimeoutSeconds}s；配置 {AppPaths.SystemConfigPath}）");

            var initResult = await Task.Run(() =>
                AppServices.InitializeWithProgress((stage, message, percent) =>
                {
                    Dispatcher.BeginInvoke(() =>
                    {
                        if (stage == "log")
                        {
                            EmitBootLog(message);
                            return;
                        }

                        // 进度只推 Vue；宿主遮罩保持 S0 logo
                        EmitBootProgress(stage, message, percent, phase: "progress");
                        EmitBootLog(message);
                    });
                }), _pipelineCts.Token).ConfigureAwait(true);

            sw.Stop();

            if (initResult.Fatal)
            {
                var msg = initResult.Message ?? "启动失败";
                EmitBootError(msg);
                EmitBootLog($"致命错误，即将退出：{msg}");
                ShowHostBootError("启动失败");
                await Task.Delay(1200).ConfigureAwait(true);
                Application.Current.Shutdown(1);
                return;
            }

            if (initResult.Degraded)
                EmitBootLog("部分数据任务已跳过，进入工具箱");

            var fast = sw.Elapsed < FastPathThreshold && !initResult.Degraded;
            EmitBootLog(fast
                ? $"初始化完成（快速通道 {sw.ElapsedMilliseconds}ms）"
                : $"初始化完成（{sw.ElapsedMilliseconds}ms）");
            EmitBootDone(fastPath: fast, degraded: initResult.Degraded);
            AppServices.StartPostBootSilentTasks();
        }
        catch (OperationCanceledException)
        {
            EmitBootLog("启动已取消");
        }
        catch (Exception ex)
        {
            EmitBootError(ex.Message);
            EmitBootLog($"错误：{ex.Message}");
            ShowHostBootError("启动失败");
            await Task.Delay(1200).ConfigureAwait(true);
            Application.Current.Shutdown(1);
        }
        finally
        {
            _pipelineRunning = false;
        }
    }

    private void EmitBootProgress(string stage, string message, int percent, string phase)
    {
        PostBoot(new
        {
            type = "boot.progress",
            stage,
            message,
            percent,
            phase,
            at = DateTimeOffset.Now.ToString("O"),
        });
    }

    private void EmitBootLog(string message)
    {
        PostBoot(new
        {
            type = "boot.log",
            message,
            at = DateTimeOffset.Now.ToString("O"),
        });
    }

    private void EmitBootDone(bool fastPath, bool degraded = false)
    {
        if (_bootDoneSent) return;
        _bootDoneSent = true;
        PostBoot(new
        {
            type = "boot.done",
            ok = true,
            fastPath,
            degraded,
            at = DateTimeOffset.Now.ToString("O"),
        });
    }

    private void EmitBootError(string message)
    {
        PostBoot(new
        {
            type = "boot.error",
            message,
            at = DateTimeOffset.Now.ToString("O"),
        });
    }

    private void PostBoot(object payload)
    {
        if (!_bootSubscriberReady)
        {
            _bootBuffer.Add(payload);
            return;
        }

        PostToUi(payload);
    }

    private void FlushBootBuffer()
    {
        foreach (var item in _bootBuffer)
            PostToUi(item);
        _bootBuffer.Clear();
    }

    /// <summary>
    /// Vue Boot 已就绪：收起遮罩窗（WebView 始终可见且已画好 HTML S0），再通知淡出 HTML splash。
    /// </summary>
    private void RevealWebViewOverHostSplash()
    {
        DismissBootSplash(instant: true);

        // 遮罩关掉后再通知页面淡出 HTML splash，避免与遮罩关闭叠在同一帧
        Dispatcher.BeginInvoke(
            () =>
            {
                Dispatcher.BeginInvoke(
                    () => PostToUi(new { type = "boot.surface-ready" }),
                    System.Windows.Threading.DispatcherPriority.Render);
            },
            System.Windows.Threading.DispatcherPriority.Loaded);
    }

    private void DismissBootSplash(bool instant)
    {
        if (_bootSplashDismissed) return;
        _bootSplashDismissed = true;
        _bootSplash?.Dismiss(instant);
        _bootSplash = null;
    }

    private void PostToUi(object payload)
    {
        var json = JsonSerializer.Serialize(payload);
        // 异步投递，避免后台线程与 UI 互相等待
        Dispatcher.BeginInvoke(() =>
        {
            try
            {
                WebView.CoreWebView2?.PostWebMessageAsJson(json);
            }
            catch
            {
                /* WebView 尚未就绪时忽略 */
            }
        });
    }

    private async Task<string?> ResolveUiUrlAsync()
    {
        // 与 Vite --host 127.0.0.1 对齐；避免 localhost→::1 / 系统代理把探测拐走
        if (await IsViteUpAsync().ConfigureAwait(true))
            return "http://127.0.0.1:5173/";

        var www = FindWwwRoot();
        if (www is null) return null;

        WebView.CoreWebView2.SetVirtualHostNameToFolderMapping(
            AppHost,
            www,
            CoreWebView2HostResourceAccessKind.Allow);

        return $"https://{AppHost}/index.html";
    }

    /// <summary>在 UI 基址上追加 <c>#/boot</c>。</summary>
    private static string AppendBootHash(string uiUrl)
    {
        const string hash = "#/boot";
        var i = uiUrl.IndexOf('#');
        return i >= 0 ? uiUrl[..i] + hash : uiUrl + hash;
    }

    private void ShowMissingUiHtml()
    {
        WebView.CoreWebView2.NavigateToString(
            "<html><body style='font-family:sans-serif;padding:2rem;background:#070b14;color:#e8f4ff'>" +
            "<h1>Miao</h1><p>未找到 UI。</p>" +
            "<p>开发：<code>cd desktop/ui && npm run dev</code>，然后 " +
            "<code>$env:MIAO_UI_DEV='1'; dotnet run --project src/Miao.App</code></p>" +
            "<p>发布：<code>.\\desktop\\build.ps1</code></p>" +
            "</body></html>");
    }

    private static string? FindWwwRoot()
    {
        var baseDir = AppContext.BaseDirectory;
        var inOutput = Path.Combine(baseDir, "wwwroot");
        if (File.Exists(Path.Combine(inOutput, "index.html")))
            return inOutput;

        var inProject = Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "wwwroot"));
        if (File.Exists(Path.Combine(inProject, "index.html")))
            return inProject;

        var dist = Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "..", "ui", "dist"));
        if (File.Exists(Path.Combine(dist, "index.html")))
            return dist;

        return null;
    }

    private static async Task<bool> IsViteUpAsync()
    {
        try
        {
            using var handler = new HttpClientHandler { UseProxy = false };
            using var client = new HttpClient(handler) { Timeout = TimeSpan.FromMilliseconds(800) };
            using var resp = await client.GetAsync("http://127.0.0.1:5173/").ConfigureAwait(false);
            return resp.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }
}
