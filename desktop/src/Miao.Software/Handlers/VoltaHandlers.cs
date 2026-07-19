using System.Text;
using Miao.Common.Jobs;
using Miao.Software.Detect;
using Miao.Software.Volta;

namespace Miao.Software.Handlers;

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
        sb.AppendLine("$ErrorActionPreference = 'Stop'");
        sb.AppendLine("function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }");
        sb.AppendLine("Refresh-Path");
        sb.AppendLine("if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {");
        sb.AppendLine("  throw '未安装 Volta。请先在开发工具中安装「Volta」，再管理 Node / pnpm / Yarn。'");
        sb.AppendLine("}");
    }

    /// <summary>兼容旧名：改为要求已安装，不再静默 winget。</summary>
    public static void AppendEnsureVolta(StringBuilder sb) => AppendRequireVolta(sb);

    public static string Escape(string s) => s.Replace("'", "''");
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

        var sb = new StringBuilder();
        VoltaScript.AppendEnsureVolta(sb);
        sb.AppendLine("Write-Host '##progress 18'");
        sb.AppendLine($"Write-Host '准备安装 {pkg}（{targets.Count} 个版本）…'");

        for (var i = 0; i < targets.Count; i++)
        {
            var ver = VoltaScript.Escape(targets[i]);
            var pct = 20 + (int)(70.0 * (i + 1) / targets.Count);
            sb.AppendLine($"Write-Host '##progress {pct}'");
            sb.AppendLine($"Write-Host 'volta install {pkg}@{ver}'");
            sb.AppendLine($"volta install {pkg}@{ver}");
            sb.AppendLine($"if ($LASTEXITCODE -ne 0) {{ throw \"volta install {pkg}@{ver} 失败\" }}");
        }

        sb.AppendLine("Write-Host '##progress 100'");
        sb.AppendLine("Refresh-Path");
        sb.AppendLine($"if (Get-Command {pkg} -ErrorAction SilentlyContinue) {{ Write-Host \"当前 {pkg}: \" + (& {pkg} {(pkg == "node" ? "-v" : "--version")} | Select-Object -First 1) }}");

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

        var sb = new StringBuilder();
        VoltaScript.AppendEnsureVolta(sb);
        sb.AppendLine("Write-Host '##progress 15'");

        for (var i = 0; i < targets.Count; i++)
        {
            var ver = VoltaScript.Escape(targets[i]);
            var pct = 20 + (int)(70.0 * (i + 1) / targets.Count);
            sb.AppendLine($"Write-Host '##progress {pct}'");
            sb.AppendLine($"Write-Host '卸载 {pkg}@{ver}…'");
            sb.AppendLine($"volta uninstall {pkg}@{ver}");
            sb.AppendLine($"$img = Join-Path $env:LOCALAPPDATA 'Volta\\tools\\image\\{pkg}\\{ver}'");
            sb.AppendLine("if (Test-Path $img) { Remove-Item -LiteralPath $img -Recurse -Force -ErrorAction SilentlyContinue }");
        }

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
        sb.AppendLine("Write-Host '##progress 40'");
        sb.AppendLine($"Write-Host '设置默认 {pkg}@{escaped}'");
        sb.AppendLine($"volta install {pkg}@{escaped}");
        sb.AppendLine("if ($LASTEXITCODE -ne 0) { throw '设置默认失败' }");
        sb.AppendLine("Write-Host '##progress 100'");

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
        sb.AppendLine("Write-Host '##progress 30'");
        sb.AppendLine($"Set-Location -LiteralPath '{dir}'");
        sb.AppendLine($"Write-Host 'volta pin {pkg}@{escaped} @ {dir}'");
        sb.AppendLine($"volta pin {pkg}@{escaped}");
        sb.AppendLine("if ($LASTEXITCODE -ne 0) { throw 'volta pin 失败' }");
        sb.AppendLine("Write-Host '##progress 100'");
        sb.AppendLine("Write-Host '已写入项目 Volta pin'");

        return await context.Jobs
            .RunPowerShellAsync(context.JobId, sb.ToString(), cancellationToken: cancellationToken)
            .ConfigureAwait(false);
    }
}
