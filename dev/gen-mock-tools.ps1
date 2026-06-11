$ErrorActionPreference = 'Stop'

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8



# 命令列 command 使用真实开发命令，便于后续 miao <cmd> 联调测试

$commandCatalog = @(

    [ordered]@{ command = 'pnpm'; name = 'pnpm 包管理'; description = '快速、节省磁盘空间的 Node 包管理器' }

    [ordered]@{ command = 'yarn'; name = 'Yarn 包管理'; description = '可靠、经典的 Node 包管理器' }

    [ordered]@{ command = 'npm'; name = 'npm 包管理'; description = 'Node.js 官方包管理器' }

    [ordered]@{ command = 'claude-code'; name = 'Claude Code'; description = 'Claude 编码助手 CLI 集成' }

    [ordered]@{ command = 'superpowers'; name = 'Superpowers'; description = '开发工作流增强工具集' }

    [ordered]@{ command = 'skill'; name = 'Skill'; description = 'Cursor Agent Skill 管理与调试' }

    [ordered]@{ command = 'hermes'; name = 'Hermes'; description = '开发通信与消息桥接工具' }

)



$tools = for ($n = 2; $n -le 81; $n++) {

    $c = $commandCatalog[($n - 2) % $commandCatalog.Count]

    [ordered]@{

        no              = $n

        command         = $c.command

        name            = $c.name

        description     = $c.description

        requiresInstall = $false

    }

}

$obj = [ordered]@{ enabled = $true; tools = @($tools) }

$path = Join-Path $PSScriptRoot 'mock-tools.json'

$json = $obj | ConvertTo-Json -Depth 4

[System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($true))

Write-Host "written $($tools.Count) mock tools -> $path"

