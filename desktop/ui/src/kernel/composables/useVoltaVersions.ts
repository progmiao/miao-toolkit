/**
 * Volta 管理的包版本清单（node / pnpm / yarn）。
 * 只负责 `volta.list` / `volta.versions` 与勾选状态，不包含页面 Tab/布局。
 * Node 与 pnpm/yarn 各自页面独立，仅复用本数据层。
 */
import { computed, ref, type Ref } from 'vue'
import { post, type HostMessage, type VoltaVersion } from '@kernel/bridge/bus'

/** `useVoltaVersions` 选项。 */
export type UseVoltaVersionsOptions = {
  /** 工具 id：`node` | `pnpm` | `yarn` */
  toolId: string | Ref<string>
  /** 初始是否仅 LTS（Node 常用 true；pnpm/yarn 常用 false） */
  ltsOnlyDefault?: boolean
}

/**
 * 拉取并缓存 Volta 版本行，供各工具页自行渲染列表。
 * @param options - 工具 id 与 LTS 默认
 */
export function useVoltaVersions(options: UseVoltaVersionsOptions) {
  const versions = ref<VoltaVersion[]>([])
  const selected = ref<Record<string, boolean>>({})
  const ltsOnly = ref(options.ltsOnlyDefault ?? false)
  const filter = ref('')
  const loading = ref(false)
  const error = ref('')
  const conflicts = ref<string[]>([])
  const voltaAvailable = ref(true)

  function resolveToolId(): string {
    const t = options.toolId
    return typeof t === 'string' ? t : t.value
  }

  /**
   * 向宿主请求版本清单。
   * @param resetError - 是否清空 error（默认 true）
   */
  function requestList(resetError = true) {
    loading.value = true
    if (resetError) error.value = ''
    post({ type: 'volta.list', tool: resolveToolId(), ltsOnly: ltsOnly.value })
  }

  /**
   * 消费 `volta.versions`；其它消息返回 false。
   * @param msg - 总线消息
   * @returns 是否已处理
   */
  function consumeVersionsMessage(msg: HostMessage): boolean {
    if (msg.type !== 'volta.versions' || !Array.isArray(msg.items)) return false
    if (msg.tool && msg.tool !== resolveToolId()) return false
    loading.value = false
    versions.value = msg.items as VoltaVersion[]
    voltaAvailable.value = msg.voltaAvailable !== false
    conflicts.value = (msg.conflicts as string[]) ?? []
    for (const v of versions.value) {
      if (selected.value[v.version] === undefined) selected.value[v.version] = false
    }
    return true
  }

  /**
   * 按关键字过滤后的版本（不含「仅已装」等业务过滤，由页面自己做）。
   */
  const filteredByQuery = computed(() => {
    const q = filter.value.trim().toLowerCase()
    return versions.value.filter((v) => {
      if (!q) return true
      return v.version.includes(q) || (v.lts ?? '').toLowerCase().includes(q)
    })
  })

  /**
   * 全选 / 清空给定列表上的勾选。
   * @param list - 要操作的版本行
   * @param on - true 全选
   */
  function toggleAll(list: VoltaVersion[], on: boolean) {
    for (const v of list) selected.value[v.version] = on
  }

  /**
   * 记录宿主错误（列表加载失败时）。
   * @param message - 文案
   */
  function setError(message: string) {
    error.value = message
    loading.value = false
  }

  /** 切换工具或重进页时清空勾选与过滤。 */
  function resetSelection() {
    selected.value = {}
    filter.value = ''
  }

  return {
    versions,
    selected,
    ltsOnly,
    filter,
    loading,
    error,
    conflicts,
    voltaAvailable,
    filteredByQuery,
    requestList,
    consumeVersionsMessage,
    toggleAll,
    setError,
    resetSelection,
  }
}
