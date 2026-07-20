using System.Text;
using Miao.Common.Jobs;
using Miao.Software.Detect;

namespace Miao.Software.Install;

/// <summary>
/// 通用：下载安装包并拉起（微信/向日葵类）。安装程序 UI 由厂商接管。
/// 本文件位于 Install/：日常工具与开发工具列表项共用，不属于某一 Dev 工具。
/// </summary>
public sealed class InstallerLaunchHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "generic.installer-launch";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var install = context.Manifest.Install;
        if (install is null || string.IsNullOrWhiteSpace(install.DownloadUrl))
        {
            return new JobResult(context.JobId, false, 1, "软件定义缺少 install.downloadUrl");
        }

        var fileName = string.IsNullOrWhiteSpace(install.InstallerFileName)
            ? Path.GetFileName(new Uri(install.DownloadUrl).LocalPath)
            : install.InstallerFileName!;
        if (string.IsNullOrWhiteSpace(fileName))
            fileName = $"{context.ToolId}-setup.exe";

        var sb = new StringBuilder();
        sb.AppendLine("$ErrorActionPreference = 'Stop'");
        sb.AppendLine("Write-Host '##progress 5'");
        sb.AppendLine($"$url = '{Escape(install.DownloadUrl)}'");
        sb.AppendLine($"$out = Join-Path $env:TEMP '{Escape(fileName)}'");
        sb.AppendLine("Write-Host \"下载: $url\"");
        sb.AppendLine("Write-Host '##progress 20'");
        sb.AppendLine("Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing");
        sb.AppendLine("Write-Host '##progress 70'");
        sb.AppendLine("Write-Host \"拉起安装程序: $out\"");
        sb.AppendLine("Start-Process -FilePath $out -Wait:$false");
        sb.AppendLine("Write-Host '##progress 100'");
        sb.AppendLine("Write-Host '已拉起安装程序；请在厂商安装向导中完成。完成后可在本页刷新状态。'");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);

        InstallDetector.ProbeAndStore(context.Db, context.ToolId, install.Detect);
        return result;
    }

    private static string Escape(string s) => s.Replace("'", "''");
}

/// <summary>
/// 通用：WinGet 安装或已存在时升级（CC Switch / CC Connect 等）。
/// </summary>
public sealed class WingetInstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "generic.winget";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var install = context.Manifest.Install;
        if (install is null || string.IsNullOrWhiteSpace(install.PackageId))
            return new JobResult(context.JobId, false, 1, "软件定义缺少 install.packageId");

        var source = string.IsNullOrWhiteSpace(install.WingetSource)
            ? ""
            : $" --source {Escape(install.WingetSource!)}";
        var id = Escape(install.PackageId!);

        var sb = new StringBuilder();
        sb.AppendLine("$ErrorActionPreference = 'Stop'");
        sb.AppendLine("Write-Host '##progress 8'");
        sb.AppendLine($"$id = '{id}'");
        sb.AppendLine($"$src = '{source.Trim()}'");
        sb.AppendLine(@"
$listed = winget list --id $id -e 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $listed -match [regex]::Escape($id)) {
  Write-Host '##progress 35'
  Write-Host ""已安装，尝试 upgrade $id""
  Invoke-Expression ""winget upgrade --id $id -e --accept-package-agreements --accept-source-agreements $src""
  if ($LASTEXITCODE -ne 0) { Write-Host '无可用升级或已是最新' }
} else {
  Write-Host '##progress 35'
  Write-Host ""winget install $id""
  Invoke-Expression ""winget install --id $id -e --accept-package-agreements --accept-source-agreements $src""
  if ($LASTEXITCODE -ne 0) { throw ""winget install 失败 exit=$LASTEXITCODE"" }
}
Write-Host '##progress 100'
Write-Host '完成'
");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);

        InstallDetector.ProbeAndStore(context.Db, context.ToolId, install.Detect);
        return result;
    }

    private static string Escape(string s) => s.Replace("'", "''");
}

