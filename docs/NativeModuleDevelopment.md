# 原生模块开发指南

GlyphBar 支持两种原生模块：**内置编译模块**（Level 1）和 **XPC 隔离原生模块**（Level 3，P4）。原生模块实现 `ModuleContract` 协议，可以执行 Swift 代码，但必须遵守 Command/Effect 单向数据流和能力安全约束。

## 概述

| 类型 | 信任等级 | 代码执行 | 面板方式 | 隔离 |
|------|---------|---------|---------|------|
| 内置编译模块 | `.bundled` | 同进程 | `TypedModuleContribution` 泛型 `@ViewBuilder` | 编译时契约 |
| XPC 隔离模块 | `.signed` | 独立 XPC 进程 | `PanelModelProjection` 声明式 schema | 进程隔离 + 能力代理 |

## ModuleContract 协议

所有原生模块必须实现 `ModuleContract`：

```swift
@MainActor
protocol ModuleContract: AnyObject {
    var manifest: ModuleManifest { get }

    func handle(
        command: Command,
        capabilities: GrantedCapabilities,
        bridge: ModuleBridge
    ) async -> DomainTransition

    func buildProjection() -> ProjectionSet
    func statusCandidates() -> [StatusCandidate]

    @ViewBuilder
    func panelContribution(context: PanelHostContext) -> AnyView?
}
```

### manifest

模块的身份声明，包含 ID、显示名称、能力、权限、刷新策略、动作、Widget 描述等。详见 [Manifest 字段参考](ModuleManifest.md)。

```swift
static let staticManifest = ModuleManifest(
    id: "mymodule",
    displayName: "My Module",
    subtitle: "A custom module",
    systemImage: "star",
    version: "1.0.0",
    author: "Developer",
    compatibility: .init(minimumGlyphBarVersion: "1.0"),
    capabilities: [.statusItem, .panel, .actions, .widgets, .deepLinks],
    permissions: [.pasteboard],
    defaultRefreshPolicy: .manual,
    actions: [...],
    widgets: [...],
    priority: 0
)

var manifest: ModuleManifest { Self.staticManifest }
```

### handle(command:capabilities:bridge:)

模块的**唯一入口**。所有外部刺激都归一化为 `Command`，模块处理后返回 `DomainTransition`。

```swift
func handle(
    command: Command,
    capabilities: GrantedCapabilities,
    bridge: ModuleBridge
) async -> DomainTransition {
    switch command {
    case .refresh(let reason):
        return await handleRefresh(reason: reason, capabilities: capabilities)

    case .userAction(let actionID, let payload):
        return handleAction(actionID: actionID, payload: payload, capabilities: capabilities)

    case .settingsChanged:
        return handleSettingsChanged(capabilities: capabilities)

    case .permissionChanged:
        return handlePermissionChanged(capabilities: capabilities)

    case .appBecameActive:
        return .empty  // 或触发刷新

    case .systemWake:
        return DomainTransition(
            effects: [.requestRefresh(reason: .systemWake)],
            health: nil,
            refreshProjection: false
        )

    case .networkChanged(let reachable):
        if reachable {
            return DomainTransition(
                effects: [.requestRefresh(reason: .networkRestored)],
                health: nil,
                refreshProjection: false
            )
        } else {
            return DomainTransition(
                effects: [],
                health: .degraded(.networkError("Network unavailable")),
                refreshProjection: true
            )
        }

    case .importData(let url):
        return handleImport(url: url, capabilities: capabilities)

    case .clearCache:
        capabilities.cache?.clear()
        return DomainTransition(
            effects: [.requestRefresh(reason: .manual)],
            health: nil,
            refreshProjection: false
        )

    case .contributionTick:
        return .empty  // 仅 Clock 等需要展示 Tick 的模块处理
    }
}
```

### buildProjection()

返回模块当前状态的 `ProjectionSet`。内核在 `DomainTransition.refreshProjection == true` 时调用此方法。

