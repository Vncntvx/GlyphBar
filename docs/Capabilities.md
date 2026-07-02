# 能力安全体系

GlyphBar 采用**能力安全**（Capability Security）模型：模块只能访问其 manifest 声明并被内核授予的能力。未声明的能力不可访问，未授予的权限不可使用。

## 设计原则

| 原则 | 含义 |
|------|------|
| 按需授予 | 只有 manifest 声明的权限才会被映射为具体能力实例 |
| 零默认权限 | `GrantedCapabilities` 中除 `bridge` 外所有能力均为可选，默认 `nil` |
| 命名空间隔离 | 每个模块的存储能力使用 `module.<moduleID>.<key>` 前缀隔离 |
| 共享 vs 独占 | 无状态能力（Network、SystemMetrics、Clipboard）全局共享；有状态能力（Settings、Cache、SecretStore）每模块独占 |

## GrantedCapabilities

```swift
@MainActor
struct GrantedCapabilities {
    let secretStore: ModuleSecretStore?
    let cache: ModuleCacheNamespace?
    let settings: ModuleSettingsNamespace?
    let network: NetworkCapability?
    let fileImport: FileImportCapability?
    let clipboard: ClipboardCapability?
    let logging: LoggingCapability?
    let systemMetrics: SystemMetricsCapability?
    let bridge: ModuleBridge   // 始终授予
}
```

模块通过 `handle(command:capabilities:bridge:)` 接收 `GrantedCapabilities`。**只有非 nil 的能力可以被使用**；如果 `network` 为 `nil`，模块无法发起网络请求。

## 能力详细参考

### ModuleSecretStore

```swift
@MainActor final class ModuleSecretStore: Capability {
    func setSecret(_ value: String?, for rawKey: String)
    func secret(for rawKey: String) -> String?
    func deleteSecret(for rawKey: String)
}
```

- **后端**：macOS Keychain（`KeychainBackend`），使用 `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete`
- **命名空间**：`module.<moduleID>.<rawKey>`（account 字段）
- **授予条件**：manifest 声明 `.appGroupStorage` 权限
- **典型用途**：存储 API Key 等敏感信息（如 DeepSeek 的 API Key）
- **隔离性**：每个模块独立实例，模块 A 无法读取模块 B 的密钥
- **测试后端**：`InMemorySecretStoreBackend` 提供不依赖 Keychain 的内存实现

> **命名诚实**：`ModuleSecretStore` 的生产后端是 Keychain，数据加密存储。测试中使用 `InMemorySecretStoreBackend` 替代。

### ModuleCacheNamespace

```swift
@MainActor final class ModuleCacheNamespace: Capability {
    func saveDomainState(_ data: Data)
    func loadDomainState() -> Data?
    func clearDomainState()
}
```

- **后端**：UserDefaults（App Group suite）
- **命名空间**：`module.<moduleID>.domainState`
- **授予条件**：manifest 声明 `.appGroupStorage` 权限或 `.cachedState` 能力
- **典型用途**：缓存模块域状态（如 NotesQuick 的备忘录数据、DeepSeek 的用量数据）
- **隔离性**：每个模块独立实例

### ModuleSettingsNamespace

```swift
@MainActor final class ModuleSettingsNamespace: Capability {
    subscript(rawKey: String) -> String? { get set }
    func get<T: Codable>(_ type: T.Type, forKey rawKey: String) -> T?
    func set<T: Codable>(_ value: T?, forKey rawKey: String)
}
```

- **后端**：UserDefaults（App Group suite）
- **命名空间**：`module.<moduleID>.setting.<rawKey>`
- **授予条件**：manifest 声明 `.appGroupStorage` 权限或 `.settings` 能力
- **典型用途**：存储模块配置（如 Clock 的 24 小时制偏好、Counter 的步长和边界）
- **隔离性**：每个模块独立实例
- **Codable 支持**：`get(_:forKey:)` 和 `set(_:forKey:)` 支持任意 Codable 类型

### NetworkCapability

```swift
@MainActor final class NetworkCapability: Capability {
    func send(_ request: NetworkRequest) async throws -> (Data, HTTPURLResponse)
}
```

