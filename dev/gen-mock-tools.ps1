$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 命令列 id 使用真实开发命令，便于后续 miao <cmd> 联调测试
$commandCatalog = @(
    [ordered]@{ id = 'pnpm'; displayName = 'pnpm 包管理'; summary = '快速、节省磁盘空间的 Node 包管理器' }
    [ordered]@{ id = 'yarn'; displayName = 'Yarn 包管理'; summary = '可靠、经典的 Node 包管理器' }
    [ordered]@{ id = 'npm'; displayName = 'npm 包管理'; summary = 'Node.js 官方包管理器' }
    [ordered]@{ id = 'claude-code'; displayName = 'Claude Code'; summary = 'Claude 编码助手 CLI 集成' }
    [ordered]@{ id = 'superpowers'; displayName = 'Superpowers'; summary = '开发工作流增强工具集' }
    [ordered]@{ id = 'skill'; displayName = 'Skill'; summary = 'Cursor Agent Skill 管理与调试' }
    [ordered]@{ id = 'hermes'; displayName = 'Hermes'; summary = '开发通信与消息桥接工具' }
)

$tools = for ($n = 2; $n -le 81; $n++) {
    $c = $commandCatalog[($n - 2) % $commandCatalog.Count]
    [ordered]@{
        number          = $n
        id              = $c.id
        displayName     = $c.displayName
        summary         = $c.summary
        requiresInstall = $false
    }
}
$obj = [ordered]@{ enabled = $true; tools = @($tools) }
$path = Join-Path $PSScriptRoot 'mock-tools.json'
$json = $obj | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($true))
Write-Host "written $($tools.Count) mock tools -> $path"
