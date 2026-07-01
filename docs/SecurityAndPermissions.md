# 安全与权限

GlyphBar 采用多层安全模型，根据模块的扩展层级和信任等级实施不同强度的隔离。核心原则是**最小权限**：模块只能访问其 manifest 声明并被内核授予的能力。

## 三级扩展安全策略

| 层级 | 类型 | 信任等级 | 代码执行 | 隔离方式 | 典型场景 |
|------|------|---------|---------|---------|---------|
| **Level 1** | 内置编译模块 | `.bundled` | 同进程，直接调用 | 编译时契约 | Clock、DeepSeek 等 |
| **Level 2** | 声明式 JSON 包 | `.unsignedLocal` | 无原生代码 | 数据隔离 | 第三方状态模块 |
| **Level 3** | XPC 隔离原生模块 | `.signed` | 独立 XPC 进程 | 进程隔离 + 能力代理 | 不可信原生模块（P4） |

### Level 1 — 内置编译模块

- **完全信任**：编译时通过 `ModuleContract` 契约约束
- **同进程运行**：直接调用，无序列化开销
- **能力约束**：仍需通过 `GrantedCapabilities` 访问平台 API，但授予更宽松
- **内置特权**：内置模块默认获得其 manifest 声明的权限；第三方模块必须获得用户授权后才获得对应能力

### Level 2 — 声明式 JSON 包

- **无代码执行**：GlyphBar 不加载任何 Swift、Objective-C、动态库、脚本或可执行文件
- **宿主解释**：由 `DeclarativeModule` 解释 manifest 和 snapshot 数据，渲染通用 UI
- **预定义行为**：只支持 4 种 action kind（copy/openURL/deepLink/refresh），无法自定义行为
- **数据隔离**：存储通过命名空间隔离，模块无法访问其他模块的数据

### Level 3 — XPC 隔离原生模块（P4）

- **进程隔离**：在独立 XPC 进程中运行，与主 App 完全隔离
- **能力代理**：所有平台访问经 `XPCModuleHostProtocol` 回调主 App，由 `CapabilityBroker` 校验后执行
- **沙箱配置**：XPC Service 配置 `com.apple.security.app-sandbox`
- **签名验证**：必须通过代码签名校验（`SecStaticCodeCheckValidity`），未签名包被拒绝加载
- **资源限制**：可配置内存、CPU、超时限制
- **降级**：XPC 进程崩溃时自动重启（带 backoff），多次失败标记为不可用

## 信任等级

```swift
enum TrustLevel: Sendable, Comparable {
    case untrusted       // rank 0
    case unsignedLocal   // rank 1
    case bundled         // rank 2
    case signed          // rank 3
}
```

| 等级 | rank | 适用 | 含义 |
|------|------|------|------|
| `.untrusted` | 0 | — | 完全不可信，当前未使用 |
| `.unsignedLocal` | 1 | Level 2 | 用户导入的未签名本地包 |
| `.bundled` | 2 | Level 1 | 随 App 编译的内置模块 |
| `.signed` | 3 | Level 3 | 通过代码签名验证的 XPC 模块 |

### 信任等级的影响

信任等级在以下场景中发挥作用：

1. **状态栏仲裁**：当多个候选的严重度和优先级相同时，高信任等级的候选优先展示。这保证了 `.bundled` 模块不会被 `.unsignedLocal` 模块饿死
2. **能力授予**：未来可能根据信任等级限制可申请的权限范围
3. **XPC 准入**：只有 `.signed` 等级的模块才允许在 XPC 进程中执行原生代码

## 权限系统

### 权限声明

模块在 manifest 中声明所需的权限：

```json
{
  "permissions": ["pasteboard", "openExternalURLs", "localFiles", "appGroupStorage"]
}
```

### 权限 → 能力映射

`CapabilityFactory` 将声明映射为具体的能力实例：

| 权限 | 授予的能力 | 共享/独占 |
|------|-----------|----------|
| `pasteboard` | `ClipboardCapability` | 共享 |
| `systemMetrics` | `SystemMetricsCapability` | 共享 |
| `appGroupStorage` | `ModuleCacheNamespace` + `ModuleSettingsNamespace` + `ModuleSecretStore` | 独占 |
| `localFiles` | `FileImportCapability` | 独占 |
| `openExternalURLs` | `NetworkCapability` | 共享 |
| `notifications` | （暂未实现） | — |

### 授予链

```
Manifest permissions + source trust + PermissionCenter
    → CapabilityFactory.makeCapabilities()
    → GrantedCapabilities（每个能力为可选，nil = 未授予）
    → 传入 Module.handle(command:capabilities:bridge:)
```

**关键**：

- 未声明的权限不会生成能力实例。
- 内置模块按声明默认授予能力。
- 第三方模块即使声明了权限，也必须通过 `PermissionCenter` 授权；未授权时 capability 为 `nil`。
- `settings`、`cachedState`、`storage` 等命名空间能力对第三方模块同样受 `appGroupStorage` 权限约束。

### CapabilityBroker — 动态授予/撤销

`CapabilityBroker` 追踪每个模块实例的能力授予状态，支持运行时动态变更：

