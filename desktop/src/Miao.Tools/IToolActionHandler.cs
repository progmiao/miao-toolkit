using Miao.Common.Jobs;
using Miao.Common.Plugins;
using Miao.Data;
using Miao.Tools.Jobs;

namespace Miao.Tools;

/// <summary>
/// 单次动作执行上下文（含完整 manifest，供通用 Handler 读 install 配置）。
/// </summary>
public sealed class ToolActionContext
{
    /// <summary>创建上下文。</summary>
    public ToolActionContext(
        string jobId,
        string toolId,
        string action,
        PluginManifest manifest,
        string pluginDir,
        JobRunner jobs,
        AppDatabase db)
    {
        JobId = jobId;
        ToolId = toolId;
        Action = action;
        Manifest = manifest;
        PluginDir = pluginDir;
        Jobs = jobs;
        Db = db;
    }

    /// <summary>任务 id。</summary>
    public string JobId { get; }

    /// <summary>插件 id。</summary>
    public string ToolId { get; }

    /// <summary>动作 id（install / uninstall 等）。</summary>
    public string Action { get; }

    /// <summary>已反序列化的 plugin.json。</summary>
    public PluginManifest Manifest { get; }

    /// <summary>插件目录绝对路径。</summary>
    public string PluginDir { get; }

    /// <summary>任务执行器。</summary>
    public JobRunner Jobs { get; }

    /// <summary>数据库（写 tool_state）。</summary>
    public AppDatabase Db { get; }
}

/// <summary>按 handler 键注册的动作处理器。</summary>
public interface IToolActionHandler
{
    /// <summary>处理器键，与 plugin.json actions[].handler 一致。</summary>
    string HandlerId { get; }

    /// <summary>执行动作。</summary>
    Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default);
}