```swift
func buildProjection() -> ProjectionSet {
    var projection = ProjectionSet()

    projection.summary = SummaryProjection(
        title: currentTitle,
        subtitle: currentSubtitle,
        systemImage: "star"
    )

    projection.metrics = MetricsProjection(items: [
        Metric(id: "value", label: "Value", value: currentValue, unit: nil, systemImage: nil)
    ])

    projection.statusCandidates = statusCandidates()

    projection.widget = WidgetProjection(
        title: currentTitle,
        subtitle: currentSubtitle,
        systemImage: "star",
        metrics: projection.metrics?.items,
        notes: nil
    )

    return projection
}
```

### statusCandidates()

返回模块的菜单栏展示候选列表。详见 [状态栏仲裁](PresentationArbiter.md)。

```swift
func statusCandidates() -> [StatusCandidate] {
    [
        StatusCandidate(
            id: "mymodule.primary",
            sourceModule: manifest.id,
            semanticRole: .primary,
            severity: .normal,
            priority: manifest.priority,
            text: currentTitle,
            icon: "star",
            createdAt: Date(),
            expiresAt: nil,
            interruptPolicy: .normal,
            trustLevel: .bundled
        )
    ]
}
```

### panelContribution(context:)

返回面板的 SwiftUI 视图。第三方/XPC 模块直接实现此方法返回 `AnyView?`；内置模块通过 `TypedModuleContribution` 返回具体类型。

## TypedModuleContribution — 内置模块的泛型面板

内置模块应遵循 `TypedModuleContribution`，使用关联类型避免 `AnyView` 擦除：

```swift
@MainActor
protocol TypedModuleContribution: ModuleContract {
    associatedtype Body: View

    @ViewBuilder
    func panelContent(context: PanelHostContext) -> Body
}
```

协议扩展自动将 `Body` 擦除为 `AnyView?`：

```swift
extension TypedModuleContribution {
    func panelContribution(context: PanelHostContext) -> AnyView? {
        AnyView(panelContent(context: context))
    }
}
```

### 实现示例

```swift
final class MyModule: TypedModuleContribution {
    // ... manifest, handle, buildProjection, statusCandidates ...

    func panelContent(context: PanelHostContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(currentTitle)
                .font(.headline)

            HStack {
                Text("Value: \(currentValue)")
                Spacer()
                Button("Refresh") {
                    context.dispatch(.refresh(reason: .manual))
                }
            }

            Button("Copy") {
                context.dispatch(.userAction(actionID: "copyStatus", payload: nil))
            }
        }
        .padding()
    }
}
```

### PanelHostContext

面板渲染时传入的上下文：

```swift
struct PanelHostContext {
    let moduleID: String
    let dispatch: (Command) -> Void
}
```

- `moduleID`：当前模块的 ID
- `dispatch`：发送 Command 到内核的闭包，**替代**直接调用模块方法

> **重要**：面板中的用户操作必须通过 `context.dispatch()` 发送 Command，不要直接调用模块方法或修改模块状态。这确保了单向数据流。

## AI-native 模块模板

新增原生模块时保持以下结构，AI 或开发者都应按同一顺序生成代码：

1. `staticManifest`：声明稳定 `id`、显示信息、actions、widgets、required capabilities 和 permissions。
2. 私有 `State` 模型：只包含领域状态；不要把 SwiftUI/AppKit 类型放入状态。
3. `handle(command:capabilities:bridge:)`：唯一业务入口。所有设置修改、按钮、导入、刷新都在这里处理。
4. 私有 handler 方法：例如 `handleRefresh`、`handleSetSetting`、`handleImportData`。
5. `buildSnapshot()` / `buildProjection()`：从状态投影，不执行副作用。
6. `statusCandidates()`：从当前状态生成候选，不读取 UI。
7. `panelContent(context:)`：SwiftUI 只展示状态并通过 `context.dispatch()` 发送 command。
8. Tests：至少覆盖 refresh、一个 user action、一个 settings command、permission denied/granted（若需要能力）、widget snapshot（若声明 widget）。

