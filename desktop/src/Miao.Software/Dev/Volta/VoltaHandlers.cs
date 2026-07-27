using System.Text;
using Miao.Common.Jobs;
using Miao.Software.Detect;
using Miao.Software.Dev.Volta;

namespace Miao.Software.Dev.Volta;

/// <summary>Volta 工具公共脚本片段。</summary>
internal static class VoltaScript
{
    /// <summary>校验 toolId 并返回 Volta 包名。</summary>
    public static string? PackageOrError(string toolId, out string? error)
    {
        if (!VoltaPackageService.IsSupported(toolId))
        {
            error = $"不支持的 Volta 工具: {toolId}";
            return null;
        }

        error = null;
        return toolId;
    }

    /// <summary>
    /// 要求本机已安装 Volta（由「Volta」工具自行安装）；未安装则失败并提示。
    /// </summary>
    public static void AppendRequireVolta(StringBuilder sb)
    {
        sb.AppendLine("function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }");
        sb.AppendLine("Refresh-Path");
        // 尽量贴近真实终端宽度，让 volta 进度条用 \\r 原地刷新
        sb.AppendLine("$env:COLUMNS = '100'");
        sb.AppendLine("$env:TERM = 'xterm-256color'");
        sb.AppendLine("try { if ($Host.UI.RawUI) { $Host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size(100, [Math]::Max(40, $Host.UI.RawUI.BufferSize.Height)); $Host.UI.RawUI.WindowSize = New-Object Management.Automation.Host.Size(100, [Math]::Min(30, $Host.UI.RawUI.WindowSize.Height)) } } catch {}");
        sb.AppendLine("if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {");
        sb.AppendLine("  throw '未安装 Volta。请先在开发工具中安装「Volta」，再管理 Node / pnpm / Yarn。'");
        sb.AppendLine("}");
    }

    /// <summary>兼容旧名：改为要求已安装，不再静默 winget。</summary>
    public static void AppendEnsureVolta(StringBuilder sb) => AppendRequireVolta(sb);

    public static string Escape(string s) => s.Replace("'", "''");

    /// <summary>
    /// 按任务序号把总进度映射到 0–100（任务数平分）。
    /// </summary>
    /// <param name="index">0-based 当前任务下标。</param>
    /// <param name="total">任务总数。</param>
    /// <param name="within">任务内比例 0–1。</param>
    public static int SliceProgress(int index, int total, double within)
    {
        if (total <= 0) return (int)Math.Round(Math.Clamp(within, 0, 1) * 100);
        var start = index * 100.0 / total;
        var end = (index + 1) * 100.0 / total;
        return (int)Math.Round(start + (end - start) * Math.Clamp(within, 0, 1));
    }
}

/// <summary>经 Volta 安装指定版本（空列表：node→lts，其它→latest）。</summary>
public sealed class VoltaInstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "volta.install";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var pkg = VoltaScript.PackageOrError(context.ToolId, out var err);
        if (pkg is null) return new JobResult(context.JobId, false, 1, err!);

        var fallback = pkg == "node" ? "lts" : "latest";
        var targets = context.Versions.Count > 0
            ? context.Versions.Select(Normalize).Where(v => v.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToList()
            : [fallback];

        var total = targets.Count;
        var sb = new StringBuilder();
        VoltaScript.AppendEnsureVolta(sb);

        sb.AppendLine($"Write-Host '##log 准备安装 {pkg}，共 {total} 个版本'");
        sb.AppendLine($"Write-Host '##task 准备安装 {pkg}（{total} 个版本）'");
        sb.AppendLine("Write-Host '##progress 0'");

        for (var i = 0; i < total; i++)
        {
            var ver = VoltaScript.Escape(targets[i]);
            var n = i + 1;
            var startPct = VoltaScript.SliceProgress(i, total, 0);
            var midPct = VoltaScript.SliceProgress(i, total, 0.15);
            var endPct = VoltaScript.SliceProgress(i, total, 1);

            sb.AppendLine($"Write-Host '##log [{n}/{total}] 安装 {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##task [{n}/{total}] 安装 {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##progress {startPct}'");
            sb.AppendLine($"Write-Host '[{n}/{total}] volta install {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##progress {midPct}'");
            sb.AppendLine($"volta install {pkg}@{ver}");
            sb.AppendLine($"if ($LASTEXITCODE -ne 0) {{ throw \"volta install {pkg}@{ver} 失败 (exit=$LASTEXITCODE)\" }}");
            sb.AppendLine($"Write-Host '##log [{n}/{total}] 安装成功 {pkg}@{ver}'");
            // UI 按条更新版本列表：version-done install|uninstall pkg@ver
            sb.AppendLine($"Write-Host '##log version-done install {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##progress {endPct}'");
        }

        sb.AppendLine($"Write-Host '##log 全部安装完成（{total} 个版本）'");
        sb.AppendLine("Write-Host '##task 安装完成'");
        sb.AppendLine("Write-Host '##progress 100'");
        sb.AppendLine("Refresh-Path");
        sb.AppendLine($"Write-Host '##log 刷新 PATH 并核对 {pkg} 命令'");
        sb.AppendLine($"if (Get-Command {pkg} -ErrorAction SilentlyContinue) {{ Write-Host \"当前 {pkg}: \" + (& {pkg} {(pkg == "node" ? "-v" : "--version")} | Select-Object -First 1) }} else {{ Write-Host '##log 提示：当前会话暂未找到 {pkg} 命令，新开终端后再试' }}");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);
        InstallDetector.ProbeAndStore(context.Db, context.ToolId, context.Manifest.Install?.Detect);
        return result;
    }

    private static string Normalize(string v) => (v ?? "").Trim().TrimStart('v');
}

