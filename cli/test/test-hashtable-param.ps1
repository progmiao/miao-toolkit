$shell = @{ TestMultiListChecked = [System.Collections.Generic.HashSet[int]]::new() }

function TestHashtableParam {
    param([hashtable]$Shell)
    return $Shell['TestMultiListChecked']
}

function TestObjectParam {
    param($Shell)
    return $Shell['TestMultiListChecked']
}

$h1 = TestHashtableParam -Shell $shell
$h2 = TestObjectParam -Shell $shell
Write-Host "hashtable param null: $($null -eq $h1) type: $($h1.GetType().FullName)"
Write-Host "object param null: $($null -eq $h2) type: $($h2.GetType().FullName)"