- **后端**：`URLSession`
- **共享实例**：所有模块共享同一个 `NetworkCapability` 实例
- **授予条件**：manifest 声明 `.openExternalURLs` 权限
- **典型用途**：发起 HTTP 请求（如 DeepSeek 查询 API 用量）
- **注意**：替代旧的 `Effect.networkRequest`，利用能力授予机制进行权限控制

### FileImportCapability

```swift
@MainActor final class FileImportCapability: Capability {
    func requestImport(allowedTypes: [String]) -> URL?
}
```

- **后端**：`NSOpenPanel`
- **授予条件**：manifest 声明 `.localFiles` 权限
- **典型用途**：让用户选择文件导入（如 DeepSeek 导入用量 CSV 数据）
- **隔离性**：每个模块独立实例

### ClipboardCapability

```swift
@MainActor final class ClipboardCapability: Capability {
    func read() -> String?
    func write(_ text: String)
}
```

- **后端**：`NSPasteboard.general`
- **共享实例**：所有模块共享同一个 `ClipboardCapability` 实例
- **授予条件**：manifest 声明 `.pasteboard` 权限
- **典型用途**：读取或写入剪贴板内容

> **注意**：写入剪贴板也可以通过 `Effect.copyToClipboard` 实现。`ClipboardCapability` 适用于需要读取剪贴板的场景。

### LoggingCapability

```swift
@MainActor final class LoggingCapability: Capability {
    func info(_ message: String)
    func warn(_ message: String)
    func error(_ message: String)
    func debug(_ message: String)
}
```

- **后端**：`GlyphLogger`
- **始终授予**：每个模块都自动获得日志能力
- **自动标记**：日志条目自动携带 `moduleID`，无需手动标注
- **隔离性**：每个模块独立实例（自动附加模块上下文）

### SystemMetricsCapability

```swift
@MainActor final class SystemMetricsCapability: Capability {
    func cpuUsage() -> Double
    func memoryUsage() -> (used: UInt64, total: UInt64)
    func diskUsage() -> (used: UInt64, total: UInt64)
}
```

- **后端**：Mach API、`ProcessInfo`、`URL.resourceValues`
- **共享实例**：所有模块共享同一个 `SystemMetricsCapability` 实例
- **授予条件**：manifest 声明 `.systemMetrics` 权限
- **典型用途**：读取系统指标（如 SystemPulseModule）
- **设计意义**：将 Mach API 等底层调用收口到能力对象中，模块不再直接调用

## CapabilityFactory — 授予规则

`CapabilityFactory` 将 manifest 的声明映射为具体的 `GrantedCapabilities`：

### 权限 → 能力映射

| 权限 (`ModulePermission`) | 授予的能力 | 共享/独占 |
|---------------------------|-----------|----------|
| `.pasteboard` | `ClipboardCapability` | 共享 |
| `.systemMetrics` | `SystemMetricsCapability` | 共享 |
| `.appGroupStorage` | `ModuleCacheNamespace` + `ModuleSettingsNamespace` + `ModuleSecretStore` | 独占 |
| `.localFiles` | `FileImportCapability` | 独占 |
| `.openExternalURLs` | `NetworkCapability` | 共享 |
| `.notifications` | （暂未实现） | — |

### 能力声明 → 命名空间补充

| 能力 (`ModuleCapability`) | 补充授予 | 说明 |
|--------------------------|---------|------|
| `.settings` | `ModuleSettingsNamespace` | 如果尚未通过权限获得 |
| `.cachedState` | `ModuleCacheNamespace` | 如果尚未通过权限获得 |
| `.storage` | `ModuleCacheNamespace` + `ModuleSettingsNamespace` | 两者都授予 |

### 始终授予

- `LoggingCapability` — 每模块独占实例
- `ModuleBridge` — 效果提交通道

### 授予优先级

`CapabilityFactory.makeCapabilities(for:manifest:bridge:)` 的处理顺序：

1. 根据 `permissions` 授予基础能力
2. 根据 `capabilities` 补充命名空间能力（如果尚未授予）
3. 如果模块声明 `.appGroupStorage` 权限且被允许，自动授予 `ModuleSecretStore`
4. 始终添加 `LoggingCapability` 和 `ModuleBridge`

### 权限校验

