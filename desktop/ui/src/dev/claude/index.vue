<script setup lang="ts">
/**
 * Claude Code 控制台：安装生命周期、初始化、API / 代理、精选插件。
 */
import { onMounted, onUnmounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import JobConsole from '@kernel/components/JobConsole.vue'
import { post, subscribe } from '@kernel/bridge/bus'
import { showToast } from '@kernel/bridge/toast'
import { useJobConsole } from '@kernel/composables/useJobConsole'
import { useShellTitle } from '@kernel/composables/useShellTitle'

useShellTitle('Claude Code')

type Status = {
  installed: boolean
  version?: string | null
  wingetManaged: boolean
  settingsExists: boolean
  apiMode?: string | null
  proxyMode?: string | null
  hasSecrets: boolean
}

type Secrets = {
  apiMode?: string | null
  apiKeyMasked?: string | null
  baseUrl?: string | null
  authTokenMasked?: string | null
  proxyMode?: string | null
  httpProxy?: string | null
  httpsProxy?: string | null
}

type Plugin = { id: string; label: string; featured: boolean }

const tab = ref<'lifecycle' | 'api' | 'proxy' | 'plugins'>('lifecycle')
const status = ref<Status | null>(null)
const secrets = ref<Secrets | null>(null)
const plugins = ref<Plugin[]>([])
const selectedPlugins = ref<Record<string, boolean>>({})
const customPlugin = ref('')

const apiMode = ref<'official' | 'custom' | 'clear'>('official')
const apiKey = ref('')
const baseUrl = ref('')
const authToken = ref('')
const httpProxy = ref('')
const httpsProxy = ref('')

const {
  logs,
  consoleLines,
  progress,
  busy,
  appendStatus,
  consumeJobMessage,
  cancel,
} = useJobConsole({
  onFinished: () => refresh(),
  formatStarted: (msg) => `开始：${msg.action ?? '任务'}`,
  formatFinished: (msg) => (msg.ok ? '完成' : `失败 ${msg.detail ?? ''}`),
})

let unsub: (() => void) | undefined

function refresh() {
  post({ type: 'claude.status' })
}

onMounted(() => {
  unsub = subscribe((msg) => {
    if (msg.type === 'claude.status') {
      status.value = msg.status as Status
      secrets.value = msg.secrets as Secrets
      plugins.value = (msg.plugins as Plugin[]) ?? []
      for (const p of plugins.value) {
        if (selectedPlugins.value[p.id] === undefined) selectedPlugins.value[p.id] = false
      }
      if (secrets.value?.httpProxy) httpProxy.value = secrets.value.httpProxy
      if (secrets.value?.httpsProxy) httpsProxy.value = secrets.value.httpsProxy
      if (secrets.value?.baseUrl) baseUrl.value = secrets.value.baseUrl
      return
    }
    if (msg.type === 'claude.saved') {
      showToast(`已保存（${msg.kind}）`, { kind: 'ok' })
      return
    }
    consumeJobMessage(msg)
  })
  refresh()
})

onUnmounted(() => unsub?.())

function runJob(action: string, extra?: Record<string, unknown>) {
  const jobId = crypto.randomUUID().replaceAll('-', '')
  post({ type: 'run-job', jobId, toolId: 'claude-code', action, ...extra })
}

function saveApi() {
  post({
    type: 'claude.set-api',
    mode: apiMode.value,
    apiKey: apiKey.value,
    baseUrl: baseUrl.value,
    authToken: authToken.value,
  })
}

function saveProxy(mode: 'set' | 'clear') {
  post({
    type: 'claude.set-proxy',
    mode,
    httpProxy: httpProxy.value,
    httpsProxy: httpsProxy.value,
  })
}

function pluginIds(): string[] {
  const ids = plugins.value.filter((p) => selectedPlugins.value[p.id]).map((p) => p.id)
  if (customPlugin.value.trim()) ids.push(customPlugin.value.trim())
  return [...new Set(ids)]
}

function installPlugins() {
  const ids = pluginIds()
  if (!ids.length) {
    appendStatus('请勾选或填写插件 id')
    return
  }
  runJob('plugin-install', { versions: ids, plugins: ids.join(',') })
}

function uninstallPlugins() {
  const ids = pluginIds()
  if (!ids.length) {
    appendStatus('请勾选或填写插件 id')
    return
  }
  runJob('plugin-uninstall', { versions: ids, plugins: ids.join(',') })
}
</script>

<template>
  <section class="page page--scroll">
    <header class="page-head row">
      <div>
        <p class="crumb">
          <RouterLink to="/dev">开发工具</RouterLink>
          <span>/</span>
          <span>Claude Code</span>
        </p>
        <p>安装 CLI → 初始化 → 配置 API / 代理 → 安装插件。密钥保存在本机 Miao 目录并合并到 ~/.claude/settings.json。</p>
      </div>
      <div class="actions">
        <button type="button" class="btn secondary" @click="refresh">刷新状态</button>
        <button type="button" class="btn danger" :disabled="!busy" @click="cancel">取消任务</button>
      </div>
    </header>

    <div class="status-bar hud-panel">
      <span class="tag" :class="status?.installed ? 'status-installed' : 'status-missing'">
        {{ status?.installed ? '已安装' : '未安装' }}
      </span>
      <span v-if="status?.version" class="mono">{{ status.version }}</span>
      <span class="tag">{{ status?.wingetManaged ? 'WinGet 管理' : '非 WinGet / 未知' }}</span>
      <span class="tag">API {{ status?.apiMode || '—' }}</span>
      <span class="tag">代理 {{ status?.proxyMode || '—' }}</span>
    </div>

    <nav class="tabs">
      <button type="button" :class="{ active: tab === 'lifecycle' }" @click="tab = 'lifecycle'">生命周期</button>
      <button type="button" :class="{ active: tab === 'api' }" @click="tab = 'api'">API</button>
      <button type="button" :class="{ active: tab === 'proxy' }" @click="tab = 'proxy'">代理</button>
      <button type="button" :class="{ active: tab === 'plugins' }" @click="tab = 'plugins'">插件</button>
    </nav>

    <div class="claude-layout">
      <div class="hud-panel main">
        <template v-if="tab === 'lifecycle'">
          <h2 class="sec">推荐流程</h2>
          <ol class="steps">
            <li>安装 / 更新 CLI（WinGet Anthropic.ClaudeCode）</li>
            <li>初始化（DISABLE_LOGIN_COMMAND + 预设 marketplace）</li>
            <li>配置 API 与可选代理</li>
            <li>安装精选插件</li>
          </ol>
          <div class="actions">
            <button type="button" class="btn" :disabled="busy" @click="runJob('install')">安装 / 更新</button>
            <button type="button" class="btn secondary" :disabled="busy || !status?.installed" @click="runJob('init')">
              初始化
            </button>
            <button
              type="button"
              class="btn secondary"
              :disabled="busy || !status?.wingetManaged"
              @click="runJob('uninstall')"
            >
              卸载（仅 WinGet）
            </button>
          </div>
        </template>

        <template v-else-if="tab === 'api'">
          <h2 class="sec">API 访问</h2>
          <p class="hint">
            当前模式：{{ secrets?.apiMode || '未配置' }}
            <template v-if="secrets?.apiKeyMasked"> · Key {{ secrets.apiKeyMasked }}</template>
          </p>
          <div class="form">
            <label>
              模式
              <select v-model="apiMode">
                <option value="official">官方 API Key</option>
                <option value="custom">自定义 Base URL + Token</option>
                <option value="clear">清除</option>
              </select>
            </label>
            <label v-if="apiMode === 'official'">
              ANTHROPIC_API_KEY
              <input v-model="apiKey" type="password" autocomplete="off" placeholder="sk-ant-…" />
            </label>
            <template v-if="apiMode === 'custom'">
              <label>
                Base URL
                <input v-model="baseUrl" type="url" placeholder="https://…" />
              </label>
              <label>
                Token
                <input v-model="authToken" type="password" autocomplete="off" />
              </label>
            </template>
            <button type="button" class="btn" @click="saveApi">保存并写入 settings</button>
          </div>
        </template>

        <template v-else-if="tab === 'proxy'">
          <h2 class="sec">HTTP(S) 代理</h2>
          <div class="form">
            <label>
              HTTP_PROXY
              <input v-model="httpProxy" placeholder="http://127.0.0.1:7890" />
            </label>
            <label>
              HTTPS_PROXY
              <input v-model="httpsProxy" placeholder="留空则同 HTTP" />
            </label>
            <div class="actions">
              <button type="button" class="btn" @click="saveProxy('set')">保存代理</button>
              <button type="button" class="btn secondary" @click="saveProxy('clear')">清除代理</button>
            </div>
          </div>
        </template>

        <template v-else>
          <h2 class="sec">精选插件</h2>
          <p class="hint">需先完成 CLI 安装与初始化（marketplace）。</p>
          <ul class="plugin-list">
            <li v-for="p in plugins" :key="p.id">
              <label>
                <input v-model="selectedPlugins[p.id]" type="checkbox" />
                <span class="mono">{{ p.id }}</span>
                <span v-if="p.featured" class="tag">精选</span>
              </label>
            </li>
          </ul>
          <label class="custom">
            自定义插件 id
            <input v-model="customPlugin" placeholder="name@marketplace" />
          </label>
          <div class="actions">
            <button type="button" class="btn" :disabled="busy" @click="installPlugins">安装所选</button>
            <button type="button" class="btn secondary" :disabled="busy" @click="uninstallPlugins">
              卸载所选
            </button>
          </div>
        </template>
      </div>

      <aside class="job-panel">
        <JobConsole
          :progress="progress"
          :logs="logs"
          :console-lines="consoleLines"
          :busy="busy"
          placeholder="任务日志…"
        />
      </aside>
    </div>
  </section>
</template>

<style scoped>
.crumb {
  display: flex;
  gap: 0.4rem;
  margin: 0 0 0.35rem;
  font-size: 0.8rem;
  color: var(--muted);
  letter-spacing: 0.06em;
  text-transform: uppercase;
  font-family: var(--font-display);
}
.crumb a {
  color: var(--accent);
  text-decoration: none;
}
.status-bar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  align-items: center;
  margin-bottom: 0.85rem;
}
.tabs {
  display: flex;
  gap: 0.35rem;
  margin-bottom: 0.85rem;
}
.tabs button {
  border: 1px solid var(--line);
  background: var(--panel);
  color: var(--ink);
  padding: 0.4rem 0.85rem;
  border-radius: 0.4rem;
  cursor: pointer;
  font-weight: 600;
}
.tabs button.active {
  border-color: var(--accent);
  box-shadow: inset 0 -2px 0 var(--accent);
  color: var(--accent);
}
.claude-layout {
  display: grid;
  grid-template-columns: 1.1fr 0.9fr;
  gap: 1rem;
  min-height: 400px;
}
.sec {
  margin: 0 0 0.5rem;
  font-family: var(--font-display);
  font-size: 0.9rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
.hint {
  color: var(--muted);
  font-size: 0.9rem;
  margin: 0 0 0.75rem;
}
.steps {
  margin: 0 0 1rem;
  padding-left: 1.2rem;
  color: var(--muted);
  line-height: 1.6;
}
.form {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}
.form label,
.custom {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  font-size: 0.85rem;
  color: var(--muted);
}
.form input,
.form select,
.custom input {
  padding: 0.45rem 0.55rem;
  border: 1px solid var(--line);
  border-radius: 0.4rem;
  background: var(--panel-strong);
  color: var(--ink);
  font-family: var(--font-mono);
}
.plugin-list {
  list-style: none;
  margin: 0 0 0.75rem;
  padding: 0;
}
.plugin-list li label {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  padding: 0.4rem 0;
  cursor: pointer;
}
@media (max-width: 900px) {
  .claude-layout {
    grid-template-columns: 1fr;
  }
}
</style>
