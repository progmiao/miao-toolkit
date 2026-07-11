# node — ConPTY runner for volta install progress capture (Windows 10 1809+)

function Ensure-VoltaConPtyType {
    if ('MiaoVoltaConPtySession' -as [type]) { return $true }

    $typeDef = @'
using System;
using System.Collections.Concurrent;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

public sealed class MiaoVoltaConPtySession : IDisposable
{
    const int ProcThreadAttributePseudoConsole = 0x00020016;
    const uint ExtendedStartupInfoPresent = 0x00080000;

    [StructLayout(LayoutKind.Sequential)]
    struct Coord { public short X; public short Y; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct StartupInfo
    {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct StartupInfoEx
    {
        public StartupInfo StartupInfo;
        public IntPtr lpAttributeList;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct ProcessInformation
    {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CreatePipe(out IntPtr hReadPipe, out IntPtr hWritePipe, IntPtr lpPipeAttributes, uint nSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern int CreatePseudoConsole(Coord size, IntPtr hInput, IntPtr hOutput, uint dwFlags, out IntPtr phPC);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern void ClosePseudoConsole(IntPtr hPC);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool InitializeProcThreadAttributeList(IntPtr lpAttributeList, int dwAttributeCount, int dwFlags, ref IntPtr lpSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool UpdateProcThreadAttribute(
        IntPtr lpAttributeList,
        uint dwFlags,
        IntPtr Attribute,
        IntPtr lpValue,
        IntPtr cbSize,
        IntPtr lpPreviousValue,
        IntPtr lpReturnSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern void DeleteProcThreadAttributeList(IntPtr lpAttributeList);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(
        string lpApplicationName,
        string lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref StartupInfoEx lpStartupInfo,
        out ProcessInformation lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetExitCodeProcess(IntPtr hProcess, out uint lpExitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool TerminateProcess(IntPtr hProcess, uint uExitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool PeekNamedPipe(
        IntPtr hNamedPipe,
        IntPtr lpBuffer,
        uint nBufferSize,
        out uint lpBytesRead,
        out uint lpTotalBytesAvail,
        out uint lpBytesLeftThisMessage);

    readonly ConcurrentQueue<string> _queue = new ConcurrentQueue<string>();
    readonly StringBuilder _line = new StringBuilder();
    readonly Thread _readerThread;
    readonly FileStream _outputReadStream;
    readonly StreamWriter _inputWriteStream;
    readonly IntPtr _hProcess;
    readonly IntPtr _hThread;
    readonly IntPtr _hpc;
    readonly IntPtr _attributeList;
    readonly IntPtr _heldInputWrite;
    readonly IntPtr _heldOutputRead;
    volatile bool _done;
    int _exitCode = 1;
    bool _disposed;

    public ConcurrentQueue<string> Queue { get { return _queue; } }
    public bool HasExited { get { return _done; } }
    public int ExitCode { get { return _exitCode; } }

    public MiaoVoltaConPtySession(string fileName, string arguments)
    {
        IntPtr pipeInputRead = IntPtr.Zero;
        IntPtr pipeOutputWrite = IntPtr.Zero;

        if (!CreatePipe(out pipeInputRead, out _heldInputWrite, IntPtr.Zero, 0))
        {
            throw new InvalidOperationException("CreatePipe(input) failed: " + Marshal.GetLastWin32Error());
        }

        if (!CreatePipe(out _heldOutputRead, out pipeOutputWrite, IntPtr.Zero, 0))
        {
            CloseHandle(_heldInputWrite);
            throw new InvalidOperationException("CreatePipe(output) failed: " + Marshal.GetLastWin32Error());
        }

        var size = new Coord { X = 120, Y = 30 };
        if (CreatePseudoConsole(size, pipeInputRead, pipeOutputWrite, 0, out _hpc) != 0)
        {
            CloseHandle(_heldInputWrite);
            CloseHandle(_heldOutputRead);
            CloseHandle(pipeOutputWrite);
            CloseHandle(pipeInputRead);
            throw new InvalidOperationException("CreatePseudoConsole failed: " + Marshal.GetLastWin32Error());
        }

        CloseHandle(pipeInputRead);
        CloseHandle(pipeOutputWrite);

        IntPtr attributeSize = IntPtr.Zero;
        InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref attributeSize);
        _attributeList = Marshal.AllocHGlobal(attributeSize.ToInt32());
        if (!InitializeProcThreadAttributeList(_attributeList, 1, 0, ref attributeSize))
        {
            throw new InvalidOperationException("InitializeProcThreadAttributeList failed: " + Marshal.GetLastWin32Error());
        }

        if (!UpdateProcThreadAttribute(
            _attributeList,
            0,
            (IntPtr)ProcThreadAttributePseudoConsole,
            _hpc,
            (IntPtr)IntPtr.Size,
            IntPtr.Zero,
            IntPtr.Zero))
        {
            throw new InvalidOperationException("UpdateProcThreadAttribute failed: " + Marshal.GetLastWin32Error());
        }

        var startupInfo = new StartupInfoEx();
        startupInfo.StartupInfo.cb = Marshal.SizeOf(typeof(StartupInfoEx));
        startupInfo.lpAttributeList = _attributeList;

        ProcessInformation processInfo;
        var commandLine = "\"" + fileName + "\" " + (arguments ?? string.Empty);
        if (!CreateProcessW(
            null,
            commandLine,
            IntPtr.Zero,
            IntPtr.Zero,
            false,
            ExtendedStartupInfoPresent,
            IntPtr.Zero,
            null,
            ref startupInfo,
            out processInfo))
        {
            throw new InvalidOperationException("CreateProcess failed: " + Marshal.GetLastWin32Error());
        }

        _hProcess = processInfo.hProcess;
        _hThread = processInfo.hThread;

        _outputReadStream = new FileStream(new SafeFileHandle(_heldOutputRead, true), FileAccess.Read);
        _inputWriteStream = new StreamWriter(new FileStream(new SafeFileHandle(_heldInputWrite, true), FileAccess.Write))
        {
            AutoFlush = true
        };

        _readerThread = new Thread(ReadLoop) { IsBackground = true, Name = "MiaoVoltaConPtyReader" };
        _readerThread.Start();

        var waiter = new Thread(WaitLoop) { IsBackground = true, Name = "MiaoVoltaConPtyWaiter" };
        waiter.Start();
    }

    void EmitLine(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) { return; }
        _queue.Enqueue(text);
    }

    void FeedChar(char ch)
    {
        if (ch == '\r')
        {
            EmitLine(_line.ToString());
            _line.Clear();
            return;
        }

        if (ch == '\n')
        {
            EmitLine(_line.ToString());
            _line.Clear();
            return;
        }

        _line.Append(ch);
    }

    void ReadLoop()
    {
        var buffer = new byte[4096];
        try
        {
            while (!_done)
            {
                uint bytesRead;
                uint bytesAvailable;
                uint bytesLeft;
                var handle = _outputReadStream.SafeFileHandle.DangerousGetHandle();
                if (!PeekNamedPipe(handle, IntPtr.Zero, 0, out bytesRead, out bytesAvailable, out bytesLeft))
                {
                    break;
                }

                if (bytesAvailable == 0)
                {
                    Thread.Sleep(20);
                    continue;
                }

                var toRead = Math.Min(buffer.Length, (int)bytesAvailable);
                var count = _outputReadStream.Read(buffer, 0, toRead);
                if (count <= 0)
                {
                    Thread.Sleep(20);
                    continue;
                }

                var chunk = Encoding.UTF8.GetString(buffer, 0, count);
                foreach (var ch in chunk)
                {
                    FeedChar(ch);
                }
            }

            if (_line.Length > 0)
            {
                EmitLine(_line.ToString());
                _line.Clear();
            }
        }
        catch
        {
        }
    }

    void WaitLoop()
    {
        WaitForSingleObject(_hProcess, 0xFFFFFFFF);
        Thread.Sleep(300);
        _done = true;

        uint exitCode = 1;
        GetExitCodeProcess(_hProcess, out exitCode);
        _exitCode = (int)exitCode;

        try
        {
            _readerThread.Join(2000);
        }
        catch
        {
        }
    }

    public void Kill()
    {
        try
        {
            TerminateProcess(_hProcess, 1);
        }
        catch
        {
        }

        _done = true;
    }

    public void Dispose()
    {
        if (_disposed) { return; }
        _disposed = true;

        Kill();

        try { _inputWriteStream.Dispose(); } catch { }
        try { _outputReadStream.Dispose(); } catch { }

        if (_hThread != IntPtr.Zero) { CloseHandle(_hThread); }
        if (_hProcess != IntPtr.Zero) { CloseHandle(_hProcess); }

        if (_attributeList != IntPtr.Zero)
        {
            DeleteProcThreadAttributeList(_attributeList);
            Marshal.FreeHGlobal(_attributeList);
        }

        if (_hpc != IntPtr.Zero) { ClosePseudoConsole(_hpc); }
    }
}
'@

    try {
        Add-Type -TypeDefinition $typeDef -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Test-VoltaConPtyAvailable {
    return (Ensure-VoltaConPtyType)
}

function Start-NodeVoltaConPtyProcess {
    param(
        [string]$FileName,
        [string]$Arguments,
        [string]$CommandLine
    )

    if (-not (Test-VoltaConPtyAvailable)) {
        throw 'ConPTY is not available on this system'
    }

    $session = New-Object MiaoVoltaConPtySession -ArgumentList @($FileName, $Arguments)
    return @{
        Mode        = 'conpty'
        Session     = $session
        Queue       = $session.Queue
        CommandLine = $CommandLine
    }
}

function Test-NodeVoltaInstallProcessExited {
    param($State)

    if (-not $State) { return $true }
    if ($State.Mode -eq 'conpty') {
        return [bool]$State.Session.HasExited
    }

    if ($State.Process) {
        return [bool]$State.Process.HasExited
    }

    return $true
}

function Stop-NodeVoltaInstallProcessState {
    param($State)

    if (-not $State) { return 1 }

    if ($State.Mode -eq 'conpty') {
        try {
            if ($State.Session -and -not $State.Session.HasExited) {
                $State.Session.Kill()
            }
        }
        catch { }
        return (Complete-NodeVoltaInstallProcessState -State $State)
    }

    try {
        if ($State.Process -and -not $State.Process.HasExited) {
            $State.Process.Kill()
            $State.Process.WaitForExit(2000)
        }
    }
    catch { }
    return (Complete-NodeVoltaInstallProcessState -State $State)
}

function Complete-NodeVoltaInstallProcessState {
    param($State)

    if (-not $State) { return ,1 }

    if ($State.Mode -eq 'conpty') {
        $exitCode = 1
        if ($State.Session) {
            try { $exitCode = [int]$State.Session.ExitCode } catch { }
            try { $State.Session.Dispose() } catch { }
        }
        return ,$exitCode
    }

    foreach ($sub in @($State.Subscriptions)) {
        if ($sub) {
            $null = Unregister-Event -SourceIdentifier $sub.Name -ErrorAction SilentlyContinue
        }
    }

    $exitCode = 1
    if ($State.Process) {
        try {
            if (-not $State.Process.HasExited) {
                $State.Process.WaitForExit(2000)
            }
            $exitCode = [int]$State.Process.ExitCode
        }
        catch { }
    }
    return ,$exitCode
}

function Get-VoltaInstallStreamLinePercent {
    param([string]$Line)

    if (-not (Get-Command Get-WingetDepStreamLinePercent -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($Line)) { return -1 }
        if ($Line -match '(\d+)\s*%') {
            return [Math]::Max(0, [Math]::Min(100, [int]$Matches[1]))
        }
        return -1
    }

    return (Get-WingetDepStreamLinePercent -Line $Line)
}

function Get-VoltaInstallStreamLineCleanText {
    param([string]$Line)

    if (Get-Command Get-WingetStreamLineCleanText -ErrorAction SilentlyContinue) {
        return (Get-WingetStreamLineCleanText -Line $Line)
    }

    if ([string]::IsNullOrWhiteSpace($Line)) { return '' }
    $trim = [string]$Line.Trim()
    $trim = $trim -replace '\x1b\[[0-9;?]*[ -/]*[@-~]', ''
    $trim = $trim -replace '\x1b\].*?\x07', ''
    $trim = $trim -replace '^\r+|\r+$', ''
    return [string]$trim.Trim()
}

function Test-VoltaInstallStreamLineIsEphemeral {
    param([string]$Line)

    $trim = Get-VoltaInstallStreamLineCleanText -Line $Line
    if ([string]::IsNullOrWhiteSpace($trim)) { return $true }

    if (Get-Command Test-WingetStreamLineIsSpinnerOnly -ErrorAction SilentlyContinue) {
        if (Test-WingetStreamLineIsSpinnerOnly -Line $trim) { return $true }
    }
    elseif ($trim -match '^[\|\\/\-\s]+$') {
        return $true
    }

    if ((Get-VoltaInstallStreamLinePercent -Line $trim) -ge 0) { return $true }
    if ($trim -match '\[[=\->\s]+\]\s*\d+\s*%') { return $true }

    return $false
}

function Get-VoltaNodeInventoryZipPath {
    param([string]$Version)

    $dir = Join-Path $env:LOCALAPPDATA 'Volta\tools\inventory\node'
    return (Join-Path $dir "node-v$Version-win-x64.zip")
}

function Get-VoltaNodeDownloadUrl {
    param([string]$Version)

    return "https://nodejs.org/dist/v$Version/node-v$Version-win-x64.zip"
}

function Test-VoltaNodeInventoryZipReady {
    param([string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) { return $false }
    $zipPath = Get-VoltaNodeInventoryZipPath -Version $Version
    if (-not (Test-Path -LiteralPath $zipPath)) { return $false }

    try {
        $info = Get-Item -LiteralPath $zipPath
        return ([int64]$info.Length -gt 1000000)
    }
    catch {
        return $false
    }
}

function Invoke-VoltaNodeInventoryDownload {
    param(
        [string]$Version,
        $Ui,
        $Redraw,
        $Log = $null,
        $LoadingState = $null,
        [int]$MaxPercent = 65
    )

    if (Test-VoltaNodeInventoryZipReady -Version $Version) {
        return $true
    }

    if ($Ui) {
        $Ui.InstallPhase = 'downloading'
    }
    if ($LoadingState) {
        $LoadingState['InstallPhase'] = 'downloading'
    }

    $zipPath = Get-VoltaNodeInventoryZipPath -Version $Version
    $url = Get-VoltaNodeDownloadUrl -Version $Version
    $dir = Split-Path -Parent $zipPath
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }

    if ($Log -and (Get-Command Write-NodeBrowseInstallLogLine -ErrorAction SilentlyContinue)) {
        Write-NodeBrowseInstallLogLine -Log $Log -Text (Get-NodeBrowseI18n -Key 'node.browse.installLogDownloadStart' -Vars @{
            version = $Version
            url     = $url
        }) -Kind 'text' -WithTimestamp
    }

    $tempPath = "$zipPath.downloading"
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }

    $request = [System.Net.HttpWebRequest]::Create($url)
    $request.Method = 'GET'
    $request.Timeout = 600000
    $request.ReadWriteTimeout = 600000
    $response = $request.GetResponse()

    try {
        $total = [int64]$response.ContentLength
        $stream = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create($tempPath)
        try {
            $buffer = New-Object byte[] 65536
            $readTotal = [int64]0
            $lastPct = -1
            $lastSpinnerTick = [Environment]::TickCount
            while ($true) {
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }

                $fileStream.Write($buffer, 0, $read)
                $readTotal += $read

                $nowTick = [Environment]::TickCount
                if ($LoadingState -and ($nowTick - $lastSpinnerTick) -ge 80) {
                    if (Get-Command Update-NodeBrowseInstallLoadingStatus -ErrorAction SilentlyContinue) {
                        Update-NodeBrowseInstallLoadingStatus -Ui $Ui -LoadingState $LoadingState -Version $Version
                    }
                    Invoke-NodeVoltaInstallRedraw -Redraw $Redraw
                    $lastSpinnerTick = $nowTick
                }

                if ($total -gt 0) {
                    $pct = [int][Math]::Min($MaxPercent, [Math]::Max(1, [Math]::Round($MaxPercent * $readTotal / [double]$total)))
                    if ($pct -ne $lastPct) {
                        $lastPct = $pct
                        Set-NodeVoltaInstallProgressPercent -Ui $Ui -Percent $pct -Version $Version `
                            -Phase 'downloading' | Out-Null
                        Invoke-NodeVoltaInstallRedraw -Redraw $Redraw
                    }
                }
            }
        }
        finally {
            $fileStream.Dispose()
        }
    }
    finally {
        if ($stream) { $stream.Dispose() }
        $response.Dispose()
    }

    if (-not (Test-Path -LiteralPath $tempPath)) {
        throw "Download failed for node@$Version"
    }

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }
    Move-Item -LiteralPath $tempPath -Destination $zipPath -Force
    Set-NodeVoltaInstallProgressPercent -Ui $Ui -Percent $MaxPercent -Version $Version -Phase 'downloading' | Out-Null
    if ($LoadingState -and (Get-Command Update-NodeBrowseInstallLoadingStatus -ErrorAction SilentlyContinue)) {
        Update-NodeBrowseInstallLoadingStatus -Ui $Ui -LoadingState $LoadingState -Version $Version
    }
    Invoke-NodeVoltaInstallRedraw -Redraw $Redraw
    return $true
}

function Get-VoltaInstallOutputDecision {
    param(
        [string]$Line,
        [hashtable]$OutputState
    )

    $trim = Get-VoltaInstallStreamLineCleanText -Line $Line
    $decision = @{
        LogText    = $null
        StatusText = $trim
        Percent    = -1
        RedrawOnly = $false
    }

    if ([string]::IsNullOrWhiteSpace($trim)) {
        $decision.RedrawOnly = $true
        return $decision
    }

    if (Test-VoltaInstallStreamLineIsEphemeral -Line $trim) {
        $decision.RedrawOnly = $true
        $percent = Get-VoltaInstallStreamLinePercent -Line $trim
        $decision.Percent = $percent
        if ($percent -ge 0) {
            $decision.StatusText = $null
        }
        else {
            $decision.StatusText = $null
        }
        return $decision
    }

    $percent = Get-VoltaInstallStreamLinePercent -Line $trim
    $decision.Percent = $percent

    if ($trim -match '^\[verbose\]\s*(Downloading|Unpacking|Installing|Saving|Unlocking|Acquiring)\b') {
        $phaseName = [string]$Matches[1]
        if ($phaseName -match '^(Unpacking|Installing|Saving)$') {
            $OutputState.VoltaPhase = 'unpacking'
            if ([int]$OutputState.MinUnpackPercent -lt 66) {
                $OutputState.MinUnpackPercent = 66
            }
        }
        elseif ($phaseName -eq 'Downloading') {
            $OutputState.VoltaPhase = 'downloading'
        }

        $decision.LogText = ($trim -replace '^\[verbose\]\s*', '')
        $decision.RedrawOnly = $true
        $decision.StatusText = $null
        return $decision
    }

    if ($trim -match '^(?i:success:)') {
        if (-not $OutputState.LoggedSuccess) {
            $OutputState.LoggedSuccess = $true
            $decision.LogText = $trim
        }
        $decision.StatusText = $null
        return $decision
    }

    if ($trim -match '^(?i:(Fetching|Unpacking)\b)') {
        $decision.RedrawOnly = $true
        if ($percent -ge 0) {
            $decision.StatusText = $null
        }
        return $decision
    }

    if ($trim -match '^(?i:error:)') {
        $decision.LogText = $trim
        return $decision
    }

    $decision.LogText = $trim
    return $decision
}

function Invoke-NodeVoltaInstallRedraw {
    param($Redraw)

    if ($null -ne $Redraw -and $Redraw -is [scriptblock]) {
        & $Redraw
    }
}

function Get-VoltaInstallTmpBytes {
    $tmp = Join-Path $env:LOCALAPPDATA 'Volta\tmp'
    if (-not (Test-Path -LiteralPath $tmp)) { return [int64]0 }

    $sum = (Get-ChildItem -LiteralPath $tmp -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return [int64]0 }
    return [int64]$sum
}

function Test-VoltaInstallTmpHasNodeExe {
    $tmp = Join-Path $env:LOCALAPPDATA 'Volta\tmp'
    if (-not (Test-Path -LiteralPath $tmp)) { return $false }

    return [bool](Get-ChildItem -LiteralPath $tmp -Filter 'node.exe' -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First 1)
}

function Get-VoltaInstallDirectoryBytes {
    return (Get-VoltaInstallTmpBytes)
}

function Get-VoltaNodeZipContentLength {
    param([string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) { return [int64]0 }

    try {
        $url = "https://nodejs.org/dist/v$Version/node-v$Version-win-x64.zip"
        $resp = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 8
        $raw = $resp.Headers['Content-Length']
        if ($null -eq $raw) { return [int64]0 }
        if ($raw -is [array]) { $raw = $raw[0] }

        $len = [int64]0
        if ([int64]::TryParse([string]$raw, [ref]$len) -and $len -gt 0) {
            return $len
        }
    }
    catch { }

    return [int64]0
}

function New-VoltaNodeInstallProgressWatch {
    param(
        [string]$Version,
        [int]$StartTick = 0
    )

    $watch = @{
        Version             = [string]$Version
        TotalBytes          = [int64]0
        UnpackEstimateBytes = [int64]0
        BaselineBytes       = (Get-VoltaInstallTmpBytes)
        LastPercent         = -1
        Ready               = $false
        DownloadStartTick   = 0
        InstallStartTick    = $(if ($StartTick -gt 0) { $StartTick } else { [Environment]::TickCount })
        Phase               = 'starting'
        PreDownloadComplete = (Test-VoltaNodeInventoryZipReady -Version $Version)
    }

    if ([string]::IsNullOrWhiteSpace($Version)) { return $watch }

    $len = Get-VoltaNodeZipContentLength -Version $Version
    if ($len -gt 0) {
        $watch.TotalBytes = $len
        $watch.UnpackEstimateBytes = [Math]::Max([int64][Math]::Ceiling($len * 2.6), [int64]60000000)
        $watch.Ready = $true
    }

    return $watch
}

function Get-VoltaNodeInstallProgressWatchPercent {
    param(
        $Watch,
        [int]$NowTick = 0
    )

    if (-not $Watch) { return -1 }

    if ($NowTick -le 0) { $NowTick = [Environment]::TickCount }

    $tmpBytes = Get-VoltaInstallTmpBytes
    $delta = $tmpBytes - [int64]$Watch.BaselineBytes
    $elapsedMs = [Math]::Max(0, $NowTick - [int]$Watch.InstallStartTick)

    if (Test-VoltaInstallTmpHasNodeExe) {
        $Watch.Phase = 'unpacking'
        $estimate = [int64]$Watch.UnpackEstimateBytes
        if ($estimate -le 0) { $estimate = [int64]60000000 }
        $ratio = if ($delta -gt 0) { [Math]::Min(1.0, $delta / [double]$estimate) } else { 0.0 }
        $pct = 65 + [int][Math]::Round(34.0 * $ratio)
        return [Math]::Max(66, [Math]::Min(99, $pct))
    }

    if ($Watch.PreDownloadComplete) {
        $Watch.Phase = 'downloading'
        if ([int]$Watch.DownloadStartTick -le 0) {
            $Watch.DownloadStartTick = $NowTick
        }
        $downloadMs = [Math]::Max(0, $NowTick - [int]$Watch.DownloadStartTick)
        return [Math]::Max(66, [Math]::Min(85, 66 + [int][Math]::Floor($downloadMs / 2000.0)))
    }

    if ($delta -gt 50000) {
        $Watch.Phase = 'downloading'
        if ([int]$Watch.DownloadStartTick -le 0) {
            $Watch.DownloadStartTick = $NowTick
        }
        $downloadMs = [Math]::Max(0, $NowTick - [int]$Watch.DownloadStartTick)
        return [Math]::Max(2, [Math]::Min(64, 2 + [int][Math]::Floor($downloadMs / 1200.0)))
    }

    $Watch.Phase = 'starting'
    return [Math]::Min(2, [int][Math]::Floor($elapsedMs / 800.0))
}

function Set-NodeVoltaInstallProgressPercent {
    param(
        $Ui,
        [int]$Percent,
        [string]$Version = '',
        [string]$Phase = ''
    )

    if ($null -eq $Ui -or $Percent -lt 0) { return $false }
    if ([int]$Ui.ItemSubPercent -ge 0 -and $Percent -lt [int]$Ui.ItemSubPercent) { return $false }

    $Ui.ItemSubPercent = $Percent
    if (-not [string]::IsNullOrWhiteSpace($Phase)) {
        $Ui.InstallPhase = $Phase
    }
    return $true
}

function Update-NodeVoltaInstallProgressFromWatch {
    param(
        $Ui,
        $Watch,
        $Redraw,
        $OutputState = $null,
        $LoadingState = $null,
        [string]$Version = '',
        [int]$NowTick = 0
    )

    if ($null -eq $Ui -or $null -eq $Watch) { return $false }
    if ($NowTick -le 0) { $NowTick = [Environment]::TickCount }

    $percent = Get-VoltaNodeInstallProgressWatchPercent -Watch $Watch -NowTick $NowTick
    if ($percent -lt 0 -or $percent -eq [int]$Watch.LastPercent) { return $false }

    $Watch.LastPercent = $percent
    Set-NodeVoltaInstallProgressPercent -Ui $Ui -Percent $percent -Version $Version `
        -Phase ([string]$Watch.Phase) | Out-Null
    if ($LoadingState -and $Watch.Phase) {
        $LoadingState['InstallPhase'] = [string]$Watch.Phase
    }
    return $true
}

function Update-NodeVoltaInstallOutputLine {
    param(
        [string]$Line,
        $Ui,
        $LoadingState,
        [hashtable]$OutputState,
        $Log,
        $Redraw
    )

    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }

    $LoadingState['OutputSeen'] = $true
    $LoadingState['LastOutputTick'] = [Environment]::TickCount

    $decision = Get-VoltaInstallOutputDecision -Line $Line -OutputState $OutputState
    $shouldRedraw = $false

    if ($OutputState -and $OutputState.VoltaPhase) {
        $LoadingState['InstallPhase'] = [string]$OutputState.VoltaPhase
        if ($Ui) {
            $Ui.InstallPhase = [string]$OutputState.VoltaPhase
        }
    }

    if ($decision.Percent -ge 0) {
        $streamPct = [int]$decision.Percent
        $phase = if ($OutputState -and $OutputState.VoltaPhase) { [string]$OutputState.VoltaPhase } else { '' }
        if ($streamPct -gt [int]$Ui.ItemSubPercent) {
            Set-NodeVoltaInstallProgressPercent -Ui $Ui -Percent $streamPct -Phase $phase | Out-Null
            $shouldRedraw = $true
        }
    }

    if ($OutputState -and $OutputState.VoltaPhase -eq 'unpacking' -and [int]$OutputState.MinUnpackPercent -ge 66) {
        $minPct = [int]$OutputState.MinUnpackPercent
        if ($minPct -gt [int]$Ui.ItemSubPercent) {
            Set-NodeVoltaInstallProgressPercent -Ui $Ui -Percent $minPct -Phase 'unpacking' | Out-Null
            $shouldRedraw = $true
        }
    }

    if ($decision.LogText) {
        Write-NodeBrowseInstallLogLine -Log $Log -Text ([string]$decision.LogText) -WithTimestamp
        $shouldRedraw = $true
    }
    elseif ($decision.RedrawOnly) {
        $shouldRedraw = $true
    }

    if ($shouldRedraw) {
        Invoke-NodeVoltaInstallRedraw -Redraw $Redraw
    }

    return $shouldRedraw
}
