using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Win32;
using Miao.Software.Jobs;

namespace Miao.App.Bridge;

/// <summary>
/// Vue ↔ C# IPC：软件目录、Volta、Claude、网站、工具集、设置、Job。
/// </summary>
public sealed class HostBridge
{
    private readonly JobRunner _jobs;
    private readonly Dictionary<string, CancellationTokenSource> _running = new();
    private Action<object>? _post;

    /// <summary>
    /// 创建消息桥。
    /// 可在完整 <see cref="AppServices"/> 初始化前创建（仅需 <see cref="JobRunner"/>）；
    /// 业务消息仍会通过属性访问触发幂等初始化。
    /// </summary>
    public HostBridge(JobRunner jobs, Dispatcher? _ = null)
    {
        _jobs = jobs;
        _jobs.Event += OnJobEvent;
        AppServices.Silent.TaskChanged += OnSilentTaskChanged;
        AppServices.Silent.QueueChanged += OnSilentQueueChanged;
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

    private void OnSilentTaskChanged(SilentTaskInfo task)
    {
        _post?.Invoke(new { type = "silent.task", task = ToSilentTaskDto(task) });
        // 安装态/更新/版本目录校准完成后推送目录，刷新列表角标与版本
        if (string.Equals(task.Status, "succeeded", StringComparison.OrdinalIgnoreCase)
            && (task.Id.StartsWith("detect.", StringComparison.OrdinalIgnoreCase)
                || task.Id.StartsWith("cache.versions.", StringComparison.OrdinalIgnoreCase)))
        {
            try
            {
                if (_post is { } post)
                {
                    PostCatalog(post, "dev");
                    PostCatalog(post, "daily");
                }
            }
            catch
            {
                /* 静默：推送失败不影响任务本身 */
            }
        }

        if (string.Equals(task.Status, "succeeded", StringComparison.OrdinalIgnoreCase)
            && string.Equals(task.Id, "cache.claude.plugins", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                if (_post is { } post)
                    PostClaudeStatus(post);
            }
            catch
            {
                /* ignore */
            }
        }
    }

    private void OnSilentQueueChanged(SilentQueueSnapshot queue)
    {
        _post?.Invoke(ToSilentQueueDto(queue));
    }

    private static object ToSilentTaskDto(SilentTaskInfo t) => new
    {
        id = t.Id,
        title = t.Title,
        status = t.Status,
        progress = t.Progress,
        detail = t.Detail,
        updatedAt = t.UpdatedAt,
    };

    private static object ToSilentQueueDto(SilentQueueSnapshot queue) => new
    {
        type = "silent.queue",
        activeCount = queue.ActiveCount,
        totalQueued = queue.TotalQueued,
        tasks = queue.Tasks.Select(ToSilentTaskDto).ToArray(),
    };

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

            case "silent.list":
            {
                postToUi(ToSilentQueueDto(AppServices.Silent.GetSnapshot()));
                break;
            }

            case "silent.cancel":
            {
                var sid = root.TryGetProperty("id", out var idEl) ? idEl.GetString() : null;
                if (string.IsNullOrWhiteSpace(sid))
                {
                    postToUi(new { type = "error", message = "silent.cancel 需要 id" });
                    break;
                }

                var ok = AppServices.Silent.Cancel(sid);
                postToUi(new { type = "silent.cancel.ok", id = sid, ok });
                break;
            }

            case "get-i18n":
            {
                var locale = AppServices.Db.GetSetting("locale", "zh");
                postToUi(new { type = "i18n", locale, map = AppServices.Db.GetI18nMap(locale) });
                break;
            }

            case "settings.get":
            {
                var appearanceJson = AppServices.Db.GetSetting("appearance_json", "");
                object? appearance = null;
                if (!string.IsNullOrWhiteSpace(appearanceJson))
                {
                    try { appearance = System.Text.Json.JsonSerializer.Deserialize<object>(appearanceJson); }
                    catch { appearance = null; }
                }
                postToUi(new
                {
                    type = "settings",
                    locale = AppServices.Db.GetSetting("locale", "zh"),
                    appearance,
                });
                break;
            }

            case "settings.set-locale":
            {
                var locale = root.TryGetProperty("locale", out var l) ? l.GetString() : null;
                if (locale is not "zh" and not "en")
                {
                    postToUi(new { type = "error", message = "locale 仅支持 zh / en" });
                    break;
                }

                AppServices.Db.SetSetting("locale", locale);
                postToUi(new
                {
                    type = "settings",
                    locale,
                    appearance = (object?)null,
                });
                postToUi(new { type = "i18n", locale, map = AppServices.Db.GetI18nMap(locale) });
                break;
            }

            case "settings.set-appearance":
            {
                if (!root.TryGetProperty("appearance", out var apEl))
                {
                    postToUi(new { type = "error", message = "缺少 appearance" });
                    break;
                }
                var appearanceJsonBody = apEl.GetRawText();
                if (appearanceJsonBody.Length > 64_000)
                {
                    postToUi(new { type = "error", message = "appearance 过大" });
                    break;
                }
                AppServices.Db.SetSetting("appearance_json", appearanceJsonBody);
                object? appearanceObj = null;
                try { appearanceObj = System.Text.Json.JsonSerializer.Deserialize<object>(appearanceJsonBody); }
                catch { appearanceObj = null; }
                postToUi(new
                {
                    type = "settings",
                    locale = AppServices.Db.GetSetting("locale", "zh"),
                    appearance = appearanceObj,
                });
                break;
            }

            case "get-groups":
                postToUi(new
                {
                    type = "groups",
                    groups = AppServices.Software.GetGroups(AppServices.Db.GetSetting("locale", "zh"))
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

            case "volta.list":
            case "node.list":
            {
                var tool = root.TryGetProperty("tool", out var tEl) ? tEl.GetString() : "node";
                if (string.IsNullOrWhiteSpace(tool)) tool = "node";
                var ltsOnly = root.TryGetProperty("ltsOnly", out var lo) && lo.ValueKind == JsonValueKind.True;
                // 默认强制远程增量同步；显式 forceRemote:false 则优先读缓存
                var forceRemote = !root.TryGetProperty("forceRemote", out var fr) || fr.ValueKind != JsonValueKind.False;
                try
                {
                    var items = await AppServices.Volta.ListAsync(tool!, ltsOnly, forceRemote).ConfigureAwait(false);
                    postToUi(new
                    {
                        type = "volta.versions",
                        tool,
                        ltsOnly,
                        items,
                        voltaAvailable = AppServices.Volta.IsVoltaAvailable(),
                        conflicts = AppServices.Volta.DetectConflicts(),
                    });
                }
                catch (Exception ex)
                {
                    postToUi(new { type = "error", message = $"拉取版本失败: {ex.Message}" });
                }

                break;
            }

            case "dialog.pick-folder":
            {
                string? path = null;
                await Application.Current.Dispatcher.InvokeAsync(() =>
                {
                    var dlg = new OpenFolderDialog
                    {
                        Title = "选择项目目录（含 package.json）",
                    };
                    if (dlg.ShowDialog() == true)
                        path = dlg.FolderName;
                });
                var hasPackageJson = !string.IsNullOrWhiteSpace(path) &&
                    File.Exists(Path.Combine(path, "package.json"));
                postToUi(new { type = "dialog.folder", path, hasPackageJson });
                break;
            }

            case "open-url":
            {
                var url = root.TryGetProperty("url", out var u) ? u.GetString() : null;
                if (string.IsNullOrWhiteSpace(url) ||
                    (!url.StartsWith("https://", StringComparison.OrdinalIgnoreCase) &&
                     !url.StartsWith("http://", StringComparison.OrdinalIgnoreCase)))
                {
                    postToUi(new { type = "error", message = "无效 URL" });
                    break;
                }

                try
                {
                    Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
                    postToUi(new { type = "open-url.ok", url });
                }
                catch (Exception ex)
                {
                    postToUi(new { type = "error", message = ex.Message });
                }

                break;
            }

            case "claude.status":
            {
                PostClaudeStatus(postToUi);
                // 已安装且已初始化、库空时补同步
                try
                {
                    if (!AppServices.Db.HasClaudePluginCache()
                        && AppServices.Claude.IsInitialized(AppServices.Db))
                        AppServices.EnqueueClaudePluginCache();
                }
                catch { /* ignore */ }
                break;
            }

            case "claude.set-api":
            {
                try
                {
                    var mode = root.TryGetProperty("mode", out var m) ? m.GetString() ?? "clear" : "clear";
                    var apiKey = root.TryGetProperty("apiKey", out var k) ? k.GetString() : null;
                    var baseUrl = root.TryGetProperty("baseUrl", out var b) ? b.GetString() : null;
                    var authToken = root.TryGetProperty("authToken", out var a) ? a.GetString() : null;
                    var path = AppServices.Claude.ApplyApi(mode, apiKey, baseUrl, authToken);
                    postToUi(new { type = "claude.saved", path, kind = "api" });
                    PostClaudeStatus(postToUi, liveStatus: true);
                }
                catch (Exception ex)
                {
                    postToUi(new { type = "error", message = ex.Message });
                }

                break;
            }

            case "claude.set-proxy":
            {
                try
                {
                    var mode = root.TryGetProperty("mode", out var m) ? m.GetString() ?? "clear" : "clear";
                    var httpProxy = root.TryGetProperty("httpProxy", out var h) ? h.GetString() : null;
                    var httpsProxy = root.TryGetProperty("httpsProxy", out var s) ? s.GetString() : null;
                    var path = AppServices.Claude.ApplyProxy(mode, httpProxy, httpsProxy);
                    postToUi(new { type = "claude.saved", path, kind = "proxy" });
                    PostClaudeStatus(postToUi, liveStatus: true);
                }
                catch (Exception ex)
                {
                    postToUi(new { type = "error", message = ex.Message });
                }

                break;
            }

            case "run-job":
                // 勿 await：Init 等同步 Handler 会堵死消息泵，导致 UI 无输出且无法 cancel-job
                _ = StartJobAsync(root, postToUi).ContinueWith(
                    t =>
                    {
                        if (t.IsFaulted)
                        {
                            var msg = t.Exception?.GetBaseException().Message ?? "任务失败";
                            postToUi(new { type = "error", message = msg });
                        }
                    },
                    TaskScheduler.Default);
                break;

            case "cancel-job":
                CancelJob(root);
                break;

            case "sites.list":
                PostSites(postToUi);
                break;

            case "sites.open":
            {
                var id = root.TryGetProperty("id", out var idEl) ? idEl.GetString() : null;
                var err = string.IsNullOrWhiteSpace(id) ? "缺少 id" : AppServices.Sites.OpenSite(id!);
                if (err is not null)
                    postToUi(new { type = "error", message = err });
                else
                    postToUi(new { type = "sites.opened", id });
                break;
            }

            case "sites.save-category":
            {
                var id = root.TryGetProperty("id", out var i) ? i.GetString() : null;
                var name = root.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                var sort = root.TryGetProperty("sort", out var s) && s.TryGetInt32(out var si) ? si : 100;
                var err = AppServices.Sites.SaveCategory(id, name, sort);
                if (err is not null) postToUi(new { type = "error", message = err });
                else PostSites(postToUi);
                break;
            }

            case "sites.save":
            {
                var id = root.TryGetProperty("id", out var i) ? i.GetString() : null;
                var categoryId = root.TryGetProperty("categoryId", out var c) ? c.GetString() ?? "" : "";
                var title = root.TryGetProperty("title", out var t) ? t.GetString() ?? "" : "";
                var url = root.TryGetProperty("url", out var u) ? u.GetString() ?? "" : "";
                var sort = root.TryGetProperty("sort", out var s) && s.TryGetInt32(out var si) ? si : 100;
                var note = root.TryGetProperty("note", out var no) ? no.GetString() : null;
                var err = AppServices.Sites.SaveSite(id, categoryId, title, url, sort, note);
                if (err is not null) postToUi(new { type = "error", message = err });
                else PostSites(postToUi);
                break;
            }

            case "sites.delete":
            {
                var id = root.TryGetProperty("id", out var i) ? i.GetString() : null;
                var err = string.IsNullOrWhiteSpace(id) ? "缺少 id" : AppServices.Sites.DeleteSite(id!);
                if (err is not null) postToUi(new { type = "error", message = err });
                else PostSites(postToUi);
                break;
            }

            case "sites.delete-category":
            {
                var id = root.TryGetProperty("id", out var i) ? i.GetString() : null;
                var err = string.IsNullOrWhiteSpace(id) ? "缺少 id" : AppServices.Sites.DeleteCategory(id!);
                if (err is not null) postToUi(new { type = "error", message = err });
                else PostSites(postToUi);
                break;
            }

            case "sites.export":
                postToUi(new { type = "sites.export", json = AppServices.Sites.ExportJson() });
                break;

            case "sites.import":
            {
                var payload = root.TryGetProperty("json", out var j) ? j.GetString() : null;
                var err = string.IsNullOrWhiteSpace(payload)
                    ? "缺少 json"
                    : AppServices.Sites.ImportJson(payload!);
                if (err is not null) postToUi(new { type = "error", message = err });
                else PostSites(postToUi);
                break;
            }

            case "utilities.list":
            {
                var locale = AppServices.Db.GetSetting("locale", "zh");
                postToUi(new { type = "utilities", data = AppServices.Utilities.GetPage(locale) });
                break;
            }

            case "utilities.guid":
            {
                var count = root.TryGetProperty("count", out var c) && c.TryGetInt32(out var ci) ? ci : 1;
                var uppercase = root.TryGetProperty("uppercase", out var u) && u.ValueKind == JsonValueKind.True;
                var braces = root.TryGetProperty("braces", out var b) && b.ValueKind == JsonValueKind.True;
                postToUi(new
                {
                    type = "utilities.guid",
                    data = AppServices.Utilities.GenerateGuids(count, uppercase, braces),
                });
                break;
            }

            default:
                postToUi(new { type = "error", message = $"未知消息类型: {type}" });
                break;
        }
    }

    private static void PostSites(Action<object> postToUi)
    {
        postToUi(new
        {
            type = "sites",
            categories = AppServices.Sites.ListCategories(),
            sites = AppServices.Sites.ListSites(),
        });
    }

    private static void PostClaudeStatus(Action<object> postToUi, bool liveStatus = false)
    {
        var lists = AppServices.Claude.GetPluginLists(AppServices.Db);
        postToUi(new
        {
            type = "claude.status",
            status = liveStatus
                ? AppServices.Claude.GetStatus()
                : AppServices.Claude.GetStatusCached(AppServices.Db),
            secrets = AppServices.Claude.GetSecretsPublic(),
            pluginsInstall = lists.Install,
            pluginsUpdate = lists.Update,
            pluginsUninstall = lists.Uninstall,
        });
    }

    private static void PostCatalog(Action<object> postToUi, string? group)
    {
        var locale = AppServices.Db.GetSetting("locale", "zh");
        var items = AppServices.Software.GetCatalog(locale, group);
        postToUi(new { type = "catalog", group, items });
    }

    private async Task StartJobAsync(JsonElement root, Action<object> postToUi)
    {
        var jobId = root.TryGetProperty("jobId", out var idEl)
            ? idEl.GetString() ?? Guid.NewGuid().ToString("N")
            : Guid.NewGuid().ToString("N");

        var toolId = root.TryGetProperty("toolId", out var t) ? t.GetString() : null;
        var action = root.TryGetProperty("action", out var a) ? a.GetString() : "install";
        var versions = ReadVersions(root);
        var options = ReadOptions(root);

        if (string.IsNullOrWhiteSpace(toolId))
        {
            postToUi(new { type = "error", message = "缺少 toolId" });
            return;
        }

        if (!AppServices.Software.Contains(toolId!))
        {
            postToUi(new { type = "job-event", jobId, kind = "error", message = $"未知软件: {toolId}" });
            return;
        }

        var cts = new CancellationTokenSource();
        lock (_running) { _running[jobId] = cts; }

        postToUi(new { type = "job-started", jobId, toolId, action, versions });

        try
        {
            var result = await AppServices.Software
                .ExecuteAsync(jobId, toolId!, action ?? "install", _jobs, versions, options, cts.Token)
                .ConfigureAwait(false);

            AppServices.Software.ProbeTool(toolId!);
            var row = AppServices.Db.GetSoftware(toolId!);
            PostCatalog(postToUi, row?.Group);

            // 初始化 / 插件装更卸后刷新三态插件列表
            if (string.Equals(toolId, "claude-code", StringComparison.OrdinalIgnoreCase)
                && IsClaudePluginDataAction(action))
            {
                PostClaudeStatus(postToUi);
            }

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

    private static bool IsClaudePluginDataAction(string? action) =>
        action is "init" or "reset" or "plugin-install" or "plugin-update" or "plugin-uninstall";

    private static List<string>? ReadVersions(JsonElement root)
    {
        var list = new List<string>();
        if (root.TryGetProperty("versions", out var arr) && arr.ValueKind == JsonValueKind.Array)
        {
            foreach (var el in arr.EnumerateArray())
            {
                var s = el.GetString();
                if (!string.IsNullOrWhiteSpace(s)) list.Add(s.Trim());
            }
        }
        else if (root.TryGetProperty("version", out var one))
        {
            var s = one.GetString();
            if (!string.IsNullOrWhiteSpace(s)) list.Add(s.Trim());
        }

        return list.Count > 0 ? list : null;
    }

    private static Dictionary<string, string>? ReadOptions(JsonElement root)
    {
        var dict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var key in new[] { "projectPath", "plugins" })
        {
            if (root.TryGetProperty(key, out var el) && el.ValueKind == JsonValueKind.String)
            {
                var s = el.GetString();
                if (!string.IsNullOrWhiteSpace(s)) dict[key] = s;
            }
        }

        if (root.TryGetProperty("options", out var opt) && opt.ValueKind == JsonValueKind.Object)
        {
            foreach (var p in opt.EnumerateObject())
            {
                if (p.Value.ValueKind == JsonValueKind.String)
                {
                    var s = p.Value.GetString();
                    if (!string.IsNullOrWhiteSpace(s)) dict[p.Name] = s!;
                }
            }
        }

        return dict.Count > 0 ? dict : null;
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
