using Miao.App.Config;

namespace Miao.App.Boot;

/// <summary>
/// 启动流水线配置：读取 <c>system.json</c> 的 <c>boot</c> 段（可手工编辑）。
/// </summary>
public static class BootOptions
{
    /// <summary>单任务失败时最大重试次数（含首次）。来自 system.json → boot.maxRetryCount。</summary>
    public static int MaxRetryCount
    {
        get
        {
            SystemConfig.EnsureLoaded();
            return Math.Clamp(SystemConfig.Current.Boot.MaxRetryCount, 1, 20);
        }
    }

    /// <summary>单任务执行超时（秒）。来自 system.json → boot.taskTimeoutSeconds。</summary>
    public static int TaskTimeoutSeconds
    {
        get
        {
            SystemConfig.EnsureLoaded();
            return Math.Clamp(SystemConfig.Current.Boot.TaskTimeoutSeconds, 3, 600);
        }
    }

    /// <summary>单任务超时。</summary>
    public static TimeSpan TaskTimeout => TimeSpan.FromSeconds(TaskTimeoutSeconds);
}

/// <summary>启动任务严重级别。</summary>
public enum BootTaskSeverity
{
    /// <summary>核心：达重试上限则无法进入工具箱，关闭窗口。</summary>
    Critical,

    /// <summary>数据：达重试上限可跳过，仍进入主壳。</summary>
    Data,
}

/// <summary><see cref="AppServices.InitializeWithProgress"/> 结果。</summary>
public sealed class BootInitResult
{
    public bool Ok { get; init; }
    public bool Fatal { get; init; }
    public bool Degraded { get; init; }
    public string? Message { get; init; }

    public static BootInitResult Success(bool degraded = false) =>
        new() { Ok = true, Fatal = false, Degraded = degraded };

    public static BootInitResult FatalFail(string message) =>
        new() { Ok = false, Fatal = true, Message = message };

    public static BootInitResult AlreadyReady() =>
        new() { Ok = true, Fatal = false, Degraded = false };
}
