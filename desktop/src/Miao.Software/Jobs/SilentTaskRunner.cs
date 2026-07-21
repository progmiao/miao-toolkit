namespace Miao.Software.Jobs;

/// <summary>
/// 进主壳后的静默任务队列：低并发、可取消、进度回传。
/// </summary>
public sealed class SilentTaskRunner
{
    private readonly object _gate = new();
    private readonly Dictionary<string, Entry> _entries = new(StringComparer.OrdinalIgnoreCase);
    private readonly Queue<string> _pending = new();
    private int _running;
    private readonly int _maxConcurrency;

    /// <summary>单条任务变化。</summary>
    public event Action<SilentTaskInfo>? TaskChanged;

    /// <summary>队列整体变化（角标等）。</summary>
    public event Action<SilentQueueSnapshot>? QueueChanged;

    /// <summary>创建。</summary>
    /// <param name="maxConcurrency">同时执行上限。</param>
    public SilentTaskRunner(int maxConcurrency = 1)
    {
        _maxConcurrency = Math.Max(1, maxConcurrency);
    }

    /// <summary>
    /// 入队。同 id 已在 pending/running 则跳过；已结束可再次入队。
    /// </summary>
    public bool Enqueue(
        string id,
        string title,
        Func<IProgress<int>, CancellationToken, Task> work)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ArgumentNullException.ThrowIfNull(work);

        lock (_gate)
        {
            if (_entries.TryGetValue(id, out var existing) &&
                existing.Status is SilentTaskStatus.Pending or SilentTaskStatus.Running)
            {
                return false;
            }

            var cts = new CancellationTokenSource();
            var entry = new Entry(id, title, work, cts)
            {
                Status = SilentTaskStatus.Pending,
                Progress = 0,
                Detail = "排队中",
            };
            _entries[id] = entry;
            _pending.Enqueue(id);
        }

        EmitQueue();
        Pump();
        return true;
    }

    /// <summary>取消指定任务（pending 直接取消；running 请求取消）。</summary>
    public bool Cancel(string id)
    {
        Entry? entry;
        lock (_gate)
        {
            if (!_entries.TryGetValue(id, out entry)) return false;
            if (entry.Status is SilentTaskStatus.Succeeded or SilentTaskStatus.Failed or SilentTaskStatus.Cancelled)
                return false;
            entry.Cts.Cancel();
            if (entry.Status == SilentTaskStatus.Pending)
            {
                entry.Status = SilentTaskStatus.Cancelled;
                entry.Detail = "已取消";
                entry.Progress = 0;
            }
        }

        EmitTask(entry!);
        EmitQueue();
        Pump();
        return true;
    }

    /// <summary>当前队列快照（进行中优先，含最近结束的少量项）。</summary>
    public SilentQueueSnapshot GetSnapshot()
    {
        lock (_gate)
        {
            return BuildSnapshotUnlocked();
        }
    }

    private void Pump()
    {
        while (true)
        {
            Entry? next = null;
            lock (_gate)
            {
                if (_running >= _maxConcurrency) return;
                while (_pending.Count > 0)
                {
                    var id = _pending.Dequeue();
                    if (!_entries.TryGetValue(id, out var e)) continue;
                    if (e.Status != SilentTaskStatus.Pending) continue;
                    e.Status = SilentTaskStatus.Running;
                    e.Detail = "执行中";
                    e.Progress = Math.Max(e.Progress, 1);
                    _running++;
                    next = e;
                    break;
                }
            }

            if (next is null) return;

            EmitTask(next);
            EmitQueue();
            _ = RunEntryAsync(next);
        }
    }

    private async Task RunEntryAsync(Entry entry)
    {
        var progress = new Progress<int>(p =>
        {
            var clamped = Math.Clamp(p, 0, 100);
            lock (_gate)
            {
                if (entry.Status != SilentTaskStatus.Running) return;
                entry.Progress = clamped;
            }

            EmitTask(entry);
        });

        try
        {
            await entry.Work(progress, entry.Cts.Token).ConfigureAwait(false);
            lock (_gate)
            {
                if (entry.Cts.IsCancellationRequested)
                {
                    entry.Status = SilentTaskStatus.Cancelled;
                    entry.Detail = "已取消";
                }
                else
                {
                    entry.Status = SilentTaskStatus.Succeeded;
                    entry.Progress = 100;
                    entry.Detail = "完成";
                }
            }
        }
        catch (OperationCanceledException)
        {
            lock (_gate)
            {
                entry.Status = SilentTaskStatus.Cancelled;
                entry.Detail = "已取消";
            }
        }
        catch (Exception ex)
        {
            lock (_gate)
            {
                entry.Status = SilentTaskStatus.Failed;
                entry.Detail = ex.Message;
            }
        }
        finally
        {
            lock (_gate)
            {
                _running = Math.Max(0, _running - 1);
            }

            EmitTask(entry);
            EmitQueue();
            Pump();
        }
    }

    private SilentQueueSnapshot BuildSnapshotUnlocked()
    {
        var active = _entries.Values
            .Where(e => e.Status is SilentTaskStatus.Pending or SilentTaskStatus.Running)
            .OrderBy(e => e.Status == SilentTaskStatus.Running ? 0 : 1)
            .ThenBy(e => e.CreatedAt)
            .Select(ToInfo)
            .ToList();

        var recent = _entries.Values
            .Where(e => e.Status is SilentTaskStatus.Succeeded or SilentTaskStatus.Failed or SilentTaskStatus.Cancelled)
            .OrderByDescending(e => e.UpdatedAt)
            .Take(8)
            .Select(ToInfo)
            .ToList();

        var tasks = active.Concat(recent).ToList();
        var activeCount = active.Count;
        return new SilentQueueSnapshot(activeCount, activeCount, tasks);
    }

    private static SilentTaskInfo ToInfo(Entry e) =>
        new(
            e.Id,
            e.Title,
            e.Status.ToString().ToLowerInvariant(),
            e.Progress,
            e.Detail,
            e.UpdatedAt.ToString("O"));

    private void EmitTask(Entry entry)
    {
        entry.Touch();
        TaskChanged?.Invoke(ToInfo(entry));
    }

    private void EmitQueue()
    {
        SilentQueueSnapshot snap;
        lock (_gate)
        {
            snap = BuildSnapshotUnlocked();
        }

        QueueChanged?.Invoke(snap);
    }

    private sealed class Entry
    {
        public Entry(
            string id,
            string title,
            Func<IProgress<int>, CancellationToken, Task> work,
            CancellationTokenSource cts)
        {
            Id = id;
            Title = title;
            Work = work;
            Cts = cts;
            CreatedAt = DateTimeOffset.Now;
            UpdatedAt = CreatedAt;
        }

        public string Id { get; }
        public string Title { get; }
        public Func<IProgress<int>, CancellationToken, Task> Work { get; }
        public CancellationTokenSource Cts { get; }
        public SilentTaskStatus Status { get; set; }
        public int Progress { get; set; }
        public string? Detail { get; set; }
        public DateTimeOffset CreatedAt { get; }
        public DateTimeOffset UpdatedAt { get; private set; }

        public void Touch() => UpdatedAt = DateTimeOffset.Now;
    }
}
