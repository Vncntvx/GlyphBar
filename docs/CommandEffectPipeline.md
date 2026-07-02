# Command / Effect 管线

GlyphBar 的所有模块行为遵循**单向数据流**：外部刺激归一化为 `Command`，模块处理后返回 `DomainTransition`，其中包含的 `Effect` 由 `EffectExecutor` 统一执行。模块**永远不**直接调用平台 API。

## 设计原则

| 原则 | 含义 |
|------|------|
| 模块拥有领域状态，不拥有应用平台 | 模块不直接访问 `NSPasteboard`、`URLSession`、`NSWorkspace` 等 |
| 模块提出 Effects，不直接执行全局副作用 | 所有副作用通过 `Effect` 枚举声明 |
| 统一入口 | 所有模块行为通过 `handle(command:capabilities:bridge:)` 单一入口 |
| 无旁路 | 不允许模块绕过管线直接 publish snapshot 或修改 UI |

## Command — 统一输入词汇

每个外部刺激被归一化为 `Command` 枚举的一个 case：

```swift
enum Command: Sendable {
    case refresh(reason: RefreshReason)
    case userAction(actionID: String, payload: ActionPayload?)
    case settingsChanged
    case permissionChanged
    case appBecameActive
    case systemWake
    case networkChanged(reachable: Bool)
    case importData(URL)
    case clearCache
    case contributionTick
}
```

### Command 详细参考

| Command | 触发时机 | 携带参数 | 典型响应 |
|---------|----------|----------|----------|
| `.refresh(reason:)` | 手动刷新、定时调度、启动、深度链接、级联、网络恢复、面板打开 | `RefreshReason` | 产生新 snapshot 并发布 |
| `.userAction(actionID:payload:)` | 用户点击模块动作按钮 | 动作 ID + 可选载荷 | 执行对应动作（复制、打开 URL 等） |
| `.settingsChanged` | 用户修改模块设置 | 无 | 重新读取设置，可能刷新数据 |
| `.permissionChanged` | 权限授予或撤销 | 无 | 重新评估可用能力，可能降级 |
| `.appBecameActive` | App 回到前台 | 无 | 刷新过期数据 |
| `.systemWake` | 系统从睡眠恢复 | 无 | 批量恢复刷新 |
| `.networkChanged(reachable:)` | 网络可达性变化 | 是否可达 | 网络恢复时触发刷新；断网时标记降级 |
| `.importData(URL)` | 文件导入结果 | 导入文件 URL | 处理导入的数据 |
| `.clearCache` | 缓存清除请求 | 无 | 清除本地缓存 |
| `.contributionTick` | 面板展示 Tick（Clock 秒级更新） | 无 | 仅更新展示，不产生副作用 |

### RefreshReason

```swift
enum RefreshReason: Sendable {
    case manual          // 用户手动触发
    case scheduled       // 定时调度
    case launch          // App 启动
    case deepLink        // 深度链接触发
    case cascade         // 级联刷新（其他模块变化触发）
    case networkRestored // 网络恢复
    case panelOpened     // 面板打开
}
```

### ActionPayload

```swift
struct ActionPayload: Sendable {
    var text: String?
    var data: Data?
}
```

可选的动作载荷。`text` 用于简单字符串参数（如 API Key、布尔值），`data` 用于 Codable 编码的结构化数据。

## Effect — 统一输出词汇

所有模块副作用被表达为 `Effect` 枚举：

```swift
enum Effect: Sendable {
    case publishSnapshot(SnapshotEnvelope)
    case persistDomainState(Data)
    case copyToClipboard(String)
    case openURL(URL)
    case showNotice(String)
    case openModuleSettings
    case requestFileImport(allowedTypes: [String])
    case requestRefresh(reason: Command.RefreshReason)
    case scheduleLocal(Command, after: TimeInterval)
    case networkRequest(NetworkRequest)
}
```

### Effect 详细参考