禁止模式：

- View/Binding 直接写模块核心状态。
- 模块直接调用 `UserDefaults.standard`、`URLSession.shared`、`NSPasteboard`、`NSWorkspace`、`WidgetCenter`。
- Settings 视图强转模块实例后调用业务方法。
- secret 存入 UserDefaults 或任何名为 secure 但实际明文的存储。

## Headless 测试

使用 `ModuleHarness` 在不启动 AppKit 窗口、StatusItem、QuickPanel 或 Settings UI 的情况下测试模块：

```swift
@MainActor
@Test func modulePublishesSnapshot() async {
    let module = MyModule()
    let harness = ModuleHarness(module: module)

    let transition = await harness.dispatch(.userAction(actionID: "increment", payload: nil))

    #expect(transition.refreshProjection == true)
    #expect(harness.latestSnapshot?.id == "myModule")
    #expect(harness.latestWidgetSnapshot?.title != nil)
}
```

需要测试权限时，注入 `PermissionCenter`：

```swift
let permissions = PermissionCenter(defaults: defaults)
let harness = ModuleHarness(
    module: ThirdPartyLikeModule(),
    sourceKind: .thirdParty,
    permissionCenter: permissions
)
```

第三方模块只有在 `PermissionCenter` 授权后才会获得 manifest 声明的敏感能力；内置模块按声明默认授予。

## DomainTransition 构建模式

### 成功刷新

```swift
let envelope = SnapshotEnvelope(
    id: manifest.id,
    schemaVersion: 1,
    capturedAt: Date(),
    validUntil: nil,
    freshness: .fresh,
    health: .healthy,
    projections: buildProjection()
)

return DomainTransition(
    effects: [.publishSnapshot(envelope)],
    health: .healthy,
    refreshProjection: true
)
```

### 用户动作

```swift
case .userAction(let actionID, _):
    switch actionID {
    case "copyStatus":
        return DomainTransition(
            effects: [.copyToClipboard(statusText), .publishSnapshot(envelope)],
            health: nil,
            refreshProjection: true
        )
    case "openDashboard":
        return DomainTransition(
            effects: [.openURL(URL(string: "https://example.com")!)],
            health: nil,
            refreshProjection: false
        )
    default:
        return .empty
    }
```

### 优雅降级

```swift
case .refresh:
    // 检查必要能力是否可用
    guard let network = capabilities.network else {
        return DomainTransition(
            effects: [.publishSnapshot(staleEnvelope)],
            health: .degraded(.permissionDenied(.network)),
            refreshProjection: true
        )
    }

    guard let secretStore = capabilities.secretStore,
          let apiKey = secretStore.get("apiKey") else {
        return DomainTransition(
            effects: [],
            health: .misconfigured(.missingSecret("apiKey")),
            refreshProjection: true
        )
    }

    // 正常处理...
```

### 忽略不相关 Command

```swift
case .settingsChanged, .appBecameActive, .systemWake:
    return .empty
```

## 能力使用

模块通过 `GrantedCapabilities` 访问被授予的能力。**只有非 nil 的能力可以使用**：

```swift
func handle(command: Command, capabilities: GrantedCapabilities, bridge: ModuleBridge) async -> DomainTransition {
    // 网络请求
    if let network = capabilities.network {
        let request = NetworkRequest(url: url, method: "GET")
        let (data, response) = try await network.send(request)
        // 处理响应...
    }

    // 密钥存储
    if let secretStore = capabilities.secretStore {
        secretStore.set("my-api-key", for: "apiKey")
        let key = secretStore.get("apiKey")
    }

    // 缓存
    if let cache = capabilities.cache {
        cache.saveDomainState(encodedData, forKey: "lastState")
        let cached = cache.loadDomainState(forKey: "lastState")
    }

    // 设置
    if let settings = capabilities.settings {
        let interval: Double = settings["refreshInterval"] ?? 300
        settings["refreshInterval"] = 600.0
    }

    // 系统指标
    if let systemMetrics = capabilities.systemMetrics {
        let cpu = systemMetrics.cpuUsage()
        let memory = systemMetrics.memoryUsage()
    }

    // 日志（始终可用）
    capabilities.logging?.info("处理完成")

    // ...
}
```

