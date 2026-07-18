$ErrorActionPreference = 'Stop'
$sw = [Diagnostics.Stopwatch]::StartNew()
$job = Start-Job -ArgumentList @($false) -ScriptBlock {
    param([bool]$LtsOnlyFlag)
    $ErrorActionPreference = 'Stop'
    $releases = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
    if ($LtsOnlyFlag) {
        $releases = @($releases | Where-Object { $_.lts -ne $false })
    }
    return @($releases | ForEach-Object {
        [PSCustomObject]@{
            Version = ($_.version -replace '^v', '')
            Lts     = $_.lts
            Date    = $_.date
        }
    })
}
while ($job.State -eq 'Running' -and $sw.ElapsedMilliseconds -lt 60000) {
    Start-Sleep -Milliseconds 100
}
Write-Host "State=$($job.State) Elapsed=$($sw.ElapsedMilliseconds)ms"
if ($job.State -eq 'Completed') {
    $r = Receive-Job -Job $job
    Write-Host "Count=$($r.Count)"
}
Remove-Job -Job $job -Force
