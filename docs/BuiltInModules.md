# 内置模块参考

GlyphBar 包含 6 个内置模块，随 App 编译，`trustLevel` 为 `.bundled`。它们遵循 `TypedModuleContribution` 协议，使用泛型 `@ViewBuilder` 面板。

## 总览

| 模块 | ID | 功能简述 | 优先级 | 刷新策略 | 所需权限 |
|------|-----|---------|--------|---------|---------|
| ClockModule | `clock` | 时钟显示与世界时钟轮换 | 50 | manual | pasteboard |
| CounterModule | `counter` | 计数器状态管理 | 0 | manual | — |
| DeepSeekModule | `deepseek` | API 用量追踪 | 100 | interval(300s) | openExternalURLs, localFiles, appGroupStorage |
| NotesQuickModule | `notesQuick` | 快速备忘录 | 0 | manual | — |
| SystemPulseModule | `systemPulse` | 系统指标监控 | 0 | interval(5s) | systemMetrics |
| NetworkMockModule | `networkMock` | 网络状态监控 | 0 | interval(30s) | — |

## ClockModule

**功能**：显示当前时间，支持多个世界时钟轮换展示、24 小时制切换、秒显示切换、时间戳复制。

| 属性 | 值 |
|------|-----|
| ID | `clock` |
| capabilities | `.statusItem` `.panel` `.widgets` `.actions` `.deepLinks` |
| permissions | `.pasteboard` |
| refreshPolicy | `.manual` |
| priority | `50` |

### 动作

| 动作 ID | 标题 | 功能 |
|---------|------|------|
| `copyTimestamp` | Copy Timestamp | 复制当前时间戳到剪贴板 |
| `toggleFormat` | Toggle Format | 切换 12/24 小时制 |

### Command 词汇

| 动作 ID | Payload | 功能 |
|---------|---------|------|
| `setFormat24h` | `text: "true"/"false"` | 设置 24 小时制 |
| `setShowSeconds` | `text: "true"/"false"` | 设置秒显示 |
| `setWorldTimezones` | `data: [String] JSON` | 设置世界时钟列表 |

### StatusCandidate 行为

- 提交 `.primary` 角色：当前时区时间
- 提交多个 `.rotation` 角色：各世界时钟标签，参与菜单栏轮换
- `interruptPolicy`：`.normal`
- `trustLevel`：`.bundled`

### 展示 Tick

Clock 的秒级更新**不走 refresh**，而是通过 `PresentationTickable` 协议的 `presentationTick()` 方法更新。refresh 仅在时区或格式变更时触发。

### 存储方式

- 时钟状态（格式、秒显示、世界时钟）：`ModuleSettingsNamespace.set(ClockState.self, forKey: "moduleState")`

---

## CounterModule

**功能**：可配置步长和边界的计数器，支持递增、递减、重置操作，状态持久化。

| 属性 | 值 |
|------|-----|
| ID | `counter` |
| capabilities | `.statusItem` `.panel` `.widgets` `.actions` `.cachedState` `.deepLinks` |
| permissions | — |
| refreshPolicy | `.manual` |
| priority | `0` |

### 动作

| 动作 ID | 标题 | Role | 功能 |
|---------|------|------|------|
| `increment` | Increment | standard | 计数 +stepSize |
| `decrement` | Decrement | standard | 计数 -stepSize |
| `reset` | Reset | destructive | 重置为 0 |

### Command 词汇

| 动作 ID | Payload | 功能 |
|---------|---------|------|
| `setStepSize` | `text: "\(step)"` | 设置步长 |
| `setBounds` | `data: CounterBounds JSON` | 设置最小/最大边界 |

### 存储方式

- 计数器状态（count、stepSize、minValue、maxValue、lastModified）：`ModuleSettingsNamespace.set(CounterState.self, forKey: "moduleState")`

---

## DeepSeekModule

**功能**：追踪 DeepSeek API 使用量，支持 API Key 配置、用量查询、CSV 数据导入导出。是 GlyphBar 中最复杂的内置模块。

| 属性 | 值 |
|------|-----|
| ID | `deepseek` |
| capabilities | `.statusItem` `.panel` `.widgets` `.actions` `.cachedState` `.deepLinks` |
| permissions | `.openExternalURLs` `.localFiles` `.appGroupStorage` |
| refreshPolicy | `.interval(seconds: 300)` (5 分钟) |
| priority | `100` |