详见 [能力安全体系](Capabilities.md)。

## 模块注册

### 内置模块

在 `AppEnvironment` 中通过 `ModuleRegistry.register {}` 注册：

```swift
registry.register { [capabilityFactory, bridge] in
    let capabilities = capabilityFactory.makeCapabilities(
        for: MyModule.staticManifest,
        bridge: bridge
    )
    return MyModule(capabilities: capabilities)
}
```

`CapabilityFactory` 根据 manifest 的 `permissions` 和 `capabilities` 自动构建正确的 `GrantedCapabilities`。

### XPC 模块（P4）

XPC 模块由 `Reconciler` 根据 `DesiredModuleState` 自动加载，通过 `XPCModuleHost` 建立连接。不需要手动注册。

## XPC 模块开发（P4 展望）

XPC 隔离模块在独立进程中运行，所有平台访问经能力代理回调主 App。

### XPCModuleProtocol

XPC 进程必须实现的协议：

```swift
@objc protocol XPCModuleProtocol {
    func load(manifestData: Data, reply: @escaping (Error?) -> Void)
    func handle(commandData: Data, reply: @escaping (Data) -> Void)
    func terminate(reply: @escaping () -> Void)
}
```

### XPCModuleHostProtocol

XPC 进程回调主 App 申请能力的协议：

```swift
@objc protocol XPCModuleHostProtocol {
    func requestNetwork(_ reqData: Data, reply: @escaping (Data?, Error?) -> Void)
    func requestSecret(_ key: String, reply: @escaping (String?) -> Void)
    func submitEffects(_ effectsData: Data)
}
```

### 序列化要求

XPC 模块的所有数据必须 `Codable + Sendable`：

- `Command` → JSON Data → 跨 XPC 传输 → 解码
- `DomainTransition` → JSON Data → 回传主 App
- `Effect` → JSON Data → 回传主 App
- `ProjectionSet` → JSON Data → 回传主 App

### 面板限制

**SwiftUI View 不可跨进程传输**。XPC 模块只能使用 `PanelModelProjection`（Codable 声明式面板布局），由主 App 的通用渲染器绘制。XPC 模块的 `panelContribution(context:)` 返回基于 `PanelModelProjection` 的 `AnyView`。

### 能力代理

XPC 进程内的 `GrantedCapabilities` 全部是代理对象：

- `NetworkCapability` → 调用 `hostProxy.requestNetwork()`
- `ModuleSecretStore` → 调用 `hostProxy.requestSecret()`
- 无直接 `NSPasteboard`/`FileManager`/`UserDefaults` 访问

主 App 的 `XPCModuleHost` 在处理能力请求时，先通过 `CapabilityBroker` 校验授予状态，再执行实际操作。

### 签名验证

XPC 模块包必须通过代码签名验证（`SecStaticCodeCheckValidity`），未签名的包被拒绝加载。只有 `TrustLevel.signed` 的模块才允许 XPC 原生执行。

### 沙箱配置

XPC Service 配置 `com.apple.security.app-sandbox`，限制文件系统和网络访问。所有资源访问必须通过能力代理。

## 相关文档

- [架构总览](Architecture.md) — 微内核架构和扩展层级
- [Command/Effect 管线](CommandEffectPipeline.md) — Command 和 Effect 的完整参考
- [能力安全体系](Capabilities.md) — GrantedCapabilities 和 CapabilityFactory
- [投影与快照](ProjectionAndSnapshot.md) — ProjectionSet 和 SnapshotEnvelope
- [状态栏仲裁](PresentationArbiter.md) — StatusCandidate 和仲裁算法
- [内置模块参考](BuiltInModules.md) — 6 个内置模块的实现参考
- [安全与权限](SecurityAndPermissions.md) — XPC 隔离和签名验证
