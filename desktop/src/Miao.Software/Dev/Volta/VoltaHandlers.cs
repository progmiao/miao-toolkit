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
        sb.AppendLine($"Write-Host '准备安装 {pkg}（{total} 个版本）…'");

        for (var i = 0; i < total; i++)
        {
            var ver = VoltaScript.Escape(targets[i]);
            var n = i + 1;
            var startPct = VoltaScript.SliceProgress(i, total, 0);
            var midPct = VoltaScript.SliceProgress(i, total, 0.15);
            var endPct = VoltaScript.SliceProgress(i, total, 1);

            sb.AppendLine($"Write-Host '##log [{n}/{total}] 开始安装 {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##task 安装 {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##progress {startPct}'");
            sb.AppendLine($"Write-Host '[{n}/{total}] volta install {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##progress {midPct}'");
            sb.AppendLine($"volta install {pkg}@{ver}");
            sb.AppendLine($"if ($LASTEXITCODE -ne 0) {{ throw \"volta install {pkg}@{ver} 失败 (exit=$LASTEXITCODE)\" }}");
            sb.AppendLine($"Write-Host '##log [{n}/{total}] 安装成功 {pkg}@{ver}'");
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

/// <summary>经 Volta 卸载指定版本并清理镜像残留。</summary>
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

        sb.AppendLine($"Write-Host '##log 准备卸载 {pkg}，共 {total} 个版本'");
        sb.AppendLine($"Write-Host '##task 准备卸载 {pkg}（{total} 个版本）'");
        sb.AppendLine("Write-Host '##progress 0'");

        for (var i = 0; i < total; i++)
        {
            var ver = VoltaScript.Escape(targets[i]);
            var n = i + 1;
            var startPct = VoltaScript.SliceProgress(i, total, 0);
            var midPct = VoltaScript.SliceProgress(i, total, 0.2);
            var endPct = VoltaScript.SliceProgress(i, total, 1);

            sb.AppendLine($"Write-Host '##log [{n}/{total}] 开始卸载 {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##task 卸载 {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##progress {startPct}'");
            sb.AppendLine($"Write-Host '[{n}/{total}] volta uninstall {pkg}@{ver}'");
            sb.AppendLine($"Write-Host '##progress {midPct}'");
            sb.AppendLine($"volta uninstall {pkg}@{ver}");
            sb.AppendLine($"$img = Join-Path $env:LOCALAPPDATA 'Volta\\tools\\image\\{pkg}\\{ver}'");
            sb.AppendLine("if (Test-Path $img) { Write-Host \"##log 清理镜像目录 $img\"; Remove-Item -LiteralPath $img -Recurse -Force -ErrorAction SilentlyContinue }");
            sb.AppendLine($"Write-Host '##log [{n}/{total}] 卸载完成 {pkg}@{ver}'");
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