内置模块（`sourceKind: .builtIn`）按声明默认授予所有权限。第三方模块（`sourceKind: .thirdParty`）需要通过 `PermissionCenter.isGranted(_:)` 校验，未授权的权限不会生成对应能力实例。

## ModuleBridge — 效果提交通道

```swift
@MainActor
protocol ModuleBridge: AnyObject {
    func submit(_ effects: [Effect])
    func submit(_ effect: Effect)
}
```

`ModuleBridge` 是 `GrantedCapabilities` 中**始终存在**的字段（非可选），是模块提交 Effect 的唯一通道。

使用方式：
```swift
func handle(command: Command, capabilities: GrantedCapabilities, bridge: ModuleBridge) async -> DomainTransition {
    // 通常通过 DomainTransition.effects 返回
    return DomainTransition(effects: [.copyToClipboard("hello")], ...)

    // 异步场景可通过 bridge.submit()
    // bridge.submit(.showNotice("操作完成"))
}
```

## CapabilityBroker — 动态授予/撤销

`CapabilityBroker` 追踪每个模块实例的能力授予状态，支持动态授予和撤销：

```swift
@MainActor final class CapabilityBroker {
    func grant(_ key: CapabilityKey, to instance: ModuleInstanceID)
    func revoke(_ key: CapabilityKey, from instance: ModuleInstanceID)
    func currentGrants(for instance: ModuleInstanceID) -> Set<CapabilityKey>
    func setGrants(_ keys: Set<CapabilityKey>, for instance: ModuleInstanceID)
    var onGrantChange: ((ModuleInstanceID, CapabilityKey, Bool) -> Void)?
}
```

- **触发回调**：授予/撤销时通过 `onGrantChange` 通知 Reconciler
- **用途**：XPC 模块的能力代理校验、权限撤销时的模块降级

## 命名空间隔离机制

所有带状态的存储能力都使用 `module.<moduleID>` 前缀实现隔离：

```
UserDefaults App Group Suite:
  module.clock.setting.moduleState → <ClockState JSON>
  module.counter.setting.moduleState → <CounterState JSON>
  module.notesQuick.domainState → <NotesQuickState Data>
  module.deepseek.domainState → <DeepSeekCache Data>

Keychain:
  service: com.wenjiexu.GlyphBar.module
  account: module.deepseek.deepseek.apiKey → <encrypted>
  account: module.deepseek.deepseek.platformCookie → <encrypted>
```

- **ModuleSecretStore**：Keychain 的 `service` 和 `account` 包含模块 ID
- **ModuleCacheNamespace**：UserDefaults key 为 `module.<moduleID>.domainState`
- **ModuleSettingsNamespace**：UserDefaults key 为 `module.<moduleID>.setting.<rawKey>`

这保证了模块 A 无法意外或恶意读写模块 B 的数据。

## 模块使用能力的典型模式

```swift
final class MyModule: TypedModuleContribution {
    let manifest: ModuleManifest = .init(...)

    func handle(command: Command, capabilities: GrantedCapabilities, bridge: ModuleBridge) async -> DomainTransition {
        switch command {
        case .refresh:
            // 使用 network 能力（如果授予了）
            if let network = capabilities.network {
                let request = NetworkRequest(url: url, method: "GET")
                let (data, _) = try await network.send(request)
                // 处理数据...
            }

            // 使用 cache 能力（如果授予了）
            if let cache = capabilities.cache {
                cache.saveDomainState(encodedData)
            }

            // 使用 settings 能力（如果授予了）
            if let settings = capabilities.settings {
                let interval: String? = settings["refreshInterval"]
            }

            // 使用 secret 能力（如果授予了）
            if let secretStore = capabilities.secretStore {
                let apiKey = secretStore.secret(for: "apiKey")
            }

            // 日志始终可用
            capabilities.logging?.info("刷新完成")

            return DomainTransition(
                effects: [.publishSnapshot(envelope)],
                health: .healthy,
                refreshProjection: true
            )

        default:
            return .empty
        }
    }
}
```

## 相关文档

- [架构总览](Architecture.md) — 五平面架构
- [Command/Effect 管线](CommandEffectPipeline.md) — 数据流和 Effect 执行
- [安全与权限](SecurityAndPermissions.md) — 信任等级和权限系统
- [Manifest 字段参考](ModuleManifest.md) — 声明权限和能力的 JSON 格式