/// <summary>
/// 卸载 Volta 托管版本。
/// Node/Yarn/pnpm 的 <c>volta uninstall</c> 尚未支持，按 Volta 文档手工清理
/// <c>tools/image</c> 与 <c>tools/inventory</c>，命令窗只记录步骤。
/// </summary>
public sealed class VoltaUninstallHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "volta.uninstall";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var pkg = VoltaScript.PackageOrError(context.ToolId, out var err);
        if (pkg is null) return new JobResult(context.JobId, false, 1, err!);

        var targets = context.Versions
            .Select(v => (v ?? "").Trim().TrimStart('v'))
            .Where(v => v.Length > 0 && !v.Equals("lts", StringComparison.OrdinalIgnoreCase)
                                     && !v.Equals("latest", StringComparison.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (targets.Count == 0)
            return new JobResult(context.JobId, false, 1, "请指定要卸载的具体版本号");

        var total = targets.Count;
        var sb = new StringBuilder();
        VoltaScript.AppendEnsureVolta(sb);
        AppendVoltaRemoveHelpers(sb);

        sb.AppendLine($"Write-Host '##log 准备卸载 {pkg}，共 {total} 个版本（Volta 不支持 CLI 卸载，按目录清理）'");
        sb.AppendLine($"Write-Host '##task 准备卸载 {pkg}（{total} 个版本）'");
        sb.AppendLine("Write-Host '##progress 0'");
        sb.AppendLine($"Write-Host '准备卸载 {pkg}，共 {total} 个版本'");
        sb.AppendLine("Write-Host '说明: volta uninstall 对 node/yarn/pnpm 尚未支持，改为清理 Volta 本地缓存目录'");
        sb.AppendLine("Write-Host '说明: 若目标为默认版本，会先切换到本批不卸载的已装最新版，再删除'");

        var excludeItems = string.Join(", ", targets.Select(t => $"'{VoltaScript.Escape(t)}'"));
        sb.AppendLine($"$voltaUninstallBatch = @({excludeItems})");

        for (var i = 0; i < total; i++)
        {
            var ver = VoltaScript.Escape(targets[i]);
            var n = i + 1;
            var startPct = VoltaScript.SliceProgress(i, total, 0);
            var midPct = VoltaScript.SliceProgress(i, total, 0.45);
            var endPct = VoltaScript.SliceProgress(i, total, 1);

            sb.AppendLine($"Write-Host '##log [{n}/{total}] 卸载 {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##task [{n}/{total}] 卸载 {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##progress {startPct}'");
            sb.AppendLine($"Write-Host '[{n}/{total}] 卸载 {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##progress {midPct}'");
            sb.AppendLine($"Remove-VoltaToolVersion -Tool '{pkg}' -Version '{ver}' -ExcludeVersions $voltaUninstallBatch");
            sb.AppendLine($"if (-not (Test-VoltaToolVersionRemoved -Tool '{pkg}' -Version '{ver}')) {{ throw \"卸载未干净: {pkg}@{ver} 仍有残留\" }}");
            sb.AppendLine($"Write-Host '##log [{n}/{total}] 已干净移除 {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '[{n}/{total}] 已干净移除 {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##log version-done uninstall {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##progress {endPct}'");
        }

        sb.AppendLine($"Write-Host '##log 全部卸载完成（{total} 个版本）'");
        sb.AppendLine("Write-Host '##task 卸载完成'");
        sb.AppendLine("Write-Host '##progress 100'");
        sb.AppendLine("Write-Host '卸载完成'");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);
        InstallDetector.ProbeAndStore(context.Db, context.ToolId, context.Manifest.Install?.Detect);
        return result;
    }

    /// <summary>
    /// 注入手工卸载辅助函数：清理 image / inventory，并处理 user/platform 默认引用。
    /// </summary>
    private static void AppendVoltaRemoveHelpers(StringBuilder sb)
    {
        var helpers = VoltaRemoveHelpers.LoadScript();
        sb.AppendLine(helpers);
    }
}

