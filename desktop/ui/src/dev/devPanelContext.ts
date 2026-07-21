/**
 * 开发工具一级页与嵌入工作区之间的上下文。
 * - DEV_JOB_KEY：共用 JobConsole（概览区安装/更新/卸载与工作区任务同一输出）
 * - DEV_SELECT_TOOL_KEY：工作区内切换左侧选中工具（不再路由跳转）
 */
import type { InjectionKey } from 'vue'
import type { JobConsoleApi } from '@kernel/composables/useJobConsole'

/** 父页 provide 的 Job 控制台 API。 */
export const DEV_JOB_KEY: InjectionKey<JobConsoleApi> = Symbol('miao.devJobConsole')

/** 父页 provide：按工具 id 选中列表项。 */
export const DEV_SELECT_TOOL_KEY: InjectionKey<(toolId: string) => void> = Symbol(
  'miao.devSelectTool',
)

/** 工作区挂到概览区的额外操作（如刷新清单）。 */
export type DevOverviewExtra = {
  /** 刷新回调 */
  refresh?: () => void
  /** 按钮文案 */
  refreshLabel?: string
  /** 刷新中 */
  refreshing?: boolean
}

export const DEV_OVERVIEW_EXTRA_KEY: InjectionKey<
  import('vue').Ref<DevOverviewExtra | null>
> = Symbol('miao.devOverviewExtra')

/** 工作区是否自带 JobConsole（父级应隐藏底部共用控制台）。 */
export const DEV_WORKSPACE_OWNS_CONSOLE_KEY: InjectionKey<
  import('vue').Ref<boolean>
> = Symbol('miao.devWorkspaceOwnsConsole')
