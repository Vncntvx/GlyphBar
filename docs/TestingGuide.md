# 测试指南

GlyphBar 使用 **Swift Testing** 框架编写测试。**不使用 XCTest**。本文档介绍测试约定、目录结构、常用模式和契约测试套件。

## 测试框架

```swift
import Testing

@Test func myTest() async {
    #expect(result == expected)
    #require(optionalValue != nil)
}
```

| Swift Testing | XCTest 等价 |
|---------------|-------------|
| `import Testing` | `import XCTest` |
| `@Test` | `func test...() throws` |
| `#expect(condition)` | `XCTAssertTrue(condition)` |
| `#expect(a == b)` | `XCTAssertEqual(a, b)` |
| `#require(value != nil)` | `XCTUnwrap(value)` |
| 测试套件 = `struct` | 测试套件 = `class XCTestCase` |

### 关键差异

- 测试函数不需要 `test` 前缀，`@Test` 宏标记测试
- 测试套件是 `struct`，不是 `class`
- `#expect` 可以用在任何位置，不限于测试方法内
- `#require` 用于解包可选值，失败时立即中止
- 支持参数化测试：`@Test(arguments: collection)`

## 运行测试

```sh
./script/build_and_run.sh --test
```

或直接使用 xcodebuild：

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project GlyphBar.xcodeproj -scheme GlyphBar \
  -destination 'platform=macOS' test \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

## 测试目录结构

```
Tests/
├── ContractTests/            # 契约测试（跨模块参数化验证）
│   ├── BuiltInModuleContractTests.swift
│   ├── BuiltInModuleCapabilityEffectContractTests.swift
│   ├── BuiltInModuleCommandProjectionContractTests.swift
│   ├── BuiltInModuleStorageSnapshotContractTests.swift
│   ├── ThirdPartyModuleContractTests.swift
│   └── ThirdPartyCapabilityPolicyContractTests.swift
│   └── ThirdPartyInfrastructureContractTests.swift
├── KernelTests/              # 内核基础设施测试
│   ├── EffectExecutorTests.swift
│   ├── ModuleCacheNamespaceTests.swift
│   ├── ModuleSecretStoreTests.swift
│   ├── ModuleHarnessTests.swift
│   ├── CapabilityEnforcementTests.swift
│   ├── ProjectionBuilderTests.swift
│   ├── SnapshotEnvelopeTests.swift
│   ├── WidgetSnapshotBridgeTests.swift
│   └── DeepSeekRegressionTests.swift
├── CoreTests/                # 核心运行时测试
│   ├── DeepLinkRouterTests.swift
│   ├── QuickPanelCoordinatorAPITests.swift
│   ├── RefreshSchedulerTests.swift
│   ├── SettingsOverhaulTests.swift
│   ├── StatusComposerTests.swift
│   ├── StatusRotationEngineTests.swift
│   ├── WidgetContentSectionsTests.swift
│   └── WidgetDataBridgeTests.swift
├── ExecutionTests/           # 调度层测试
│   └── ExecutionModelTests.swift
├── ModuleTests/              # 模块行为测试
│   ├── ClockCounterCommandTests.swift
│   ├── NotesQuickModuleTests.swift
│   └── TemplateModuleTests.swift
├── ControlPlaneTests/        # 控制面板测试
│   ├── ControlPlaneTests.swift
│   └── PlatformTests.swift
└── PropertyTests/            # 属性测试
    ├── ArbiterPropertyTests.swift
    └── ArbiterTests.swift
```

| 目录 | 内容 | 特点 |
|------|------|------|
| `ContractTests/` | 跨所有模块的契约验证 | 参数化，验证所有模块遵守公共契约 |
| `KernelTests/` | 内核组件单元测试 | 测试 EffectExecutor、Capability、Projection 等 |
| `CoreTests/` | 核心运行时测试 | 测试路由、调度、设置、Widget 桥接等 |
| `ModuleTests/` | 模块集成测试 | 测试模块 command 流和状态变更 |
| `PropertyTests/` | 属性测试 | 仲裁器随机输入验证 |

## 测试模式

### 参数化测试

跨所有内置模块验证公共契约：

```swift
struct BuiltInModuleContractTests {
    @Test(arguments: builtInModuleFactories)
    func manifestIDMatchesRegisteredName(_ factory: ModuleFactory) async {
        let module = factory.make()
        #expect(module.manifest.id == factory.id)
    }
}
```

### UserDefaults 隔离

使用独立 suite 避免测试间干扰：

```swift
let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
defer { defaults.removePersistentDomain(forName: defaults.suiteName!) }
```

### KernelBridge 闭包桥接

创建无操作 bridge 用于单元测试：

```swift
let bridge = KernelBridge { _ in }
// 或捕获 effects：
var capturedEffects: [Effect] = []
let bridge = KernelBridge { capturedEffects.append($0) }
```

### GrantedCapabilities 构建

构建最小或完整的 `GrantedCapabilities`：

```swift
// 最小（无额外能力）
let capabilities = GrantedCapabilities(bridge: bridge)

// 完整
let capabilities = GrantedCapabilities(
    secretStore: ModuleSecretStore(moduleID: "test", backend: InMemorySecretStoreBackend()),
    cache: ModuleCacheNamespace(moduleID: "test"),
    settings: ModuleSettingsNamespace(moduleID: "test"),
    network: NetworkCapability(),
    fileImport: nil,
    clipboard: ClipboardCapability(),
    logging: LoggingCapability(moduleID: "test", logger: logger),
    systemMetrics: nil,
    bridge: bridge
)
```

### ModuleHarness

模块行为测试优先使用 `ModuleHarness`。它复用生产 `ModuleSupervisor` 和 `CapabilityFactory`，但不创建 AppKit 窗口、StatusItem、QuickPanel 或 Settings UI。

