# Volta does not support `volta uninstall` for node/yarn/pnpm.
# Manual cleanup mirrors upstream guidance:
#   tools/image/<tool>/<version>/
#   tools/inventory/<tool>/<tool>-v<version>*
#   tools/user/platform.json default pin (if matching)
#
# 若目标是默认版本，node.exe 常被占用：先把默认切到「本批不卸载的已装最新版」再删。

function Get-VoltaHomeRoots {
  $roots = New-Object System.Collections.Generic.List[string]
  if ($env:VOLTA_HOME -and $env:VOLTA_HOME.Trim().Length -gt 0) {
    [void]$roots.Add($env:VOLTA_HOME.Trim())
  }
  if ($env:LOCALAPPDATA) {
    [void]$roots.Add((Join-Path $env:LOCALAPPDATA 'Volta'))
  }
  if ($env:USERPROFILE) {
    [void]$roots.Add((Join-Path $env:USERPROFILE '.volta'))
  }
  return @($roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
}

function Normalize-VoltaVersion([string]$Version) {
  if ([string]::IsNullOrWhiteSpace($Version)) { return '' }
  return $Version.Trim().TrimStart('v', 'V')
}

function Get-VoltaDefaultVersion([string]$Tool) {
  foreach ($root in Get-VoltaHomeRoots) {
    $platform = Join-Path $root 'tools\user\platform.json'
    if (-not (Test-Path -LiteralPath $platform)) { continue }
    try {
      $json = Get-Content -LiteralPath $platform -Raw -Encoding UTF8
      if ([string]::IsNullOrWhiteSpace($json)) { continue }
      $obj = $json | ConvertFrom-Json
      if ($Tool -eq 'node' -and $null -ne $obj.node) {
        $runtime = [string]$obj.node.runtime
        if ($runtime) { return (Normalize-VoltaVersion $runtime) }
      }
      if ($Tool -eq 'npm' -and $null -ne $obj.npm) {
        return (Normalize-VoltaVersion ([string]$obj.npm))
      }
      if ($Tool -eq 'yarn' -and $null -ne $obj.yarn) {
        return (Normalize-VoltaVersion ([string]$obj.yarn))
      }
      if ($Tool -eq 'pnpm' -and $null -ne $obj.pnpm) {
        return (Normalize-VoltaVersion ([string]$obj.pnpm))
      }
    } catch {}
  }
  return $null
}

function Get-VoltaInstalledVersions([string]$Tool) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($root in Get-VoltaHomeRoots) {
    $dir = Join-Path $root ("tools\image\" + $Tool)
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
      $v = Normalize-VoltaVersion $_.Name
      if ($v) { [void]$set.Add($v) }
    }
  }
  return @($set)
}

function Get-LatestSemver([string[]]$Versions) {
  $list = @($Versions | Where-Object { $_ -and $_.Trim().Length -gt 0 } | ForEach-Object { Normalize-VoltaVersion $_ })
  if ($list.Count -eq 0) { return $null }
  $parsed = @()
  foreach ($v in $list) {
    try {
      $parsed += [pscustomobject]@{ Raw = $v; Ver = [version]$v }
    } catch {
      $parsed += [pscustomobject]@{ Raw = $v; Ver = $null }
    }
  }
  $withVer = @($parsed | Where-Object { $null -ne $_.Ver } | Sort-Object Ver -Descending)
  if ($withVer.Count -gt 0) { return [string]$withVer[0].Raw }
  return [string](($parsed | Sort-Object Raw -Descending)[0].Raw)
}

