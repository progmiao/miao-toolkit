using System.Text;
using Miao.Common.Jobs;
using Miao.Software.Detect;

namespace Miao.Software.Dev.CcSwitch;

/// <summary>
/// CC Switch：从 GitHub Releases 下载官方 Windows MSI 并安装（对齐用户手册）。
/// 安装闸门：本机需已安装 Node.js 18+。
/// </summary>
public sealed class CcSwitchInstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "cc-switch.install";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var install = context.Manifest.Install;
        var owner = install?.GithubOwner ?? "farion1231";
        var repo = install?.GithubRepo ?? "cc-switch";

        var sb = new StringBuilder();
        sb.AppendLine("$ErrorActionPreference = 'Stop'");
        sb.AppendLine("$ProgressPreference = 'SilentlyContinue'");
        sb.AppendLine("$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')");
        sb.AppendLine("Write-Host '##progress 5'");
        sb.AppendLine(@"
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw '未找到 Node.js。CC Switch 需要 Node.js 18+，请先安装 Node.js 后再安装 CC Switch。'
}
$nodeVerRaw = (node -v 2>$null)
if (-not $nodeVerRaw) { throw '无法读取 node 版本' }
$nodeVer = ($nodeVerRaw -replace '^v','').Trim()
$major = [int]($nodeVer.Split('.')[0])
if ($major -lt 18) {
  throw ""需要 Node.js 18+，当前为 $nodeVerRaw""
}
Write-Host ""前置检查通过：Node.js $nodeVerRaw""
");
        sb.AppendLine($"$owner = '{Escape(owner)}'; $repo = '{Escape(repo)}'");
        sb.AppendLine(@"
Write-Host '##progress 15'
$api = ""https://api.github.com/repos/$owner/$repo/releases/latest""
Write-Host ""查询 Release: $api""
$headers = @{ 'User-Agent' = 'miao-toolkit'; 'Accept' = 'application/vnd.github+json' }
$rel = Invoke-RestMethod -Uri $api -Headers $headers -TimeoutSec 60
$tag = [string]$rel.tag_name
$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
if ($arch -eq 'Arm64') {
  $msiLike = 'CC-Switch-*-Windows-arm64.msi'
} else {
  $msiLike = 'CC-Switch-*-Windows.msi'
}
$item = @($rel.assets) | Where-Object {
  $_.name -like $msiLike -and $_.name -notlike '*.sig' -and $_.name -notlike '*Portable*'
} | Select-Object -First 1
if (-not $item) { throw ""Release $tag 中未找到匹配 $msiLike 的安装包"" }
$url = [string]$item.browser_download_url
$name = [string]$item.name
Write-Host ""远程 tag=$tag · 架构=$arch · 资源=$name""
Write-Host ""下载: $url""
Write-Host '##progress 35'
Write-Host '##task 正在下载 MSI…'
$tmp = Join-Path $env:TEMP (""cc-switch-"" + [guid]::NewGuid().ToString('N') + '.msi')
Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -Headers $headers
Write-Host '##progress 75'
Write-Host '##task 正在安装 MSI…'
# /passive：显示进度条、无需交互；失败时抛出 msiexec 退出码
$p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $tmp, '/passive', '/norestart') -Wait -PassThru
Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
if ($null -eq $p -or $p.ExitCode -ne 0) {
  $code = if ($p) { $p.ExitCode } else { -1 }
  throw ""msiexec 安装失败 exit=$code""
}
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
Write-Host '##progress 100'
Write-Host ""已安装 CC Switch ($tag)""
");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);

        InstallDetector.ProbeAndStore(context.Db, context.ToolId, install?.Detect);
        return result;
    }

    private static string Escape(string s) => s.Replace("'", "''");
}