### 动作

| 动作 ID | 标题 | Role | 功能 |
|---------|------|------|------|
| `refresh` | Refresh | refresh | 触发手动刷新 |

### Command 词汇

| 动作 ID | Payload | 功能 |
|---------|---------|------|
| `setApiKey` | `text: apiKey` | 设置 API Key（通过 `ModuleSecretStore`） |
| `clearApiKey` | 无 | 清除 API Key |
| `setPlatformCookie` | `text: cookie` | 设置平台 Cookie |
| `clearPlatformCookie` | 无 | 清除 Cookie 和 Token |
| `setRawUserToken` | `text: token` | 设置原始用户 Token |
| `importUsageItems` | `data: [ParsedUsageItem] JSON` | 导入用量数据 |
| `fetchUsage` | 无 | 获取用量导出 |

### 能力使用

- `NetworkCapability`：发起 API 请求查询用量
- `ModuleSecretStore`：存储 API Key、平台 Cookie、用户 Token（Keychain 后端）
- `ModuleCacheNamespace`：缓存用量数据
- `ModuleSettingsNamespace`：存储模块配置
- `FileImportCapability`：导入 CSV 用量数据

### 健康状态

- `.misconfigured(.missingSecret("deepseek.apiKey"))`：未配置 API Key
- `.degraded(.networkError(...))`：网络请求失败，展示缓存数据
- `.degraded(.authFailed)`：API Key 无效

### StatusCandidate 行为

- 提交 `.primary` 角色：当前用量信息
- 提交 `.rotation` 角色：余额信息
- `priority: 100`（高于其他默认模块）
- `interruptPolicy`：`.normal`
- `trustLevel`：`.bundled`

### Widget

DeepSeek 当前未声明 Widget 描述符（`widgets: []`）。未来可通过在 manifest 中添加 `ModuleWidgetDescriptor` 启用 Widget 支持。

---

## NotesQuickModule

**功能**：快速备忘录，支持文本记录、置顶、完成标记、内联编辑和剪贴板复制。

| 属性 | 值 |
|------|-----|
| ID | `notesQuick` |
| capabilities | `.statusItem` `.panel` `.widgets` `.actions` `.cachedState` `.deepLinks` |
| permissions | — |
| refreshPolicy | `.manual` |
| priority | `0` |

### 动作

| 动作 ID | 标题 | Role | 功能 |
|---------|------|------|------|
| `addNote` | Add Note | standard | 添加新笔记 |
| `copyNote` | Copy Note | standard | 复制笔记内容到剪贴板 |
| `clearCompleted` | Clear Done | destructive | 清除所有已完成笔记 |

### Command 词汇

| 动作 ID | Payload | 功能 |
|---------|---------|------|
| `addNote` | `text: 笔记文本` | 添加新笔记 |
| `editNote` | `text: UUID, data: [title, content]` | 编辑笔记内容 |
| `toggleComplete` | `text: UUID` | 切换完成状态 |
| `togglePin` | `text: UUID` | 切换置顶 |
| `deleteNote` | `text: UUID` | 删除笔记 |
| `copyNote` | `text: UUID` | 复制到剪贴板（`.copyToClipboard` Effect） |
| `clearCompleted` | 无 | 清除已完成 |

所有面板操作通过 `context.dispatch(.userAction)` 走 Command/Effect 管线。

### 面板交互

- **List + Section** 原生列表，置顶/最近/已完成三个分组
- **Toggle(.checkbox)** 原生复选框切换完成状态
- **.contextMenu** 右键菜单提供置顶、复制、编辑、删除
- **.searchable** 系统搜索栏
- 内联编辑：点击行或右键"Edit"进入编辑态
- 完成笔记整体 opacity 降低 + 删除线

### 存储方式

- 备忘数据：`ModuleCacheNamespace.saveDomainState()` 域状态持久化（App Group UserDefaults）
- 数据格式：`[Note]` Codable JSON，通过 `NotesQuickStateStore` 编解码

---

## SystemPulseModule

**功能**：监控 CPU、内存、磁盘使用率，异常时发出告警。

