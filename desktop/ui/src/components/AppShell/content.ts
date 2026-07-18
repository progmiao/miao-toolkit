/**
 * 应用壳固定文案与元数据（写死；不需要多语言）。
 * 四周壳子使用；中间内容区不读此处布局字段。
 */
export const appShellContent = {
  /** 窗口标题 / 产品短名 */
  windowTitle: 'Miao',
  /** 顶栏 cap 中间文字 */
  title: 'Miao 工具箱',
  /** 左侧 logo 下方欢迎语 */
  welcomeLine: '欢迎使用 Miao！',
  /** 作者显示名 */
  author: '程序喵',
  /** 标签（写死中文） */
  authorLabel: '作者',
  versionLabel: '版本号',
  releaseDateLabel: '发布日期',
  emailLabel: '邮箱',
  /** 联系邮箱 */
  email: '455855199@qq.com',
  /** 发布日期（展示用） */
  releaseDate: '2026-07-11',
  /** 宿主尚未返回版本时的回退 */
  fallbackVersion: '0.1.1',
} as const