function Stop-VoltaImageLocks([string]$ImageDir) {
  if (-not (Test-Path -LiteralPath $ImageDir)) { return }
  $full = [System.IO.Path]::GetFullPath($ImageDir).TrimEnd('\')
  Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
    try {
      $p = $_.Path
      if (-not $p) { return }
      $pf = [System.IO.Path]::GetFullPath($p)
      if ($pf.StartsWith($full + '\', [StringComparison]::OrdinalIgnoreCase) -or
          $pf.Equals($full, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ("结束占用进程: " + $_.ProcessName + " (PID " + $_.Id + ")")
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
      }
    } catch {}
  }
}

function Remove-TreeForced([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $true }
  Write-Host ("删除: " + $Path)
  Stop-VoltaImageLocks $Path
  try {
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
  } catch {
    Write-Host ("警告: 删除失败，尝试解除只读后重试: " + $_.Exception.Message)
    Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
      try { $_.Attributes = 'Normal' } catch {}
    }
    # exe 仍占用时先改名再删
    Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
      Where-Object { -not $_.PSIsContainer -and $_.Extension -match '\.(exe|dll)$' } |
      ForEach-Object {
        try {
          $tmp = $_.FullName + '.miao-del'
          Move-Item -LiteralPath $_.FullName -Destination $tmp -Force -ErrorAction Stop
        } catch {}
      }
    Start-Sleep -Milliseconds 200
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
  }
  if (Test-Path -LiteralPath $Path) {
    Write-Host ("错误: 仍存在 " + $Path)
    return $false
  }
  return $true
}

function Clear-VoltaDefaultPin([string]$Tool, [string]$Version) {
  $Version = Normalize-VoltaVersion $Version
  foreach ($root in Get-VoltaHomeRoots) {
    $platform = Join-Path $root 'tools\user\platform.json'
    if (-not (Test-Path -LiteralPath $platform)) { continue }
    try {
      $json = Get-Content -LiteralPath $platform -Raw -Encoding UTF8
      if ([string]::IsNullOrWhiteSpace($json)) { continue }
      $obj = $json | ConvertFrom-Json
      $changed = $false

      if ($null -ne $obj.node -and $Tool -eq 'node') {
        $runtime = Normalize-VoltaVersion ([string]$obj.node.runtime)
        if ($runtime -and ($runtime -eq $Version)) {
          Write-Host ("清除默认 node 引用: " + $platform)
          $obj.node = $null
          $changed = $true
        }
      }
      if ($null -ne $obj.npm -and $Tool -eq 'npm') {
        $npmVer = Normalize-VoltaVersion ([string]$obj.npm)
        if ($npmVer -and ($npmVer -eq $Version)) {
          Write-Host ("清除默认 npm 引用: " + $platform)
          $obj.npm = $null
          $changed = $true
        }
      }
      if ($null -ne $obj.yarn -and $Tool -eq 'yarn') {
        $yarnVer = Normalize-VoltaVersion ([string]$obj.yarn)
        if ($yarnVer -and ($yarnVer -eq $Version)) {
          Write-Host ("清除默认 yarn 引用: " + $platform)
          $obj.yarn = $null
          $changed = $true
        }
      }
      if ($null -ne $obj.pnpm -and $Tool -eq 'pnpm') {
        $pnpmVer = Normalize-VoltaVersion ([string]$obj.pnpm)
        if ($pnpmVer -and ($pnpmVer -eq $Version)) {
          Write-Host ("清除默认 pnpm 引用: " + $platform)
          $obj.pnpm = $null
          $changed = $true
        }
      }

      if ($changed) {
        ($obj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $platform -Encoding UTF8
      }
    } catch {
      Write-Host ("警告: 处理 platform.json 失败: " + $_.Exception.Message)
    }
  }
}

<#
.SYNOPSIS
  若即将卸载的版本是默认，先切到「不在排除列表中的已装最新版」。
#>
function Ensure-VoltaDefaultSwitchedAway {
  param(
    [Parameter(Mandatory = $true)][string]$Tool,
    [Parameter(Mandatory = $true)][string]$Version,
    [string[]]$ExcludeVersions = @()
  )
  $Version = Normalize-VoltaVersion $Version
  $default = Get-VoltaDefaultVersion $Tool
  if (-not $default -or ($default -ne $Version)) {
    return
  }

  $exclude = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  [void]$exclude.Add($Version)
  foreach ($x in @($ExcludeVersions)) {
    $n = Normalize-VoltaVersion $x
    if ($n) { [void]$exclude.Add($n) }
  }

  $candidates = @(Get-VoltaInstalledVersions $Tool | Where-Object { -not $exclude.Contains($_) })
  if ($candidates.Count -eq 0) {
    Write-Host ("默认版本即 " + $Tool + "@" + $Version + "，且无其它可保留版本；先清除默认引用再删除")
    Clear-VoltaDefaultPin -Tool $Tool -Version $Version
    return
  }

  $next = Get-LatestSemver $candidates
  if (-not $next) {
    Clear-VoltaDefaultPin -Tool $Tool -Version $Version
    return
  }

  Write-Host ("当前默认是 " + $Tool + "@" + $Version + "（易被占用），先切换默认为 " + $Tool + "@" + $next)
  Write-Host ("volta install " + $Tool + "@" + $next)
  & volta install ($Tool + '@' + $next)
  if ($LASTEXITCODE -ne 0) {
    throw ("切换默认失败: volta install " + $Tool + "@" + $next + " (exit=$LASTEXITCODE)")
  }
  Write-Host ("已切换默认: " + $Tool + "@" + $next)
}

function Remove-VoltaToolVersion {
  param(
    [Parameter(Mandatory = $true)][string]$Tool,
    [Parameter(Mandatory = $true)][string]$Version,
    [string[]]$ExcludeVersions = @()
  )
  $Version = Normalize-VoltaVersion $Version
  Write-Host ("开始清理 " + $Tool + "@" + $Version)
  $ok = $true
  $roots = @(Get-VoltaHomeRoots)
  if ($roots.Count -eq 0) {
    throw '未找到 Volta 数据目录（LOCALAPPDATA\Volta 或 VOLTA_HOME）'
  }

  Ensure-VoltaDefaultSwitchedAway -Tool $Tool -Version $Version -ExcludeVersions $ExcludeVersions

  foreach ($root in $roots) {
    Write-Host ("Volta 根目录: " + $root)

    $img = Join-Path $root ("tools\image\" + $Tool + "\" + $Version)
    if (Test-Path -LiteralPath $img) {
      if (-not (Remove-TreeForced $img)) { $ok = $false }
    } else {
      Write-Host ("镜像目录不存在（跳过）: " + $img)
    }

    $invDir = Join-Path $root ("tools\inventory\" + $Tool)
    if (Test-Path -LiteralPath $invDir) {
      $prefix = $Tool + '-v' + $Version
      $hits = @(Get-ChildItem -LiteralPath $invDir -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
      })
      if ($hits.Count -eq 0) {
        Write-Host ("inventory 无匹配项（跳过）: " + $prefix + '*')
      }
      foreach ($item in $hits) {
        if (-not (Remove-TreeForced $item.FullName)) { $ok = $false }
      }
    } else {
      Write-Host ("inventory 目录不存在（跳过）: " + $invDir)
    }
  }

  Clear-VoltaDefaultPin -Tool $Tool -Version $Version

  if (-not $ok) { throw ("清理失败: " + $Tool + "@" + $Version) }
  Write-Host ("清理步骤完成: " + $Tool + "@" + $Version)
}

function Test-VoltaToolVersionRemoved {
  param(
    [Parameter(Mandatory = $true)][string]$Tool,
    [Parameter(Mandatory = $true)][string]$Version
  )
  $Version = Normalize-VoltaVersion $Version
  foreach ($root in Get-VoltaHomeRoots) {
    $img = Join-Path $root ("tools\image\" + $Tool + "\" + $Version)
    if (Test-Path -LiteralPath $img) {
      Write-Host ("残留镜像: " + $img)
      return $false
    }

    $invDir = Join-Path $root ("tools\inventory\" + $Tool)
    if (Test-Path -LiteralPath $invDir) {
      $prefix = $Tool + '-v' + $Version
      $hits = @(Get-ChildItem -LiteralPath $invDir -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
      })
      if ($hits.Count -gt 0) {
        foreach ($h in $hits) { Write-Host ("残留 inventory: " + $h.FullName) }
        return $false
      }
    }
  }

  # volta list may show "vX.Y.Z" or "tool@X.Y.Z" (avoid matching shorter prefixes of longer versions)
  try {
    $raw = & volta list $Tool 2>&1 | Out-String
    $escaped = [regex]::Escape($Version)
    $linePat = '(?i)^\s*(?:v)?' + $escaped + '(?:\s|\(|$)'
    $atPat = '(?i)' + [regex]::Escape($Tool) + '@(?:v)?' + $escaped + '(?!\d|\.)'
    foreach ($line in ($raw -split "`r?`n")) {
      if ($line -match $linePat -or $line -match $atPat) {
        Write-Host ("volta list 仍包含 " + $Tool + "@" + $Version)
        return $false
      }
    }
  } catch {
    Write-Host ("警告: volta list 校验跳过: " + $_.Exception.Message)
  }
  return $true
}
