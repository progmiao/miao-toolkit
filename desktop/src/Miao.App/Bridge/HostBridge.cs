using System.Text.Json;
using System.Windows.Threading;
using Miao.Tools.Jobs;

namespace Miao.App.Bridge;

/// <summary>
/// Vue ↔ C# IPC：目录（按 daily/dev）、分组、Job。
/// </summary>
public sealed class HostBridge
{
    private readonly JobRunner _jobs;
    private readonly Dictionary<string, CancellationTokenSource> _running = new();
    private Action<object>? _post;

    /// <summary>创建消息桥。</summary>
    public HostBridge(JobRunner jobs, Dispatcher _)
    {
        _jobs = jobs;
        _jobs.Event += OnJobEvent;
        AppServices.EnsureInitialized();
    }

    private void OnJobEvent(Miao.Common.Jobs.JobEvent ev)
    {
        _post?.Invoke(new
        {
            type = "job-event",
            jobId = ev.JobId,
            kind = ev.Kind,
            message = ev.Message,
            at = ev.At
        });
    }

    /// <summary>处理来自 Vue 的 JSON。</summary>
    public async Task HandleWebMessageAsync(string json, Action<object> postToUi)
    {
        _post = postToUi;
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        var type = root.GetProperty("type").GetString() ?? "";

        switch (type)
        {
            case "ping":
                postToUi(new { type = "pong", at = DateTimeOffset.Now });
                break;

            case "get-groups":
                postToUi(new
                {
                    type = "groups",
                    groups = AppServices.Plugins.GetGroups(AppServices.Db.GetSetting("locale", "zh"))
                });
                break;

            case "get-catalog":
            {
                var group = root.TryGetProperty("group", out var g) ? g.GetString() : null;
                PostCatalog(postToUi, group);
                break;
            }

            case "get-app-info":
                postToUi(new
                {
                    type = "app-info",
                    name = "Miao",
                    version = typeof(HostBridge).Assembly.GetName().Version?.ToString() ?? "0.1.0"
                });
                break;

            case "run-job":
                await StartJobAsync(root, postToUi).ConfigureAwait(false);
                break;

            case "cancel-job":
                CancelJob(root);
                break;

            default:
                postToUi(new { type = "error", message = $"未知消息类型: {type}" });
                break;
        }
    }

    private static void PostCatalog(Action<object> postToUi, string? group)
    {
        var locale = AppServices.Db.GetSetting("locale", "zh");
        var items = AppServices.Plugins.GetCatalog(locale, group);
        postToUi(new { type = "catalog", group, items });
    }

    private async Task StartJobAsync(JsonElement root, Action<object> postToUi)
    {
        var jobId = root.TryGetProperty("jobId", out var idEl)
            ? idEl.GetString() ?? Guid.NewGuid().ToString("N")
            : Guid.NewGuid().ToString("N");

        var toolId = root.TryGetProperty("toolId", out var t) ? t.GetString() : null;
        var action = root.TryGetProperty("action", out var a) ? a.GetString() : "install";

        if (string.IsNullOrWhiteSpace(toolId))
        {
            postToUi(new { type = "error", message = "缺少 toolId" });
            return;
        }

        if (!AppServices.Plugins.Contains(toolId!))
        {
            postToUi(new { type = "job-event", jobId, kind = "error", message = $"未知插件: {toolId}" });
            return;
        }

        var cts = new CancellationTokenSource();
        lock (_running) { _running[jobId] = cts; }

        postToUi(new { type = "job-started", jobId, toolId, action });

        try
        {
            var result = await AppServices.Plugins
                .ExecuteAsync(jobId, toolId!, action ?? "install", _jobs, cts.Token)
                .ConfigureAwait(false);

            AppServices.Plugins.ProbeTool(toolId!);
            var row = AppServices.Db.GetPlugin(toolId!);
            PostCatalog(postToUi, row?.Group);

            postToUi(new
            {
                type = "job-finished",
                jobId,
                ok = result.Ok,
                exitCode = result.ExitCode,
                detail = result.Detail
            });
        }
        finally
        {
            lock (_running) { _running.Remove(jobId); }
        }
    }

    private void CancelJob(JsonElement root)
    {
        if (!root.TryGetProperty("jobId", out var idEl)) return;
        var jobId = idEl.GetString();
        if (jobId is null) return;
        lock (_running)
        {
            if (_running.TryGetValue(jobId, out var cts))
                cts.Cancel();
        }
    }
}
