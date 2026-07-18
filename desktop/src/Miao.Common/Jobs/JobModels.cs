namespace Miao.Common.Jobs;

/// <summary>
/// 任务过程中的一条事件。
/// </summary>
/// <param name="JobId">关联任务 id。</param>
/// <param name="Kind">种类（log / progress / done / error）。</param>
/// <param name="Message">文本载荷。</param>
/// <param name="At">事件时间（本地偏移）。</param>
public sealed record JobEvent(string JobId, string Kind, string Message, DateTimeOffset At);

/// <summary>
/// 任务最终结果。
/// </summary>
/// <param name="JobId">关联任务 id。</param>
/// <param name="Ok">是否成功（退出码 0）。</param>
/// <param name="ExitCode">进程退出码；启动失败或取消时为 -1。</param>
/// <param name="Detail">stderr 汇总或 cancelled 等说明。</param>
public sealed record JobResult(string JobId, bool Ok, int ExitCode, string Detail);