| Effect | 副作用执行 | 使用场景 |
|--------|-----------|----------|
| `.publishSnapshot(SnapshotEnvelope)` | 写入 CacheStore + WidgetBridge + 回调 Runtime 更新 snapshot | 模块数据更新后发布到 Widget |
| `.persistDomainState(Data)` | 日志记录（完整接线待完成） | 保存模块的域状态数据 |
| `.copyToClipboard(String)` | `NSPasteboard.general.clearContents()` + `setString()` | 复制文本到剪贴板 |
| `.openURL(URL)` | `NSWorkspace.shared.open(url)` | 在浏览器中打开 URL |
| `.showNotice(String)` | 更新 runtime notice + 日志记录 | 向用户显示提示信息 |
| `.openModuleSettings` | `openSettingsAction?()` + `NSApp.activate()` | 跳转到模块设置 |
| `.requestFileImport(allowedTypes:)` | 日志记录（能力接线待完成） | 请求文件导入对话框 |
| `.requestRefresh(reason:)` | 通过 runtime 回调再次 dispatch refresh | 某些操作后需要立即刷新 |
| `.scheduleLocal(Command, after:)` | 通过 runtime 注入的 `SchedulerClock` 安排 command，可在 module disable/unload 时取消 | 定时自我触发 |
| `.networkRequest(NetworkRequest)` | 日志警告：建议使用 `NetworkCapability` 代替 | 兼容路径，新代码不应使用 |

> **注意**：`.networkRequest` 保留用于兼容，新代码应使用 `GrantedCapabilities.network` (`NetworkCapability`) 发起网络请求，这样可以利用能力授予机制进行权限控制。

## DomainTransition — 模块返回值

`handle(command:capabilities:bridge:)` 返回 `DomainTransition`：

```swift
struct DomainTransition: Sendable {
    var effects: [Effect]
    var health: ModuleHealth?
    var refreshProjection: Bool

    static let empty = DomainTransition(effects: [], health: nil, refreshProjection: false)
}
```

| 字段 | 类型 | 含义 |
|------|------|------|
| `effects` | `[Effect]` | 需要内核执行的副作用列表 |
| `health` | `ModuleHealth?` | 可选的健康状态更新 |
| `refreshProjection` | `Bool` | 是否需要重新调用 `buildProjection()` |

### 常见 DomainTransition 模式

**成功刷新**：
```swift
DomainTransition(
    effects: [.publishSnapshot(envelope)],
    health: .healthy,
    refreshProjection: true
)
```

**用户动作（复制到剪贴板）**：
```swift
DomainTransition(
    effects: [.copyToClipboard("已复制的文本"), .publishSnapshot(updatedEnvelope)],
    health: nil,
    refreshProjection: true
)
```

**优雅降级（缺少密钥）**：
```swift
DomainTransition(
    effects: [],
    health: .misconfigured(.missingSecret("apiKey")),
    refreshProjection: true
)
```

**忽略不相关的 Command**：
```swift
DomainTransition.empty
```

## ModuleBridge — Effect 提交通道

模块通过 `ModuleBridge` 协议提交 Effect：

```swift
@MainActor
protocol ModuleBridge: AnyObject {
    func submit(_ effects: [Effect])
    func submit(_ effect: Effect)
}
```

`ModuleBridge` 是 `GrantedCapabilities` 中**始终授予**的能力。模块在 `handle()` 内部可以通过 `bridge.submit()` 提交额外的 Effect，但通常建议通过 `DomainTransition.effects` 返回——`bridge.submit()` 主要用于面板等异步场景。

当前实现：

1. **KernelBridge**：轻量闭包实现，用于 `ModuleSupervisor` 中将 Effect 路由回 supervisor 的 `onEffects` 回调
2. **ModuleRuntime**：将 `onEffects` 接到 `EffectExecutor`，并为 refresh、scheduled local command、settings window、notice 等 runtime 行为提供注入回调

## EffectExecutor — 全局副作用出口

`EffectExecutor` 是**唯一**执行副作用的组件：

