<script setup lang="ts">
/**
 * pnpm 工作区：梯形 Tab + 上区操作 + 下区共用进度/输出。
 * 取消任务挂到父级 tool-overview「终止」。
 * 逻辑见 voltaShared；本页仅保留工具文案与模板，便于日后单独演进。
 */
import { computed } from 'vue'
import JobConsole from '@kernel/components/JobConsole.vue'
import RegionLock from '@kernel/components/RegionLock.vue'
import { useVoltaPackagePage } from '../voltaShared/useVoltaPackagePage'
import '../voltaShared/voltaPackageWorkspace.css'

const TOOL_ID = 'pnpm'
const DISPLAY_NAME = 'pnpm'

const props = defineProps<{
  /** 嵌在一级页 tool-workspace 时为 true。 */
  embedded?: boolean
}>()

const {
  displayName,
  tabs,
  tab,
  versions,
  selected,
  defaultPick,
  specifyVersion,
  projectPath,
  projectCanPin,
  filter,
  loading,
  error,
  conflicts,
  voltaAvailable,
  listForTab,
  selectedList,
  versionSkeletonRows,
  bindVerListEl,
  outputEntries,
  progress,
  statusText,
  busy,
  selectTool,
  projectPinHint,
  canRunSpecify,
  selectTab,
  runBatchInstall,
  pickProjectDir,
  runSpecifyPin,
  runSetDefault,
  runBatchUninstall,
  installVoltaTool,
} = useVoltaPackagePage({
  toolId: TOOL_ID,
  displayName: DISPLAY_NAME,
  embedded: () => !!props.embedded,
  silentCacheTaskId: 'cache.versions.pnpm',
})

const listAria = computed(() => `${displayName} 版本列表`)
const installedListAria = computed(() => `已安装 ${displayName} 版本`)
const tablistAria = computed(() => `${displayName} 功能`)
</script>

