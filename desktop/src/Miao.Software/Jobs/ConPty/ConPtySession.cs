using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Miao.Software.Jobs.ConPty;

/// <summary>
/// 通过 Windows ConPTY 启动子进程，按块读取伪终端输出（含 ANSI）。
/// </summary>
internal sealed class ConPtySession : IDisposable
{
    private IntPtr _hPC;
    private readonly SafeFileHandle _inputWrite;
    private readonly SafeFileHandle _outputRead;
    private readonly ConPtyNative.ProcessInformation _processInfo;
    private readonly IntPtr _attributeList;
    private bool _disposed;

    private ConPtySession(
        IntPtr hPC,
        SafeFileHandle inputWrite,
        SafeFileHandle outputRead,
        ConPtyNative.ProcessInformation processInfo,
        IntPtr attributeList)
    {
        _hPC = hPC;
        _inputWrite = inputWrite;
        _outputRead = outputRead;
        _processInfo = processInfo;
        _attributeList = attributeList;
    }

    /// <summary>
    /// 在 ConPTY 中启动命令行；失败时抛出 <see cref="Win32Exception"/>。
    /// </summary>
    /// <param name="commandLine">完整命令行（可含参数与引号）。</param>
    /// <param name="cols">伪终端列数。</param>
    /// <param name="rows">伪终端行数。</param>
    public static ConPtySession Start(string commandLine, short cols = 120, short rows = 32)
    {
        if (!ConPtyNative.CreatePipe(out var inputRead, out var inputWrite, IntPtr.Zero, 0))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "CreatePipe(input) 失败");
        if (!ConPtyNative.CreatePipe(out var outputRead, out var outputWrite, IntPtr.Zero, 0))
        {
            inputRead.Dispose();
            inputWrite.Dispose();
            throw new Win32Exception(Marshal.GetLastWin32Error(), "CreatePipe(output) 失败");
        }

        var size = new ConPtyNative.Coord { X = cols, Y = rows };
        var hr = ConPtyNative.CreatePseudoConsole(size, inputRead, outputWrite, 0, out var hPC);
        // ConPTY 已复制句柄，关闭我们这边的端
        inputRead.Dispose();
        outputWrite.Dispose();

        if (hr != 0)
        {
            inputWrite.Dispose();
            outputRead.Dispose();
            throw new Win32Exception(hr, "CreatePseudoConsole 失败");
        }

        IntPtr attrList = IntPtr.Zero;
        try
        {
            attrList = CreateAttributeList(hPC);
            var startup = new ConPtyNative.StartupInfoEx();
            startup.StartupInfo.cb = Marshal.SizeOf<ConPtyNative.StartupInfoEx>();
            startup.StartupInfo.dwFlags = ConPtyNative.StartFUseStdHandles;
            startup.lpAttributeList = attrList;

            var pSec = new ConPtyNative.SecurityAttributes
            {
                nLength = Marshal.SizeOf<ConPtyNative.SecurityAttributes>(),
            };
            var tSec = pSec;

            // CreateProcessW 需要可写命令行缓冲区
            var cmd = new StringBuilder(commandLine);
            if (!ConPtyNative.CreateProcessW(
                    null,
                    cmd,
                    ref pSec,
                    ref tSec,
                    bInheritHandles: false,
                    dwCreationFlags: ConPtyNative.ExtendedStartupInfoPresent,
                    lpEnvironment: IntPtr.Zero,
                    lpCurrentDirectory: null,
                    lpStartupInfo: ref startup,
                    lpProcessInformation: out var pi))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateProcessW 失败");
            }