/// <summary>通用：WinGet 卸载（按 packageId）。</summary>
public sealed class WingetUninstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "generic.winget-uninstall";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var install = context.Manifest.Install;
        if (install is null || string.IsNullOrWhiteSpace(install.PackageId))
            return new JobResult(context.JobId, false, 1, "软件定义缺少 install.packageId");

        var source = string.IsNullOrWhiteSpace(install.WingetSource)
            ? ""
            : $" --source {Escape(install.WingetSource!)}";
        var id = Escape(install.PackageId!);

        var sb = new StringBuilder();
        sb.AppendLine("$ErrorActionPreference = 'Stop'");
        sb.AppendLine("Write-Host '##progress 20'");
        sb.AppendLine($"Write-Host 'winget uninstall --id {id} -e{source}'");
        sb.AppendLine($"winget uninstall --id {id} -e --accept-source-agreements{source}");
        sb.AppendLine("if ($LASTEXITCODE -ne 0) { throw \"winget uninstall 失败 exit=$LASTEXITCODE\" }");
        sb.AppendLine("Write-Host '##progress 100'");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);

        InstallDetector.ProbeAndStore(context.Db, context.ToolId, install.Detect);
        return result;
    }

    private static string Escape(string s) => s.Replace("'", "''");
}

/// <summary>
/// 通用：通过 npm 全局安装 CLI 包（CC Connect 等）。
/// </summary>
public sealed class NpmGlobalInstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "generic.npm-global";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var install = context.Manifest.Install;
        var pkg = install?.NpmPackage;
        if (string.IsNullOrWhiteSpace(pkg))
            return new JobResult(context.JobId, false, 1, "软件定义缺少 install.npmPackage");

        var sb = new StringBuilder();
        sb.AppendLine("$ErrorActionPreference = 'Stop'");
        sb.AppendLine("$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')");
        sb.AppendLine("Write-Host '##progress 15'");
        sb.AppendLine("if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { throw '未找到 npm，请先安装 Node.js' }");
        sb.AppendLine($"Write-Host 'npm install -g {Escape(pkg)}'");
        sb.AppendLine($"npm install -g {Escape(pkg)}");
        sb.AppendLine("if ($LASTEXITCODE -ne 0) { throw \"npm 失败 exit=$LASTEXITCODE\" }");
        sb.AppendLine("Write-Host '##progress 100'");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);

        InstallDetector.ProbeAndStore(context.Db, context.ToolId, install?.Detect);
        return result;
    }

    private static string Escape(string s) => s.Replace("'", "''");
}

/// <summary>
/// 通用：按卸载项 DisplayName 匹配后执行 QuietUninstallString / UninstallString。
/// </summary>
public sealed class RegistryUninstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "generic.uninstall";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var names = context.Manifest.Install?.Detect?.RegistryUninstallNames ?? new List<string>();
        if (names.Count == 0)
            return new JobResult(context.JobId, false, 1, "未配置 registryUninstallNames，无法通用卸载");

        var nameList = string.Join(",", names.Select(n => "'" + n.Replace("'", "''") + "'"));
        var sb = new StringBuilder();
        sb.AppendLine("$ErrorActionPreference = 'Stop'");
        sb.AppendLine($"$needles = @({nameList})");
        sb.AppendLine(@"
$roots = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
  'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
)
$cmd = $null
foreach ($root in $roots) {
  if (-not (Test-Path $root)) { continue }
  Get-ChildItem $root | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
    if (-not $p.DisplayName) { return }
    foreach ($n in $needles) {
      if ($p.DisplayName -like ('*' + $n + '*')) {
        $cmd = if ($p.QuietUninstallString) { $p.QuietUninstallString } else { $p.UninstallString }
      }
    }
  }
}
if (-not $cmd) { throw '未找到卸载命令' }
Write-Host ""卸载: $cmd""
Write-Host '##progress 40'
cmd /c $cmd
Write-Host '##progress 100'
");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);

        InstallDetector.ProbeAndStore(context.Db, context.ToolId, context.Manifest.Install?.Detect);
        return result;
    }
}