/// <summary>加载 Volta 手工卸载 PowerShell 辅助脚本。</summary>
file static class VoltaRemoveHelpers
{
    private const string ResourceSuffix = "Remove-VoltaToolVersion.ps1";

    public static string LoadScript()
    {
        var asm = typeof(VoltaUninstallHandler).Assembly;
        var name = asm.GetManifestResourceNames()
            .FirstOrDefault(n => n.EndsWith(ResourceSuffix, StringComparison.OrdinalIgnoreCase));
        if (name is null)
            throw new FileNotFoundException($"未找到嵌入资源 {ResourceSuffix}");

        using var stream = asm.GetManifestResourceStream(name)
            ?? throw new FileNotFoundException($"无法打开嵌入资源 {name}");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}

/// <summary>将已安装版本设为 Volta 默认。</summary>
public sealed class VoltaSetDefaultHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "volta.set-default";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var pkg = VoltaScript.PackageOrError(context.ToolId, out var err);
        if (pkg is null) return new JobResult(context.JobId, false, 1, err!);

        var ver = context.Versions.Select(v => (v ?? "").Trim().TrimStart('v')).FirstOrDefault(v => v.Length > 0);
        if (string.IsNullOrWhiteSpace(ver))
            return new JobResult(context.JobId, false, 1, "请指定要设为默认的版本");

        var escaped = VoltaScript.Escape(ver);
        var sb = new StringBuilder();
        VoltaScript.AppendEnsureVolta(sb);
        sb.AppendLine($"Write-Host '##log 设置默认 {pkg}@{escaped}'");
        sb.AppendLine($"Write-Host '##task 设置默认 {pkg}@{escaped}'");
        sb.AppendLine("Write-Host '##progress 20'");
        sb.AppendLine($"Write-Host 'volta install {pkg}@{escaped}'");
        sb.AppendLine("Write-Host '##progress 40'");
        sb.AppendLine($"volta install {pkg}@{escaped}");
        sb.AppendLine("if ($LASTEXITCODE -ne 0) { throw '设置默认失败' }");
        sb.AppendLine($"Write-Host '##log 已设为默认 {pkg}@{escaped}'");
        sb.AppendLine("Write-Host '##progress 100'");
        sb.AppendLine("Write-Host '##task 完成'");

        var result = await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);
        InstallDetector.ProbeAndStore(context.Db, context.ToolId, context.Manifest.Install?.Detect);
        return result;
    }
}

/// <summary>
/// 在指定项目目录执行 <c>volta pin</c>（需 Options["projectPath"]）。
/// </summary>
public sealed class VoltaPinHandler : IToolActionHandler
{
    /// <inheritdoc />
    public string HandlerId => "volta.pin";

    /// <inheritdoc />
    public async Task<JobResult> ExecuteAsync(ToolActionContext context, CancellationToken cancellationToken = default)
    {
        var pkg = VoltaScript.PackageOrError(context.ToolId, out var err);
        if (pkg is null) return new JobResult(context.JobId, false, 1, err!);

        if (!context.Options.TryGetValue("projectPath", out var projectPath) ||
            string.IsNullOrWhiteSpace(projectPath) ||
            !Directory.Exists(projectPath))
        {
            return new JobResult(context.JobId, false, 1, "请先选择有效的项目目录（含 package.json）");
        }

        var ver = context.Versions.Select(v => (v ?? "").Trim().TrimStart('v')).FirstOrDefault(v => v.Length > 0);
        if (string.IsNullOrWhiteSpace(ver))
            return new JobResult(context.JobId, false, 1, "请指定要 pin 的版本");

        var pkgJson = Path.Combine(projectPath, "package.json");
        if (!File.Exists(pkgJson))
            return new JobResult(context.JobId, false, 1, "项目目录缺少 package.json");

        var dir = VoltaScript.Escape(projectPath);
        var escaped = VoltaScript.Escape(ver);
        var sb = new StringBuilder();
        VoltaScript.AppendEnsureVolta(sb);
        sb.AppendLine($"Write-Host '##log 准备 pin {pkg}@{escaped}'");
        sb.AppendLine($"Write-Host '##task pin {pkg}@{escaped}'");
        sb.AppendLine("Write-Host '##progress 20'");
        sb.AppendLine($"Set-Location -LiteralPath '{dir}'");
        sb.AppendLine($"Write-Host '##log 工作目录: {dir}'");
        sb.AppendLine($"Write-Host 'volta pin {pkg}@{escaped}'");
        sb.AppendLine("Write-Host '##progress 50'");
        sb.AppendLine($"volta pin {pkg}@{escaped}");
        sb.AppendLine("if ($LASTEXITCODE -ne 0) { throw 'volta pin 失败' }");
        sb.AppendLine("Write-Host '##log 已写入项目 Volta pin'");
        sb.AppendLine("Write-Host '##progress 100'");
        sb.AppendLine("Write-Host '##task 完成'");

        return await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);
    }
}