            return new ConPtySession(hPC, inputWrite, outputRead, pi, attrList);
        }
        catch
        {
            ConPtyNative.ClosePseudoConsole(hPC);
            inputWrite.Dispose();
            outputRead.Dispose();
            if (attrList != IntPtr.Zero)
            {
                ConPtyNative.DeleteProcThreadAttributeList(attrList);
                Marshal.FreeHGlobal(attrList);
            }
            throw;
        }
    }

    /// <summary>
    /// 读取伪终端输出直到关闭，并对每个 UTF-8 文本块回调。
    /// </summary>
    public async Task PumpOutputAsync(Action<string> onChunk, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(_outputRead, FileAccess.Read, 4096, false);
        var buffer = new byte[4096];
        var decoder = Encoding.UTF8.GetDecoder();
        var chars = new char[4096];

        while (!cancellationToken.IsCancellationRequested)
        {
            int read;
            try
            {
                read = await stream.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (ObjectDisposedException)
            {
                break;
            }
            catch (IOException)
            {
                break;
            }

            if (read <= 0) break;

            var n = decoder.GetChars(buffer, 0, read, chars, 0, flush: false);
            if (n > 0) onChunk(new string(chars, 0, n));
        }
    }

    /// <summary>等待进程结束并返回退出码。</summary>
    public async Task<int> WaitForExitAsync(CancellationToken cancellationToken)
    {
        // 轮询可取消；ConPTY 场景下进程句柄等待足够
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var wait = ConPtyNative.WaitForSingleObject(_processInfo.hProcess, 200);
            if (wait == 0) // WAIT_OBJECT_0
            {
                ConPtyNative.GetExitCodeProcess(_processInfo.hProcess, out var code);
                return unchecked((int)code);
            }

            await Task.Delay(50, cancellationToken).ConfigureAwait(false);
        }
    }

    /// <summary>强制结束子进程。</summary>
    public void Kill()
    {
        try
        {
            if (_processInfo.hProcess != IntPtr.Zero)
                ConPtyNative.TerminateProcess(_processInfo.hProcess, 1);
        }
        catch
        {
            /* ignore */
        }
    }

    /// <summary>
    /// 关闭伪终端（使输出读取收到 EOF），不释放进程句柄。
    /// </summary>
    public void ClosePty()
    {
        if (_hPC == IntPtr.Zero) return;
        try { ConPtyNative.ClosePseudoConsole(_hPC); } catch { /* ignore */ }
        _hPC = IntPtr.Zero;
    }

    /// <summary>调整伪终端尺寸（字符行列）。</summary>
    public void Resize(short cols, short rows)
    {
        if (_hPC == IntPtr.Zero) return;
        ConPtyNative.ResizePseudoConsole(_hPC, new ConPtyNative.Coord { X = cols, Y = rows });
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        ClosePty();

        try { _inputWrite.Dispose(); } catch { /* ignore */ }
        try { _outputRead.Dispose(); } catch { /* ignore */ }

        if (_attributeList != IntPtr.Zero)
        {
            try { ConPtyNative.DeleteProcThreadAttributeList(_attributeList); } catch { /* ignore */ }
            try { Marshal.FreeHGlobal(_attributeList); } catch { /* ignore */ }
        }

        if (_processInfo.hThread != IntPtr.Zero)
            ConPtyNative.CloseHandle(_processInfo.hThread);
        if (_processInfo.hProcess != IntPtr.Zero)
            ConPtyNative.CloseHandle(_processInfo.hProcess);
    }

    private static IntPtr CreateAttributeList(IntPtr hPC)
    {
        var size = IntPtr.Zero;
        ConPtyNative.InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
        if (size == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "无法计算属性列表大小");

        var list = Marshal.AllocHGlobal(size);
        if (!ConPtyNative.InitializeProcThreadAttributeList(list, 1, 0, ref size))
        {
            Marshal.FreeHGlobal(list);
            throw new Win32Exception(Marshal.GetLastWin32Error(), "InitializeProcThreadAttributeList 失败");
        }

        // lpValue：与微软 GUIConsole 示例一致，传入 HPCON 句柄值
        if (!ConPtyNative.UpdateProcThreadAttribute(
                list,
                0,
                (IntPtr)ConPtyNative.ProcThreadAttributePseudoConsole,
                hPC,
                (IntPtr)IntPtr.Size,
                IntPtr.Zero,
                IntPtr.Zero))
        {
            ConPtyNative.DeleteProcThreadAttributeList(list);
            Marshal.FreeHGlobal(list);
            throw new Win32Exception(Marshal.GetLastWin32Error(), "UpdateProcThreadAttribute 失败");
        }

        return list;
    }
}