```swift
@MainActor
final class EffectExecutor {
    private let widgetBridge: WidgetDataBridge
    private let cacheStore: CacheStore
    private let logger: GlyphLogger
    var onSnapshotPublished: ((ModuleID, ModuleSnapshot) -> Void)?
    var onNotice: ((String) -> Void)?
    var requestRefreshAction: ((ModuleID, Command.RefreshReason) async -> Void)?
    var scheduleLocalAction: ((ModuleID, Command, TimeInterval) -> Void)?
    var openSettingsAction: (() -> Void)?

    func execute(_ effect: Effect, for moduleID: String) async
}
```

每个 `Effect` case 在 `EffectExecutor.execute()` 中映射到具体的平台调用：

| Effect | EffectExecutor 执行 |
|--------|-------------------|
| `.publishSnapshot(envelope)` | 构建 `ModuleSnapshot`、写入 `CacheStore`、发布到 `WidgetDataBridge`、回调 runtime 更新 snapshot |
| `.persistDomainState(data)` | 日志记录（完整接线待完成） |
| `.copyToClipboard(text)` | `NSPasteboard.general.clearContents()` + `setString()` |
| `.openURL(url)` | `NSWorkspace.shared.open(url)` |
| `.showNotice(message)` | 更新 runtime notice + 日志记录 |
| `.openModuleSettings` | `openSettingsAction?()` + `NSApp.activate()` |
| `.requestFileImport(types)` | 日志记录（能力接线待完成） |
| `.requestRefresh(reason)` | 通过 runtime 回调再次 dispatch refresh |
| `.scheduleLocal(cmd, after:)` | 通过 runtime 注入的 `SchedulerClock` 安排 command，可在 module disable/unload 时取消 |
| `.networkRequest(req)` | 日志警告：建议使用 `NetworkCapability` |

## 完整数据流示例

以 ClockModule 手动刷新为例：

```
1. 用户点击菜单栏 → Refresh
2. DeepLinkRouter / Menu → ModuleRuntime.refresh(moduleID:)
3. ModuleRuntime → ModuleSupervisor.perform(.refresh(reason: .manual))
4. ModuleActor → ClockModule.handle(command: .refresh(reason: .manual),
                                      capabilities: granted,
                                      bridge: KernelBridge)
5. ClockModule:
   - 读取当前时间
   - 构建 SnapshotEnvelope
   - 返回 DomainTransition(
       effects: [.publishSnapshot(envelope)],
       health: .healthy,
       refreshProjection: true
     )
6. ModuleActor → ModuleSupervisor.onEffects → EffectExecutor.execute(.publishSnapshot(envelope), for: "clock")
7. EffectExecutor → CacheStore.save(snapshot) + WidgetDataBridge.publish(envelope)
8. WidgetDataBridge → 写入 App Group UserDefaults + WidgetCenter.reloadAllTimelines()
9. EffectExecutor 回调 ModuleRuntime 更新 `snapshots[moduleID]`
10. StatusItemController 收集 enabled snapshots/status candidates → PresentationArbiter.submit()
11. PresentationArbiter → StatusItemRenderer → 更新 NSStatusItem
```

## Command 合并与代际

`ModuleActor` 保证**模块内串行**处理：

- **Coalesce**：重复的 `.refresh` 命令会被合并，只保留最新的 `reason`（仅限 fire-and-forget 的 enqueue 调用；awaited `perform()` 调用不会合并）
- **不合并**：`.userAction` 命令不会合并，确保每个用户操作都被处理
- **代际**：使用 `GenerationToken` 和 `CancellationScope`，如果模块正在处理旧 refresh，新 refresh 取消旧任务，旧结果被丢弃

## 相关文档

- [架构总览](Architecture.md) — 五平面架构和设计原则
- [能力安全体系](Capabilities.md) — GrantedCapabilities 和 CapabilityFactory
- [投影与快照](ProjectionAndSnapshot.md) — SnapshotEnvelope 和 ProjectionSet
- [原生模块开发](NativeModuleDevelopment.md) — 如何实现 handle() 方法
