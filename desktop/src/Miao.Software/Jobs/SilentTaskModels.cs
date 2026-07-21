namespace Miao.Software.Jobs;

/// <summary>静默任务状态。</summary>
public enum SilentTaskStatus
{
    Pending,
    Running,
    Succeeded,
    Failed,
    Cancelled,
}

/// <summary>静默任务快照（推 UI）。</summary>
public sealed record SilentTaskInfo(
    string Id,
    string Title,
    string Status,
    int Progress,
    string? Detail,
    string UpdatedAt);

/// <summary>队列摘要。</summary>
public sealed record SilentQueueSnapshot(
    int ActiveCount,
    int TotalQueued,
    IReadOnlyList<SilentTaskInfo> Tasks);
