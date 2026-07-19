using Miao.Common.Jobs;
using Miao.Common.Software;
using Miao.Data;
using Miao.Software.Jobs;

namespace Miao.Software;

/// <summary>
/// 单次动作执行上下文（含完整定义，供通用 Handler 读 install 配置）。
/// </summary>
public sealed class ToolActionContext
{
    /// <summary>创建上下文。</summary>
    /// <param name="jobId">任务 id。</param>
    /// <param name="toolId">软件 id。</param>
    /// <param name="action">动作 id。</param>
    /// <param name="manifest">软件定义。</param>
    /// <param name="seedDir">种子根目录。</param>
    /// <param name="jobs">任务执行器。</param>
    /// <param name="db">数据库。</param>
    /// <param name="versions">可选版本 / 插件 id 列表。</param>
    /// <param name="options">附加键值（如 projectPath、plugins）。</param>
    public ToolActionContext(
        string jobId,
        string toolId,
        string action,
        SoftwareDefinition manifest,
        string seedDir,
        JobRunner jobs,
        AppDatabase db,
        IReadOnlyList<string>? versions = null,
        IReadOnlyDictionary<string, string>? options = null)
    {
        JobId = jobId;
        ToolId = toolId;
        Action = action;
        Manifest = manifest;
        SeedDir = seedDir;
        Jobs = jobs;
        Db = db;
        Versions = versions ?? Array.Empty<string>();
        Options = options ?? new Dictionary<string, string>();
    }

    /// <summary>任务 id。</summary>
    public string JobId { get; }

    /// <summary>软件 id。</summary>
    public string ToolId { get; }

    /// <summary>动作 id（install / uninstall / set-default / pin 等）。</summary>
    public string Action { get; }

    /// <summary>已反序列化的软件定义。</summary>
    public SoftwareDefinition Manifest { get; }

    /// <summary>种子根目录绝对路径。</summary>
    public string SeedDir { get; }

    /// <summary>任务执行器。</summary>
    public JobRunner Jobs { get; }

    /// <summary>数据库（写 tool_state）。</summary>
    public AppDatabase Db { get; }

    /// <summary>目标版本或插件 id 列表。</summary>
    public IReadOnlyList<string> Versions { get; }

    /// <summary>附加选项（projectPath、plugins 等）。</summary>
    public IReadOnlyDictionary<string, string> Options { get; }
}

/// <summary>按 handler 键注册的动作处理器。</summary>
public interface IToolActionHandler
{
    /// <summary>处理器键，与 seeds 中 actions[].handler 一致。</summary>
    string HandlerId { get; }

    /// <summary>执行动作；失败时返回 Ok=false 的 JobResult。</summary>
    Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default);
}