<template>
  <section class="volta-page" :class="{ embedded: props.embedded }">
    <p v-if="!voltaAvailable" class="prereq-banner">
      未安装 Volta。请先安装后再管理 {{ displayName }} 版本。
      <span class="prereq-actions">
        <button type="button" class="btn" :disabled="busy" @click="installVoltaTool">
          {{ selectTool ? '前往 Volta' : '安装 Volta' }}
        </button>
      </span>
    </p>
    <p v-else-if="conflicts.length" class="banner-warn">
      检测到可能冲突的版本管理器：{{ conflicts.join('、') }}。建议统一使用 Volta。
    </p>
    <p v-if="error" class="banner-err">{{ error }}</p>

    <template v-if="voltaAvailable">
      <RegionLock :active="busy" title="任务进行中，请先终止">
        <div class="folder-tabs" role="tablist" :aria-label="tablistAria">
          <button
            v-for="(t, i) in tabs"
            :key="t.id"
            type="button"
            role="tab"
            class="folder-tab"
            :class="{ active: tab === t.id }"
            :style="{ zIndex: tab === t.id ? tabs.length + 1 : tabs.length - i }"
            :aria-selected="tab === t.id"
            :tabindex="busy ? -1 : undefined"
            @click="selectTab(t.id)"
          >
            <span class="folder-tab-label">{{ t.label }}</span>
          </button>
        </div>
      </RegionLock>

      <div class="folder-body">
        <div class="tool-stack" :class="{ 'is-job-locked': busy }">
          <div class="tool-ops">
            <div
              v-if="busy"
              class="tool-ops-lock"
              title="任务进行中，请先终止"
              aria-hidden="true"
            />
          <!-- 批量安装 -->
          <template v-if="tab === 'batch-install'">
            <div class="ver-head">
              <input
                v-model="filter"
                class="search"
                type="search"
                placeholder="过滤版本…"
                :aria-label="`过滤版本，共 ${listForTab.length} 项`"
              />
              <button
                type="button"
                class="btn btn-install"
                :disabled="busy || loading || !selectedList.length"
                :title="!selectedList.length ? '请先勾选要安装的版本' : '安装所选版本'"
                @click="runBatchInstall"
              >
                安装
              </button>
            </div>
            <ul
              :ref="bindVerListEl"
              class="ver-list ver-list--install"
              :class="{ 'ver-list--loading': loading && !versions.length }"
              :aria-busy="loading"
              :aria-label="listAria"
            >
              <template v-if="loading && !versions.length">
                <li
                  v-for="n in versionSkeletonRows"
                  :key="'vsk-' + n"
                  class="ver-row is-skel"
                  aria-hidden="true"
                >
                  <div class="ver-row-label">
                    <span class="ver-lead">
                      <span class="ver-skel-swatch ver-skel-swatch--check" />
                    </span>
                    <span class="ver-skel-swatch ver-skel-swatch--ver" />
                    <span class="ver-skel-swatch ver-skel-swatch--tag" />
                  </div>
                </li>
              </template>
              <template v-else>
                <li
                  v-for="v in listForTab"
                  :key="v.version"
                  class="ver-row"
                  :class="{ 'is-checked': selected[v.version] }"
                >
                  <label class="ver-row-label">
                    <span class="ver-lead">
                      <input
                        v-model="selected[v.version]"
                        class="ver-check"
                        type="checkbox"
                        :disabled="busy"
                      />
                    </span>
                    <span class="ver-num">{{ v.version }}</span>
                    <span v-if="v.lts" class="tag">LTS · {{ v.lts }}</span>
                  </label>
                </li>
                <li v-if="!listForTab.length && !loading" class="empty-hint">无匹配版本</li>
              </template>
            </ul>
          </template>

          <!-- 指定版本 -->
          <template v-else-if="tab === 'specify'">
            <div class="ver-project-row">
              <div class="ver-project">
                <div class="ver-project-main">
                  <span class="ver-project-label">当前目录</span>
                  <span
                    class="ver-project-path"
                    :class="{ empty: !projectPath }"
                    :title="projectPath || undefined"
                  >
                    {{ projectPath || '未选择' }}
                  </span>
                </div>
                <button
                  type="button"
                  class="btn btn-install"
                  :disabled="busy"
                  title="选择含 package.json 的项目目录"
                  @click="pickProjectDir"
                >
                  选择
                </button>
              </div>
              <p
                class="ver-project-hint"
                :class="{
                  ok: projectCanPin,
                  bad: !!projectPath && !projectCanPin,
                }"
              >
                {{ projectPinHint }}
              </p>
            </div>
            <div class="ver-head">
              <input
                v-model="filter"
                class="search"
                type="search"
                placeholder="过滤版本…"
                :aria-label="`过滤版本，共 ${listForTab.length} 项`"
              />
              <button
                type="button"
                class="btn btn-install"
                :disabled="!canRunSpecify"
                :title="
                  !projectCanPin
                    ? '请先选择有效项目目录'
                    : !specifyVersion
                      ? '请先选择版本'
                      : 'Pin 所选版本到项目'
                "
                @click="runSpecifyPin"
              >
                指定
              </button>
            </div>
            <ul
              class="ver-list ver-list--install"
              :class="{ 'ver-list--loading': loading && !versions.length }"
              :aria-busy="loading"
              :aria-label="listAria"
            >
              <li
                v-for="v in listForTab"
                :key="v.version"
                class="ver-row"
                :class="{
                  'is-checked': specifyVersion === v.version,
                  'is-default': v.isDefault,
                  'is-installed': v.installed && !v.isDefault,
                }"
              >
                <label class="ver-row-label">
                  <span class="ver-lead">
                    <input
                      v-model="specifyVersion"
                      class="ver-radio"
                      type="radio"
                      :name="TOOL_ID + '-specify'"
                      :value="v.version"
                      :disabled="busy || !projectCanPin"
                    />
                  </span>
                  <span class="ver-num">{{ v.version }}</span>
                  <span v-if="v.lts" class="tag">LTS · {{ v.lts }}</span>
                </label>
              </li>
              <li v-if="!listForTab.length && !loading" class="empty-hint">无匹配版本</li>
            </ul>
          </template>

          <!-- 设置默认 -->
          <template v-else-if="tab === 'set-default'">
            <div class="ver-head">
              <input
                v-model="filter"
                class="search"
                type="search"
                placeholder="过滤版本…"
                :aria-label="`过滤版本，共 ${listForTab.length} 项`"
              />
              <button
                type="button"
                class="btn btn-install"
                :disabled="busy || loading || !defaultPick"
                :title="!defaultPick ? '请先选择版本' : '设为默认'"
                @click="runSetDefault"
              >
                设置
              </button>
            </div>
            <ul
              class="ver-list ver-list--install"
              :class="{ 'ver-list--loading': loading && !versions.length }"
              :aria-busy="loading"
              :aria-label="listAria"
            >
              <li
                v-for="v in listForTab"
                :key="v.version"
                class="ver-row"
                :class="{
                  'is-checked': defaultPick === v.version,
                  'is-default': v.isDefault,
                  'is-installed': v.installed && !v.isDefault,
                }"
              >
                <label class="ver-row-label">
                  <span class="ver-lead">
                    <input
                      v-model="defaultPick"
                      class="ver-radio"
                      type="radio"
                      :name="TOOL_ID + '-default'"
                      :value="v.version"
                      :disabled="busy"
                    />
                  </span>
                  <span class="ver-num">{{ v.version }}</span>
                  <span v-if="v.lts" class="tag">LTS · {{ v.lts }}</span>
                </label>
              </li>
              <li v-if="!listForTab.length && !loading" class="empty-hint">无匹配版本</li>
            </ul>
          </template>

          <!-- 批量卸载 -->
          <template v-else-if="tab === 'batch-uninstall'">
            <div class="ver-head">
              <input
                v-model="filter"
                class="search"
                type="search"
                placeholder="过滤版本…"
                :aria-label="`过滤版本，共 ${listForTab.length} 项`"
              />
              <button
                type="button"
                class="btn btn-install"
                :disabled="busy || loading || !selectedList.length"
                :title="!selectedList.length ? '请先勾选要卸载的版本' : '卸载所选版本'"
                @click="runBatchUninstall"
              >
                卸载
              </button>
            </div>
            <ul
              class="ver-list ver-list--install"
              :class="{ 'ver-list--loading': loading && !versions.length }"
              :aria-busy="loading"
              :aria-label="installedListAria"
            >
              <li
                v-for="v in listForTab"
                :key="v.version"
                class="ver-row"
                :class="{
                  'is-checked': selected[v.version],
                  'is-default': v.isDefault,
                }"
              >
                <label class="ver-row-label">
                  <span class="ver-lead">
                    <input
                      v-model="selected[v.version]"
                      class="ver-check"
                      type="checkbox"
                      :disabled="busy"
                    />
                  </span>
                  <span class="ver-num">{{ v.version }}</span>
                  <span v-if="v.lts" class="tag">LTS · {{ v.lts }}</span>
                </label>
              </li>
              <li v-if="!listForTab.length && !loading" class="empty-hint">暂无已安装版本</li>
            </ul>
          </template>
          </div>

          <JobConsole
            class="tool-console"
            always-show
            :progress="progress"
            :status-text="statusText"
            :entries="outputEntries"
            :busy="busy"
            placeholder="执行操作后在此显示输出…"
          />
        </div>
      </div>
    </template>
  </section>
</template>