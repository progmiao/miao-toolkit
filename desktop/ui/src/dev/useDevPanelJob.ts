/**
 * 开发工具 panel 工作区取 Job API：嵌在一级页时用父级共用控制台，独立打开时自建。
 */
import { inject } from 'vue'
import {
  useJobConsole,
  type JobConsoleApi,
  type UseJobConsoleOptions,
} from '@kernel/composables/useJobConsole'
import { DEV_JOB_KEY } from './devPanelContext'

export type DevPanelJobApi = JobConsoleApi & {
  /** 是否使用父级共用控制台（此时勿再 consumeJobMessage，避免日志重复）。 */
  isShared: boolean
}

/**
 * @param options - 仅在无父级共用控制台时生效（独立路由兜底）
 */
export function useDevPanelJob(options: UseJobConsoleOptions = {}): DevPanelJobApi {
  const shared = inject(DEV_JOB_KEY, null)
  if (shared) return { ...shared, isShared: true }
  return { ...useJobConsole(options), isShared: false }
}