```swift
@MainActor final class CapabilityBroker {
    func grant(_ key: CapabilityKey, to instance: ModuleInstanceID)
    func revoke(_ key: CapabilityKey, from instance: ModuleInstanceID)
    func currentGrants(for instance: ModuleInstanceID) -> Set<CapabilityKey>
    var onGrantChange: ((ModuleInstanceID, CapabilityKey, Bool) -> Void)?
}
```

- 权限撤销时，`onGrantChange` 通知 Reconciler，模块可能被降级或暂停
- XPC 模块的能力请求经过 `CapabilityBroker` 校验后才执行

## 存储安全

### ModuleSecretStore — 密钥存储

- **后端**：macOS Keychain
- **命名空间**：`module.<moduleID>.<key>`
- **安全特性**：
  - Keychain 数据加密存储
  - 每个模块独立命名空间，模块 A 无法读取模块 B 的密钥
  - 模块删除时可选择清除关联密钥

**无明文兼容层**：GlyphBar 不提供明文 secret store 或 UserDefaults plaintext fallback。新模块只能通过 `ModuleSecretStore` 读写敏感信息；测试覆盖了 UserDefaults 明文键不会被读取。

### ModuleCacheNamespace — 缓存存储

- **后端**：UserDefaults（App Group suite）
- **命名空间**：`module.<moduleID>.<key>`
- **安全特性**：
  - 命名空间隔离，模块间不可交叉访问
  - 数据为模块域状态，可随时清除重建

### ModuleSettingsNamespace — 设置存储

- **后端**：UserDefaults（App Group suite）
- **命名空间**：`module.<moduleID>.<key>`
- **安全特性**：
  - 命名空间隔离
  - Codable 类型安全
  - 模块删除时可选择保留或清除

### 模块删除时的数据清理

删除第三方模块时：

1. 删除 Application Support 中的包目录
2. 清除 App Group UserDefaults 中的缓存数据（`module.<moduleID>.*`）
3. 清除 Keychain 中的密钥（`module.<moduleID>.*`）
4. 通知 WidgetBridge 移除关联快照

## App Group 数据隔离

主 App 和 Widget 扩展通过共享的 App Group 容器交换数据：

```
App Group: group.com.wenjiexu.GlyphBar
├── Main App (com.wenjiexu.GlyphBar)
│   └── 写入 WidgetModuleSnapshot
└── Widget Extension (com.wenjiexu.GlyphBar.widgets)
    └── 读取 WidgetModuleSnapshot
```

- **主 App**：通过 `WidgetDataBridge` 写入数据
- **Widget 扩展**：通过 `ModuleTimelineProvider` 读取数据
- **隔离**：Widget 扩展只能读取 App Group 中的数据，无法访问主 App 的其他存储

## XPC 隔离（P4）

### 沙箱配置

XPC Service 在 App Sandbox 中运行：

```xml
<!-- GlyphBarXPCModule.xpc/Info.plist -->
<key>com.apple.security.app-sandbox</key>
<true/>
```

沙箱限制：
- 无法直接访问文件系统（需通过 `FileImportCapability` 代理）
- 无法直接发起网络请求（需通过 `NetworkCapability` 代理）
- 无法直接访问剪贴板（需通过 `ClipboardCapability` 代理）
- 无法直接访问 Keychain（需通过 `ModuleSecretStore` 代理）

### 能力代理

XPC 进程内的所有能力都是代理对象，通过 `XPCModuleHostProtocol` 回调主 App：

```swift
@objc protocol XPCModuleHostProtocol {
    func requestNetwork(_ reqData: Data, reply: @escaping (Data?, Error?) -> Void)
    func requestSecret(_ key: String, reply: @escaping (String?) -> Void)
    func submitEffects(_ effectsData: Data)
}
```

主 App 的 `XPCModuleHost` 在处理请求时：
1. 通过 `CapabilityBroker` 校验该模块是否被授予了对应能力
2. 如果已授予，执行实际操作并返回结果
3. 如果未授予，返回错误

### 签名验证

`Installer.validate` 阶段对 XPC 模块包执行代码签名校验：

```swift
func validate(package: Package) throws {
    // SecStaticCodeCheckValidity 验证代码签名
    // 未签名的包拒绝加载
    // 签名不匹配的包拒绝加载
}
```

只有 `TrustLevel.signed` 的模块才被允许在 XPC 进程中执行原生代码。

### 资源/时间限制

- **超时**：`handle()` 设置超时，超时后 `ModuleSupervisor` 取消连接并重建
- **内存限制**：XPC Service 可配置内存上限
- **崩溃恢复**：XPC 进程崩溃 → Supervisor 重启（带 backoff）→ 多次失败 → 标记 `unavailable`

## 相关文档

- [架构总览](Architecture.md) — 三级扩展模型
- [能力安全体系](Capabilities.md) — GrantedCapabilities 和 CapabilityFactory
- [声明式模块开发](ModuleDevelopment.md) — Level 2 模块开发
- [原生模块开发](NativeModuleDevelopment.md) — Level 1 和 Level 3 模块开发
- [Manifest 字段参考](ModuleManifest.md) — permissions 字段详解
