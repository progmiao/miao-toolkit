namespace Miao.Common.Software;

/// <summary>
/// 软件一级分组 id（与 seeds/software/{id}.json 及条目 group 字段一致）。
/// </summary>
public static class SoftwareGroups
{
    /// <summary>日常工具（微信、向日葵等）。</summary>
    public const string Daily = "daily";

    /// <summary>开发工具（Node、Claude、CC Switch、TerminalBuddy 等）。</summary>
    public const string Dev = "dev";
}