```swift
@MainActor
@Test func commandPublishesSnapshot() async {
    let harness = ModuleHarness(module: MyModule())

    let transition = await harness.dispatch(.refresh(reason: .manual))

    #expect(transition.refreshProjection == true)
    #expect(harness.latestSnapshot?.id == "myModule")
    #expect(harness.latestWidgetSnapshot?.id == "myModule")
}
```

用它覆盖：

- command dispatch（`dispatch(_:)`）
- refresh（`refresh(reason:)`）
- emitted effects（`emittedEffects`）
- latest snapshot（`latestSnapshot`、`latestEnvelope`）
- widget snapshot projection（`latestWidgetSnapshot`）
- start/stop/unload 行为（`stop()`、`unload()`）
- permission denied/granted 路径（通过 `sourceKind: .thirdParty` + `PermissionCenter`）

### 临时目录

使用临时目录测试文件系统操作：

```swift
let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
```

## 契约测试套件

`BuiltInModuleContractTests` 验证所有内置模块遵守 `ModuleContract` 的 12 项契约：

### 1. Manifest 合法性

- ID 与注册名匹配
- 版本号为语义化格式
- 刷新策略合法
- 优先级在 0...1000 范围内
- 动作 ID 唯一且非空

### 2. handle(command:) 合法性

- `.refresh` 产生有效 `DomainTransition`（包含 `publishSnapshot`）
- 未知 `userAction` 不产生副作用的 Effect
- 系统命令（`.settingsChanged`、`.appBecameActive` 等）不崩溃

### 3. buildProjection() 合法性

- 返回非空 `summary`（包含 title 和 systemImage）
- 声明了 `widgets` 的模块产生 `widget` 投影

### 4. statusCandidates() 契约

- 格式正确（非空 ID、sourceModule 匹配、priority 0-1000、合法 semanticRole）
- 内置模块的候选必须使用 `.bundled` trustLevel
- ID 唯一且稳定

### 5. 优雅降级

- 模块在 `nil` capabilities 下处理 refresh 不崩溃
- DeepSeek 在无密钥时优雅降级

### 6. 命名空间隔离

- `ModuleSettingsNamespace` 和 `ModuleCacheNamespace` 隔离两个模块
- Codable round-trip 正确
- nil 删除正确

### 7. SnapshotEnvelope 契约

- 携带所有字段
- 默认值合理
- stale/unavailable freshness 状态正确

### 8. PresentationTickable 契约

- Clock tick 返回更新后的候选
- 幂等性
- 保留 rotation 候选

### 9. DomainTransition 契约

- `.empty` 无 effects
- 构建的 transitions 正确携带 effects/health/refreshProjection

### 10. ModuleHealth 契约

- `.healthy` 不是 unhealthy/terminal
- `.degraded` 是 unhealthy 但不是 terminal
- `.unavailable`/`.misconfigured`/`.suspended` 是 terminal

### 11. CapabilityFactory 契约

- 按 manifest 授予能力
- 拒绝未声明的能力
- `appGroupStorage` 权限授予 `secretStore`
- 始终授予 `logging` + `bridge`

### 12. Effect 契约

- 所有 case 可构造
- `NetworkRequest` 携带所有字段

## 第三方基础设施测试

`ThirdPartyModuleContractTests` 验证第三方模块支持基础设施：

### IngestionAPI 测试

- publish/subscribe 正确工作
- schema 版本不匹配时拒绝
- 所有 source 类型正确
- invalidate 和 clear 正确执行

### CapabilityBroker 测试

- grant/track 正确
- revocation 正确
- 实例间隔离
- `setGrants` 批量设置
- `onGrantChange` 回调正确触发

### ArbitrationPolicy 测试

- `.bundled` 优先于 `.untrusted`
- `.critical` 抢占 `.normal`
- 按语义角色的最短展示时长
- 按严重度的冷却期

### XPC 隔离测试

- Host 创建和销毁
- Proxy 创建
- 从包创建 Proxy

### 诊断和版本测试

- `DiagnosticContext` 字段正确填充
- 关联 ID 唯一
- `SchemaVersion`/`ProtocolVersions` 初始值正确
- 包验证器拒绝不存在的路径

## DeepSeek 回归测试

`DeepSeekRegressionTests` 是 DeepSeek 模块能力注入和 command 流的反回归守卫：

- **不再直接访问 `UserDefaults.standard`**：DeepSeek 必须使用 `ModuleSettingsNamespace`
- **secret 只走 `ModuleSecretStore`**：没有明文 secret store 或 UserDefaults fallback
- **设置与导入通过 command**：API key、cookie、usage import 都通过 `handle(command:)` 测试
- **NetworkCapability 注入正确**：网络请求通过 `NetworkCapability` 而非 `URLSession.shared`

## 编写新测试的建议

1. **使用 Swift Testing**：不要使用 XCTest
2. **命名描述性**：`func arbiterCriticalAlwaysBeatsPrimary()` 而非 `func testArbiter1()`
3. **隔离性**：每个测试使用独立的 UserDefaults suite 和临时目录
4. **参数化**：跨模块的验证使用 `@Test(arguments:)`
5. **契约优先**：为新模块添加契约测试，确保其遵守 `ModuleContract`
6. **反回归**：修复 bug 时先写失败测试，再修复代码

## 相关文档

- [架构总览](Architecture.md) — 测试在架构中的位置
- [Command/Effect 管线](CommandEffectPipeline.md) — 理解 Effect 测试
- [能力安全体系](Capabilities.md) — 理解 Capability 测试
- [投影与快照](ProjectionAndSnapshot.md) — 理解 Projection 和 Envelope 测试
