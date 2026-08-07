using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace Miao.App;

/// <summary>
/// 启动期置顶遮罩：独立窗口盖住主窗 WebView2，避免 Hidden→Visible 闪缩。
/// 仅对齐主窗<strong>客户区</strong>（不含标题栏/边框），切换时外框尺寸不变。
/// </summary>
public partial class BootSplashWindow : Window
{
    private readonly Window _owner;
    private bool _closing;
    private bool _syncing;

    public BootSplashWindow(Window owner)
    {
        _owner = owner;
        InitializeComponent();
        Owner = owner;
        LoadAscii();
        SyncToOwner();
        owner.LocationChanged += OnOwnerBoundsChanged;
        owner.SizeChanged += OnOwnerBoundsChanged;
        owner.StateChanged += OnOwnerBoundsChanged;
        owner.Closed += OnOwnerClosed;
    }

    public void ShowError(string message)
    {
        HostBootHint.Text = message;
        HostBootHint.Visibility = Visibility.Visible;
    }

    /// <summary>对齐主窗客户区，标题栏始终属于主窗，避免收遮罩时「窗口变小」。</summary>
    public void SyncToOwner()
    {
        if (_closing || _syncing) return;
        if (!_owner.IsVisible && !_owner.IsLoaded) return;

        _syncing = true;
        try
        {
            var content = _owner.Content as FrameworkElement;
            var source = PresentationSource.FromVisual(_owner);

            if (content is null
                || content.ActualWidth <= 1
                || content.ActualHeight <= 1
                || source?.CompositionTarget is null)
            {
                // 布局未就绪：先贴主窗外框，Loaded 后再收紧到客户区
                Left = _owner.Left;
                Top = _owner.Top;
                Width = _owner.ActualWidth > 1 ? _owner.ActualWidth : _owner.Width;
                Height = _owner.ActualHeight > 1 ? _owner.ActualHeight : _owner.Height;
                return;
            }

            // Window (0,0) = 客户区左上；PointToScreen 为物理像素，需转回 DIP
            var screenTl = _owner.PointToScreen(new Point(0, 0));
            var dipTl = source.CompositionTarget.TransformFromDevice.Transform(screenTl);

            Left = dipTl.X;
            Top = dipTl.Y;
            Width = content.ActualWidth;
            Height = content.ActualHeight;
        }
        catch
        {
            /* 句柄/视觉树尚未就绪 */
        }
        finally
        {
            _syncing = false;
        }
    }

    public void Dismiss(bool instant = true)
    {
        if (_closing) return;
        _closing = true;
        DetachOwner();

        if (instant || !IsVisible)
        {
            Close();
            return;
        }

        var anim = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(180))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut },
        };
        anim.Completed += (_, _) => Close();
        BeginAnimation(OpacityProperty, anim);
    }

    private void LoadAscii()
    {
        try
        {
            var uri = new Uri("pack://application:,,,/Assets/ascii-logo.txt");
            var info = Application.GetResourceStream(uri);
            if (info?.Stream is null) return;
            using var reader = new StreamReader(info.Stream);
            var raw = reader.ReadToEnd();
            HostBootAscii.Text = string.Join(
                "\n",
                raw.Replace("\uFEFF", "")
                    .Replace("\r\n", "\n")
                    .Split('\n')
                    .Select(l => l.TrimEnd())
                    .Where(l => !string.IsNullOrWhiteSpace(l)));
        }
        catch
        {
            HostBootAscii.Text = "Miao";
        }
    }

    private void OnOwnerBoundsChanged(object? sender, EventArgs e) => SyncToOwner();

    private void OnOwnerClosed(object? sender, EventArgs e)
    {
        DetachOwner();
        if (!_closing)
        {
            _closing = true;
            Close();
        }
    }

    private void DetachOwner()
    {
        _owner.LocationChanged -= OnOwnerBoundsChanged;
        _owner.SizeChanged -= OnOwnerBoundsChanged;
        _owner.StateChanged -= OnOwnerBoundsChanged;
        _owner.Closed -= OnOwnerClosed;
    }
}
