using System.Diagnostics;
using System.Text.Json;
using Miao.Common.Sites;
using Miao.Data;

namespace Miao.Sites;

/// <summary>
/// 常用网站：系统项只读；用户项可增删改；导入仅写入用户数据。
/// </summary>
public sealed class SiteService
{
    private readonly AppDatabase _db;

    /// <summary>创建服务。</summary>
    public SiteService(AppDatabase db) => _db = db;

    /// <summary>列出分类（含 editable）。</summary>
    public IReadOnlyList<SiteCategoryDto> ListCategories()
    {
        return _db.ListSiteCategories()
            .Select(c => new SiteCategoryDto(
                c.Id, c.Name, c.SortOrder, c.Source, c.Source == "user"))
            .ToList();
    }

    /// <summary>列出网站（含 editable）。</summary>
    public IReadOnlyList<SiteDto> ListSites()
    {
        return _db.ListSites()
            .Select(s => new SiteDto(
                s.Id, s.CategoryId, s.Title, s.Url, s.SortOrder, s.Source, s.Note, s.Source == "user"))
            .ToList();
    }

    /// <summary>用系统默认浏览器打开 URL。</summary>
    public string? OpenSite(string id)
    {
        var site = _db.GetSite(id);
        if (site is null) return "网站不存在";
        if (!Uri.TryCreate(site.Url, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        {
            return "无效的网址";
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = uri.ToString(),
            UseShellExecute = true,
        });
        return null;
    }

    /// <summary>保存用户分类；系统分类拒绝修改。</summary>
    public string? SaveCategory(string? id, string name, int sort)
    {
        if (string.IsNullOrWhiteSpace(name)) return "分类名称不能为空";
        var cid = string.IsNullOrWhiteSpace(id) ? $"user-cat-{Guid.NewGuid():N}" : id!.Trim();
        var existing = _db.GetSiteCategory(cid);
        if (existing is not null && existing.Source != "user")
            return "系统分类不可编辑";

        _db.UpsertSiteCategory(cid, name.Trim(), sort, "user");
        return null;
    }

    /// <summary>保存用户网站；系统网站拒绝修改。</summary>
    public string? SaveSite(string? id, string categoryId, string title, string url, int sort, string? note)
    {
        if (string.IsNullOrWhiteSpace(title)) return "标题不能为空";
        if (string.IsNullOrWhiteSpace(categoryId)) return "请选择分类";
        if (!Uri.TryCreate(url?.Trim(), UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        {
            return "请输入有效的 http(s) 网址";
        }

        var cat = _db.GetSiteCategory(categoryId);
        if (cat is null) return "分类不存在";

        var sid = string.IsNullOrWhiteSpace(id) ? $"user-site-{Guid.NewGuid():N}" : id!.Trim();
        var existing = _db.GetSite(sid);
        if (existing is not null && existing.Source != "user")
            return "系统网站不可编辑";

        _db.UpsertSite(sid, categoryId, title.Trim(), uri.ToString(), sort, "user", note?.Trim());
        return null;
    }

    /// <summary>删除用户网站。</summary>
    public string? DeleteSite(string id)
    {
        if (!_db.DeleteUserSite(id)) return "只能删除自己添加的网站";
        return null;
    }

    /// <summary>删除用户分类。</summary>
    public string? DeleteCategory(string id)
    {
        if (!_db.DeleteUserSiteCategory(id)) return "只能删除自己添加的分类";
        return null;
    }

    /// <summary>导出全部可见数据（系统+用户）。</summary>
    public string ExportJson()
    {
        var file = new SitesExportFile
        {
            Categories = _db.ListSiteCategories().Select(c => new SitesExportCategory
            {
                Id = c.Id,
                Name = c.Name,
                Sort = c.SortOrder,
                Source = c.Source,
            }).ToList(),
            Sites = _db.ListSites().Select(s => new SitesExportSite
            {
                Id = s.Id,
                CategoryId = s.CategoryId,
                Title = s.Title,
                Url = s.Url,
                Sort = s.SortOrder,
                Source = s.Source,
                Note = s.Note,
            }).ToList(),
        };
        return JsonSerializer.Serialize(file, new JsonSerializerOptions { WriteIndented = true });
    }

    /// <summary>导入：仅写入用户项；跳过与系统 id 冲突的项。</summary>
    public string? ImportJson(string json)
    {
        SitesExportFile? file;
        try
        {
            file = JsonSerializer.Deserialize<SitesExportFile>(json);
        }
        catch (Exception ex)
        {
            return $"JSON 无效: {ex.Message}";
        }

        if (file is null) return "空文件";

        foreach (var c in file.Categories)
        {
            if (string.IsNullOrWhiteSpace(c.Id) || string.IsNullOrWhiteSpace(c.Name)) continue;
            var existing = _db.GetSiteCategory(c.Id);
            if (existing is not null && existing.Source == "system") continue;
            _db.UpsertSiteCategory(c.Id.Trim(), c.Name.Trim(), c.Sort, "user");
        }

        foreach (var s in file.Sites)
        {
            if (string.IsNullOrWhiteSpace(s.Id) || string.IsNullOrWhiteSpace(s.Title)) continue;
            var existing = _db.GetSite(s.Id);
            if (existing is not null && existing.Source == "system") continue;
            if (!Uri.TryCreate(s.Url?.Trim(), UriKind.Absolute, out var uri)) continue;
            _db.UpsertSite(s.Id.Trim(), s.CategoryId, s.Title.Trim(), uri.ToString(), s.Sort, "user", s.Note);
        }

        return null;
    }
}
