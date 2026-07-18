$ErrorActionPreference = 'Stop'
$null = Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

public sealed class VoltaConPtyProbe : IDisposable
{
    const int ProcThreadAttributePseudoConsole = 0x00020016;
    const uint ExtendedStartupInfoPresent = 0x00080000;

    [StructLayout(LayoutKind.Sequential)] struct Coord { public short X; public short Y; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct StartupInfo { public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct StartupInfoEx { public StartupInfo StartupInfo; public IntPtr lpAttributeList; }

    [StructLayout(LayoutKind.Sequential)]
    struct ProcessInformation { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CreatePipe(out IntPtr r, out IntPtr w, IntPtr a, uint s);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] static extern int CreatePseudoConsole(Coord size, IntPtr input, IntPtr output, uint flags, out IntPtr hpc);
    [DllImport("kernel32.dll", SetLastError=true)] static extern void ClosePseudoConsole(IntPtr hpc);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr l, int c, int f, ref IntPtr s);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr l, uint f, IntPtr a, IntPtr v, IntPtr cb, IntPtr p, IntPtr r);
    [DllImport("kernel32.dll", SetLastError=true)] static extern void DeleteProcThreadAttributeList(IntPtr l);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool CreateProcessW(string a, string c, IntPtr pa, IntPtr ta, bool ih, uint f, IntPtr e, string d, ref StartupInfoEx si, out ProcessInformation pi);
    [DllImport("kernel32.dll", SetLastError=true)] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr h, out uint c);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool PeekNamedPipe(IntPtr h, IntPtr b, uint n, out uint br, out uint ba, out uint bl);

    readonly IntPtr _hProcess, _hThread, _hpc, _attr, _inWrite, _outRead;
    readonly FileStream _out;
    volatile bool _done;
    public int RawBytes;
    public int ExitCode = 1;
    public string LastChunk = "";

    public VoltaConPtyProbe(string exe, string args)
    {
        IntPtr inRead, outWrite;
        CreatePipe(out inRead, out _inWrite, IntPtr.Zero, 0);
        CreatePipe(out _outRead, out outWrite, IntPtr.Zero, 0);
        CreatePseudoConsole(new Coord { X=120, Y=30 }, inRead, outWrite, 0, out _hpc);
        CloseHandle(inRead); CloseHandle(outWrite);
        IntPtr sz = IntPtr.Zero;
        InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref sz);
        _attr = Marshal.AllocHGlobal(sz.ToInt32());
        InitializeProcThreadAttributeList(_attr, 1, 0, ref sz);
        UpdateProcThreadAttribute(_attr, 0, (IntPtr)ProcThreadAttributePseudoConsole, _hpc, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero);
        var si = new StartupInfoEx(); si.StartupInfo.cb = Marshal.SizeOf(typeof(StartupInfoEx)); si.lpAttributeList = _attr;
        ProcessInformation pi;
        CreateProcessW(null, "\"" + exe + "\" " + args, IntPtr.Zero, IntPtr.Zero, false, ExtendedStartupInfoPresent, IntPtr.Zero, null, ref si, out pi);
        _hProcess = pi.hProcess; _hThread = pi.hThread;
        _out = new FileStream(new SafeFileHandle(_outRead, true), FileAccess.Read);
        new Thread(ReadLoop) { IsBackground = true }.Start();
        new Thread(WaitLoop) { IsBackground = true }.Start();
    }

    void ReadLoop()
    {
        var buf = new byte[8192];
        var sb = new StringBuilder();
        while (!_done)
        {
            uint br, ba, bl;
            var h = _out.SafeFileHandle.DangerousGetHandle();
            if (!PeekNamedPipe(h, IntPtr.Zero, 0, out br, out ba, out bl)) break;
            if (ba == 0) { Thread.Sleep(20); continue; }
            int n = _out.Read(buf, 0, (int)Math.Min(buf.Length, ba));
            if (n <= 0) { Thread.Sleep(20); continue; }
            RawBytes += n;
            sb.Append(Encoding.UTF8.GetString(buf, 0, n));
            if (sb.Length > 400) LastChunk = sb.ToString(sb.Length - 400, 400); else LastChunk = sb.ToString();
        }
    }

    void WaitLoop()
    {
        WaitForSingleObject(_hProcess, 0xFFFFFFFF);
        Thread.Sleep(500);
        _done = true;
        uint c = 1; GetExitCodeProcess(_hProcess, out c); ExitCode = (int)c;
    }

    public bool HasExited { get { return _done; } }

    public void Dispose()
    {
        _done = true;
        try { _out.Dispose(); } catch {}
        if (_hThread != IntPtr.Zero) CloseHandle(_hThread);
        if (_hProcess != IntPtr.Zero) CloseHandle(_hProcess);
        if (_attr != IntPtr.Zero) { DeleteProcThreadAttributeList(_attr); Marshal.FreeHGlobal(_attr); }
        if (_hpc != IntPtr.Zero) ClosePseudoConsole(_hpc);
        if (_inWrite != IntPtr.Zero) CloseHandle(_inWrite);
        if (_outRead != IntPtr.Zero) CloseHandle(_outRead);
    }
}
'@

$ver = if ($args.Count -gt 0) { [string]$args[0] } else { '14.20.0' }
$volta = (Get-Command volta -ErrorAction Stop).Source
$probe = New-Object VoltaConPtyProbe -ArgumentList @($volta, "install node@$ver")
$deadline = [Environment]::TickCount + 180000
while (-not $probe.HasExited -and [Environment]::TickCount -lt $deadline) {
    Start-Sleep -Milliseconds 200
    Write-Host "rawBytes=$($probe.RawBytes)"
}
Write-Host "final rawBytes=$($probe.RawBytes) exit=$($probe.ExitCode)"
if ($probe.RawBytes -gt 0) {
    Write-Host '--- tail ---'
    Write-Host $probe.LastChunk
}
$probe.Dispose()
