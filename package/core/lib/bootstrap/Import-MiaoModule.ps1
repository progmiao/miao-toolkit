# 按需 dot-source 页面与域模块，并将函数注册到 global（供 Session 内懒加载）



if (-not (Get-Variable -Name MiaoModuleExports -Scope Global -ErrorAction SilentlyContinue)) {

    $global:MiaoModuleExports = @{}

}

if (-not $global:MiaoLoadedModules) {

    $global:MiaoLoadedModules = @{}

}

$script:MiaoLoadedModules = $global:MiaoLoadedModules



function Get-MiaoToolDepsModulePaths {

    return @(

        'domain\Check-Update.ps1'

        'domain\Ensure-ToolDeps.ps1'

        'config\Deps-State.ps1'

        'domain\Invoke-ToolDepPackage.ps1'

        'domain\Invoke-ToolkitDepOperation.ps1'

        'ui\shell\DepOperationView.ps1'
        'ui\shell\ToolkitDepBatchOperation.ps1'

        'domain\Invoke-ToolkitDeps.ps1'

    )

}



function Import-MiaoToolDepsModule {

    Import-MiaoModule -Name ToolDeps

}



function Get-MiaoModuleFunctionNames {

    param([string[]]$Paths)



    $names = @()

    foreach ($path in $Paths) {

        if (-not (Test-Path $path)) { continue }

        $tokens = $null

        $errors = $null

        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)

        if ($null -eq $ast) { continue }

        foreach ($node in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {

            $names += [string]$node.Name

        }

    }

    return @($names | Select-Object -Unique)

}



function Import-MiaoModule {

    param(

        [Parameter(Mandatory)]

        [ValidateSet('Tool', 'ToolDeps', 'Help', 'Lang', 'Sys', 'Update', 'Install', 'Init', 'Cache')]

        [string]$Name

    )



    $lib = $script:MiaoCoreLibDir
    if ([string]::IsNullOrWhiteSpace($lib)) {
        $lib = $global:MiaoCoreLibDir
    }

    if ([string]::IsNullOrWhiteSpace($lib)) {

        throw 'Miao core not bootstrapped. Call Load-Core.ps1 first.'

    }

    if ($Name -eq 'Cache') { $Name = 'Init' }



    if (-not $script:MiaoLoadedModules) {
        $script:MiaoLoadedModules = $global:MiaoLoadedModules
    }
    if (-not $script:MiaoLoadedModules) {
        $script:MiaoLoadedModules = @{}
        $global:MiaoLoadedModules = $script:MiaoLoadedModules
    }

    if ($script:MiaoLoadedModules.ContainsKey($Name)) {

        return

    }



    $toolDepsPaths = @(Get-MiaoToolDepsModulePaths)

    $paths = switch ($Name) {

        'ToolDeps' { $toolDepsPaths }

        'Tool' { @($toolDepsPaths + 'domain\Invoke-Tool.ps1') }

        'Help' { @('pages\sys.ps1', 'pages\help.ps1') }

        'Lang' { @('pages\lang.ps1') }

        'Sys' { @('pages\sys.ps1') }

        'Update' { @('domain\Check-Update.ps1', 'pages\update.ps1') }

        'Install' { @($toolDepsPaths + 'pages\install.ps1', 'pages\toolbox-deps.ps1') }

        'Init' { @('ui\shell\ToolkitDepBatchOperation.ps1', 'ui\shell\DepOperationView.ps1', 'pages\init.ps1') }
        'Cache' { @('ui\shell\ToolkitDepBatchOperation.ps1', 'ui\shell\DepOperationView.ps1', 'pages\init.ps1') }

    }



    $fullPaths = @($paths | ForEach-Object { Join-Path $lib $_ })

    $exportNames = @(Get-MiaoModuleFunctionNames -Paths $fullPaths)

    if (-not $global:MiaoModuleExports) {
        $global:MiaoModuleExports = @{}
    }
    $global:MiaoModuleExports[$Name] = $exportNames



    foreach ($rel in $paths) {

        . (Join-Path $lib $rel)

    }



    foreach ($fnName in @($exportNames)) {

        $cmd = Get-Command -Name $fnName -CommandType Function -ErrorAction SilentlyContinue

        if ($cmd) {

            Set-Item -Path "function:global:$fnName" -Value $cmd.ScriptBlock -Force | Out-Null

        }

    }



    $script:MiaoLoadedModules[$Name] = $true
    $global:MiaoLoadedModules = $script:MiaoLoadedModules

}



function Ensure-MiaoShellViewModule {

    param(

        [Parameter(Mandatory)]

        [ValidateSet(

            'ToolList', 'Help', 'Sys', 'Lang', 'Update', 'Install', 'Tool',

            'ToolDep', 'Init', 'InitFromSys', 'ToolboxDepUpdate', 'ToolboxDepUninstall', 'SysUninstall'

        )]

        [string]$View

    )



    switch ($View) {

        'ToolList' { }

        'Help' { Import-MiaoModule -Name Help }

        'Sys' { Import-MiaoModule -Name Sys }

        'Lang' { Import-MiaoModule -Name Lang }

        'Update' { Import-MiaoModule -Name Update }

        'Install' { Import-MiaoModule -Name Install }

        'ToolboxDepUpdate' { Import-MiaoModule -Name Install }

        'ToolboxDepUninstall' { Import-MiaoModule -Name Install }

        'Init' { Import-MiaoModule -Name Init }

        'InitFromSys' { Import-MiaoModule -Name Init; Import-MiaoModule -Name Sys }

        'SysUninstall' { Import-MiaoModule -Name Sys }

        'Tool' { Import-MiaoModule -Name Tool }

        'ToolDep' { Import-MiaoModule -Name ToolDeps }

    }

}


