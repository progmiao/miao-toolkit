$ErrorActionPreference = 'Stop'
try {
    $x = $null.Text
    Write-Host "null.Text ok: [$x]"
}
catch {
    Write-Host "null.Text error: $($_.FullyQualifiedErrorId)"
}

try {
    $null.Contains(0)
}
catch {
    Write-Host "null.Contains error: $($_.FullyQualifiedErrorId)"
}

try {
    $spec = $null
    if ($null -ne $spec.Text) { 'has text' }
}
catch {
    Write-Host "spec.Text check error: $($_.FullyQualifiedErrorId)"
}