| 属性 | 值 |
|------|-----|
| ID | `systemPulse` |
| capabilities | `.statusItem` `.panel` `.widgets` `.actions` `.deepLinks` |
| permissions | `.systemMetrics` |
| refreshPolicy | `.interval(seconds: 5)` |
| priority | `0` |

### 动作

| 动作 ID | 标题 | Role | 功能 |
|---------|------|------|------|
| `refresh` | Refresh | refresh | 触发手动刷新 |

### 能力使用

- `SystemMetricsCapability`：读取 CPU、内存、磁盘使用率（收口 Mach `host_statistics`、`ProcessInfo`、`URL.resourceValues` 等底层调用）

### StatusCandidate 行为

- 所有候选使用 `.alert` 语义角色 + `.preempt` 抢占策略
- 告警阈值通过 `HysteresisTracker` 防闪烁
- `trustLevel`：`.bundled`

### 告警行为

当 CPU/内存/磁盘使用率超过阈值时：
1. `statusCandidates()` 返回 `.alert` 角色 + `.preempt` 策略的候选
2. `PresentationArbiter` 立即抢占菜单栏展示
3. 使用率回落到安全范围后，告警候选消失，恢复正常展示

---

## NetworkMockModule

**功能**：监控网络状态，展示网络接口信息和本地 IP。

| 属性 | 值 |
|------|-----|
| ID | `networkMock` |
| capabilities | `.statusItem` `.panel` `.widgets` `.actions` `.cachedState` `.deepLinks` |
| permissions | — |
| refreshPolicy | `.interval(seconds: 30)` |
| priority | `0` |

### 动作

| 动作 ID | 标题 | Role | 功能 |
|---------|------|------|------|
| `retry` | Refresh | refresh | 触发手动刷新 |
| `copyIP` | Copy IP | standard | 复制本地 IP 地址到剪贴板 |

### StatusCandidate 行为

- 所有候选使用 `.alert` 语义角色 + `.preempt` 抢占策略
- `trustLevel`：`.bundled`

### 特殊说明

NetworkMockModule 通过 `NetworkStatusProvider` 使用 `NWPathMonitor` 和 POSIX `getifaddrs` 获取网络状态。这些平台调用被封装在 Provider 中，模块本身不直接调用。

---

## 内置模块的共同模式

### Command 处理

所有内置模块的 `handle(command:capabilities:bridge:)` 遵循相同模式：

```swift
func handle(command: Command, capabilities: GrantedCapabilities, bridge: ModuleBridge) async -> DomainTransition {
    switch command {
    case .refresh(let reason):
        let envelope = ProjectionBuilder.buildEnvelope(from: buildSnapshot())
        return DomainTransition(
            effects: [.publishSnapshot(envelope)],
            health: .healthy,
            refreshProjection: true
        )

    case .userAction(let actionID, let payload):
        switch actionID {
        case "copyStatus":
            return DomainTransition(
                effects: [.copyToClipboard(statusText)],
                health: nil,
                refreshProjection: false
            )
        default:
            return .empty
        }

    default:
        return .empty
    }
}
```

### 优雅降级

所有内置模块在 `GrantedCapabilities` 中的能力为 `nil` 时不会崩溃：

```swift
case .refresh:
    if let network = capabilities.network {
        // 有网络能力，正常请求
    } else {
        // 无网络能力，返回降级状态
        return DomainTransition(
            effects: [.publishSnapshot(staleEnvelope)],
            health: .degraded(.permissionDenied(.network)),
            refreshProjection: true
        )
    }
```

### 面板实现

内置模块实现 `TypedModuleContribution`，返回具体的 SwiftUI View。面板通过 `PanelHostContext.dispatch` 将用户操作转为 `Command`，避免面板直接调用模块方法。SwiftUI `Binding` 的 `set` 闭包同样 dispatch command。

### 状态持久化

所有模块通过 `ModuleSettingsNamespace` 或 `ModuleCacheNamespace` 持久化状态，不使用 `UserDefaults.standard`。

## 相关文档

- [架构总览](Architecture.md) — 微内核架构和模块契约
- [原生模块开发](NativeModuleDevelopment.md) — 如何开发内置模块
- [Command/Effect 管线](CommandEffectPipeline.md) — Command 和 Effect 的详细参考
- [能力安全体系](Capabilities.md) — 各模块使用的能力详解
- [状态栏仲裁](PresentationArbiter.md) — StatusCandidate 如何参与仲裁
