$hs = [System.Collections.Generic.HashSet[int]]::new()
$shell = @{ TestMultiListChecked = $hs; Name = 'ok' }

function ReadShell {
    param($Shell)
    Write-Host "Name=$($Shell['Name'])"
    Write-Host "KeyExists=$($Shell.ContainsKey('TestMultiListChecked'))"
    $v = $Shell['TestMultiListChecked']
    Write-Host "ValueNull=$($null -eq $v)"
    if ($v) { Write-Host "ValueType=$($v.GetType().FullName)" }
    return $v
}

$r = ReadShell -Shell $shell
Write-Host "ReturnNull=$($null -eq $r)"
