using System.Text;
using Miao.Common.Jobs;
using Miao.Software.Detect;

namespace Miao.Software.Dev.CcSwitch;

/// <summary>
/// CC Switch：从 GitHub Releases 下载官方 Windows MSI 并安装（对齐用户手册）。
/// 安装闸门：本机需已安装 Node.js 18+。
/// 下载阶段流式读入并输出「已下载 / 总大小」，驱动命令窗进度行与 ##progress。
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
$sizeBytes = 0L
try { $sizeBytes = [int64]$item.size } catch { $sizeBytes = 0L }
Write-Host ""下载: $url""
Write-Host '##progress 35'
Write-Host '##task 正在下载 MSI…'
$tmp = Join-Path $env:TEMP (""cc-switch-"" + [guid]::NewGuid().ToString('N') + '.msi')
# 流式下载并汇报进度（输出 ""已下载 / 总大小""，供命令窗原地刷新 + 进度条）
Add-Type -AssemblyName System.Net.Http | Out-Null
function Format-MiaoSize([int64]$n) {
  $c = [Globalization.CultureInfo]::InvariantCulture
  if ($n -ge 1GB) { return [string]::Format($c, '{0:0.0} GB', $n / 1GB) }
  if ($n -ge 1MB) { return [string]::Format($c, '{0:0.0} MB', $n / 1MB) }
  if ($n -ge 1KB) { return [string]::Format($c, '{0:0.0} KB', $n / 1KB) }
  return (""$n B"")
}
$http = $null
$resp = $null
$inStream = $null
$outStream = $null
try {
  $http = New-Object System.Net.Http.HttpClient
  $http.Timeout = [TimeSpan]::FromMinutes(30)
  $http.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', 'miao-toolkit') | Out-Null
  $resp = $http.GetAsync($url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
  if (-not $resp.IsSuccessStatusCode) {
    throw ""下载失败 HTTP $([int]$resp.StatusCode) $($resp.ReasonPhrase)""
  }
  $tot = 0L
  if ($resp.Content.Headers.ContentLength.HasValue) { $tot = [int64]$resp.Content.Headers.ContentLength.Value }
  if ($tot -le 0 -and $sizeBytes -gt 0) { $tot = $sizeBytes }
  $inStream = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
  $outStream = [System.IO.File]::Create($tmp)
  $buffer = New-Object byte[] 81920
  $recv = [int64]0
  $lastPct = -1
  $lastAt = [datetime]::MinValue
  while (($read = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
    $outStream.Write($buffer, 0, $read)
    $recv += $read
    $now = [datetime]::UtcNow
    if ($tot -gt 0) {
      $pct = [int][Math]::Min(100, [Math]::Floor((100.0 * $recv) / $tot))
      if ($pct -lt 100 -and $pct -eq $lastPct) { continue }
      if ($pct -lt 100 -and ($pct - $lastPct) -lt 1 -and ($now - $lastAt).TotalMilliseconds -lt 250) { continue }
      $lastPct = $pct
      $lastAt = $now
      Write-Host (""$(Format-MiaoSize $recv) / $(Format-MiaoSize $tot)"")
      $mapped = 35 + [int][Math]::Floor(39.0 * $pct / 100.0)
      Write-Host ""##progress $mapped""
    } else {
      if (($now - $lastAt).TotalMilliseconds -lt 800) { continue }
      $lastAt = $now
      Write-Host ""##task 正在下载 MSI… $(Format-MiaoSize $recv)""
    }
  }
  if ($tot -gt 0) {
    Write-Host (""$(Format-MiaoSize $recv) / $(Format-MiaoSize $tot)"")
  } elseif ($recv -gt 0) {
    Write-Host (""已下载 $(Format-MiaoSize $recv)"")
  }
  Write-Host '下载完成'
} finally {
  if ($outStream) { $outStream.Dispose() }
  if ($inStream) { $inStream.Dispose() }
  if ($resp) { $resp.Dispose() }
  if ($http) { $http.Dispose() }
}
Write-Host '##progress 75'
Write-Host '##task 正在安装 MSI…'
# /quiet：完全静默、无 MSI UI；失败时靠退出码与日志反馈
$p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $tmp, '/quiet', '/norestart') -Wait -PassThru
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
