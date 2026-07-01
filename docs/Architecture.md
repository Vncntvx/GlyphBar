# GlyphBar 架构总览

GlyphBar 是一个原生 macOS SwiftUI 菜单栏模块化信息中心，采用**微内核 + 单向数据流 + Actor 监督 + 能力安全**的架构范式。

## 设计哲学

GlyphBar 的架构围绕一个核心信念：**模块拥有领域状态，不拥有应用平台**。这意味着：

- 模块只处理自己的业务逻辑，不直接访问系统 API
- 模块通过声明式契约与平台交互，平台负责调度和执行
- 模块之间互不感知，通过内核间接通信

## 四条不可突破边界

1. **模块拥有领域状态，不拥有应用平台** — 模块不直接调用 `NSPasteboard`、`URLSession`、`NSWorkspace`、`UserDefaults.standard` 等平台 API
2. **模块提出 Effects，不直接执行全局副作用** — 所有副作用通过 `Effect` 枚举声明，由 `EffectExecutor` 统一执行
3. **模块提交展示候选，不决定最终菜单栏内容** — 模块通过 `StatusCandidate` 提交候选，由 `PresentationArbiter` 仲裁决定
4. **内核管理生命周期与安全，不理解模块业务** — 内核只关心 Command/Effect/Capability/Health，不关心模块的具体业务语义

## 五平面架构

```
┌─────────────────────────────────────────────────────────┐
│                    Presentation                          │
│   PresentationArbiter · StatusItemRenderer              │
│   ModulePanelHost · ModuleContribution                  │
├─────────────────────────────────────────────────────────┤
│                    Projection                            │
│   SnapshotEnvelope · ProjectionSet · ProjectionBuilder  │
│   WidgetEnvelopeBridge                                   │
├─────────────────────────────────────────────────────────┤
│                    Kernel                                │
│   ModuleContract · Command · Effect · EffectExecutor    │
│   GrantedCapabilities · CapabilityFactory · ModuleBridge│
│   ModuleSupervisor · ModuleActor · ModuleOperationalState│
├─────────────────────────────────────────────────────────┤
│                    Execution                             │
│   RefreshScheduler · SchedulerClock · RefreshBudget     │
│   SystemEnvironmentMonitor · PresentationTicker         │
├─────────────────────────────────────────────────────────┤
│                    Control Plane                         │
│   DesiredModuleState · ObservedModuleState · Reconciler │
│   Package · ModuleDefinition · ModuleInstance · Installer│
└─────────────────────────────────────────────────────────┘
```

| 平面 | 职责 | 关键类型 |
|------|------|----------|
| **Presentation** | 菜单栏渲染、面板展示、状态仲裁 | `PresentationArbiter`、`StatusItemRenderer`、`ModulePanelHost` |
| **Projection** | 数据投影、快照封装、Widget 桥接 | `SnapshotEnvelope`、`ProjectionSet`、`WidgetEnvelopeBridge` |
| **Kernel** | 模块契约、命令/效果管线、能力授予、生命周期 | `ModuleContract`、`Command`、`Effect`、`EffectExecutor`、`GrantedCapabilities` |
| **Execution** | 刷新调度、环境感知、展示 Tick | `RefreshScheduler`、`SystemEnvironmentMonitor`、`PresentationTicker` |
| **Control Plane** | 期望/观测状态分离、调和、安装/升级 | `Reconciler`、`Installer`、`DesiredModuleState`、`ObservedModuleState` |

平面间只通过协议交互，不直接引用具体实现。

## 核心数据流

所有模块行为遵循**单向数据流**：

```
外部刺激 → Command → ModuleContract.handle() → DomainTransition → EffectExecutor → 副作用
                                        ↓
                              ProjectionSet → SnapshotEnvelope → WidgetBridge → WidgetKit
                                        ↓
                              StatusCandidate → PresentationArbiter → PresentationDecision → NSStatusItem
```

1. **外部刺激**（用户操作、定时器、网络变化等）被归一化为 `Command`
2. **内核**将 Command 分发给对应模块的 `handle(command:capabilities:bridge:)` 方法
3. **模块**返回 `DomainTransition`，包含 `Effect` 列表、可选的 `ModuleHealth` 更新、以及投影刷新标记
4. **EffectExecutor** 统一执行所有副作用（剪贴板、URL、Widget 发布等）
5. 模块的 `buildProjection()` 和 `statusCandidates()` 分别产出投影数据和展示候选

模块**永远不**直接执行副作用。`ModuleBridge.submit()` 是模块提交 Effect 的唯一通道。

## 目录结构

```
GlyphBar/
├── App/                    # 应用协调层
│   ├── AppDelegate.swift   # 启动入口，URL scheme 注册
│   ├── GlyphBarApp.swift   # SwiftUI @main，Settings scene
│   ├── AppEnvironment.swift # 组合根，创建所有基础设施并注册模块
│   ├── StatusBar/          # StatusItemController（交互层）
│   ├── Panel/              # QuickPanelCoordinator + QuickPanelRootView
│   ├── Settings/           # 设置界面（General/MenuBar/Modules/Privacy/Advanced/About）
│   ├── Menu/               # 菜单栏菜单
│   ├── Routing/            # DeepLinkRouter
│   └── Windows/            # 日志窗口等
├── Kernel/                 # 微内核
│   ├── Contracts/          # ModuleContract、DomainTransition、ModuleHealth
│   ├── Command/            # Command 枚举
│   ├── Effect/             # Effect 枚举、EffectExecutor
│   ├── Capabilities/       # Capability 协议、GrantedCapabilities、CapabilityFactory
│   │                        ModuleSecretStore、ModuleCacheNamespace、ModuleSettingsNamespace
│   │                        NetworkCapability、FileImportCapability、ClipboardCapability
│   │                        LoggingCapability、SystemMetricsCapability、CapabilityBroker
│   └── Lifecycle/          # ModuleSupervisor、ModuleActor、ModuleHarness
│                            ModuleOperationalState、GenerationToken、CancellationScope
├── Projection/             # 投影层
│   ├── SnapshotEnvelope.swift
│   ├── ProjectionSet.swift
│   ├── ProjectionBuilder.swift
│   ├── Projections/        # Summary/Metrics/List/Chart/Widget/PanelModel 投影类型
│   └── WidgetBridge/       # WidgetEnvelopeBridge
├── Presentation/           # 展示层
│   ├── Arbiter/            # PresentationArbiter、StatusCandidate、HysteresisTracker
│   │                        ArbitrationPolicy、PresentationDecision
│   ├── Host/               # ModulePanelHost、ModuleContribution、PanelHostContext
│   └── StatusBar/          # StatusItemRenderer
├── Platform/               # 平台扩展（P4）
│   ├── Ingestion/          # IngestionAPI（CLI/Shortcuts/CI 数据发布）
│   ├── Trust/              # TrustLevel
│   └── Isolation/          # XPCModuleHost、XPCModuleProtocol、XPCModuleProxy
├── Core/                   # 遗留运行时（逐步迁移至 Kernel/Projection/Presentation）
│   ├── Runtime/            # ModuleRuntime、ModuleRegistry
│   ├── Modules/            # ModuleTypes（ModuleManifest、ExternalModuleManifest 等）
│   ├── Storage/            # CacheStore、AppSettingsStore
│   ├── Permissions/        # PermissionCenter
│   ├── Refresh/            # RefreshScheduler（旧版）
│   ├── Status/             # StatusComposer、StatusRotationEngine（旧版）
│   └── Logging/            # GlyphLogger
├── DesignSystem/           # 可复用 SwiftUI 组件
├── Modules/                # 内置模块
│   ├── ClockModule/
│   ├── CounterModule/
│   ├── DeepSeekModule/
│   ├── NotesQuickModule/
│   ├── SystemPulseModule/
│   └── NetworkMockModule/
├── WidgetShared/           # 主 App 与 Widget 扩展共享的类型
│   ├── AppGroup.swift
│   ├── WidgetSnapshotModels.swift
│   └── WidgetDataBridge.swift
└── GlyphBarWidgets/        # WidgetKit 扩展
    ├── GlyphBarWidgetsBundle.swift
    └── Providers/ModuleTimelineProvider.swift
```

## 组合根

`AppEnvironment` 是当前的组合根（singleton），负责：

1. 创建所有基础设施：`GlyphLogger`、`CacheStore`、`PermissionCenter`、`AppSettingsStore`、`WidgetDataBridge`、`CapabilityFactory`
2. 通过 `ModuleRegistry` 注册所有内置模块，每个模块使用 `CapabilityFactory.makeCapabilities(for:manifest:bridge:)` 注入正确的能力集
3. 创建 `ModuleRuntime`，连接 `openSettingsAction` 到设置界面
4. 创建 UI 协调器：`AppMenuCoordinator`、`QuickPanelCoordinator`、`StatusItemController`、`DeepLinkRouter`、`LogsWindowCoordinator`
5. 首次启动时按 `manifest.priority` 排序模块

未来（P3）将拆分为 `CompositionRoot`，按五平面接线，`AppEnvironment` 退化为薄壳或删除。

## 模块生命周期

每个模块经历以下状态机：

```
installed → loaded → starting → idle/refreshing/ready
                                    ↓
                            degraded/suspended/failed
                                    ↓
                              stopping → uninstalled
```

| 状态 | 含义 |
|------|------|
| `installed` | 已注册但未加载 |
| `loaded` | 实例已创建 |
| `starting` | 正在执行首次 refresh |
| `idle` | 空闲，等待下次 refresh |
| `refreshing` | 正在执行 refresh |
| `ready` | 刷新成功，数据可用 |
| `degraded` | 功能降级（如缺少密钥、网络错误） |
| `suspended` | 被暂停（如权限被撤销） |
| `failed` | 不可恢复的失败 |
| `stopping` | 正在停止 |
| `uninstalled` | 已卸载 |

`ModuleSupervisor` 管理所有模块的 `ModuleActor` 实例，确保模块间并行、模块内串行。失败时按策略处理：首次失败重试（5s backoff），重复失败降级/暂停。

## 扩展层级

GlyphBar 支持三级扩展模型：

| 层级 | 类型 | 信任等级 | 代码执行 | 隔离方式 |
|------|------|----------|----------|----------|
| **Level 1** | 内置编译模块 | `.bundled` | 同进程，直接调用 | 编译时契约 |
| **Level 2** | 声明式 JSON 包 | `.unsignedLocal` | 无原生代码，宿主解释 | 数据隔离 |
| **Level 3** | XPC 隔离原生模块 | `.signed` | 独立 XPC 进程 | 进程隔离 + 能力代理 |

- **Level 1**：随 App 编译，实现 `TypedModuleContribution`，使用泛型 `@ViewBuilder` 面板
- **Level 2**：`.glyphbarmodule` 目录包，包含 `glyphbar-module.json` manifest 和 `snapshot.json` 数据，由 `DeclarativeModule` 解释渲染
- **Level 3**（P4）：签名原生模块在独立 XPC 进程运行，所有平台访问经能力代理回调主 App

## 相关文档

| 文档 | 内容 |
|------|------|
| [Command/Effect 管线](CommandEffectPipeline.md) | Command 和 Effect 的完整参考 |
| [能力安全体系](Capabilities.md) | GrantedCapabilities 和 CapabilityFactory 详解 |
| [投影与快照](ProjectionAndSnapshot.md) | ProjectionSet、SnapshotEnvelope、ModuleHealth |
| [状态栏仲裁](PresentationArbiter.md) | StatusCandidate、仲裁算法、HysteresisTracker |
| [内置模块参考](BuiltInModules.md) | 6 个内置模块的功能和配置 |
| [声明式模块开发](ModuleDevelopment.md) | 第三方 JSON 包开发指南 |
| [原生模块开发](NativeModuleDevelopment.md) | 内置模块和 XPC 模块开发指南 |
| [Manifest 字段参考](ModuleManifest.md) | glyphbar-module.json 和 snapshot.json 完整字段 |
| [Widget 集成](WidgetIntegration.md) | Widget 数据流和开发指南 |
| [深度链接](DeepLinks.md) | glyphbar:// URL scheme 路由 |
| [安全与权限](SecurityAndPermissions.md) | 信任等级、权限系统、存储安全 |
| [测试指南](TestingGuide.md) | Swift Testing 测试模式和契约测试 |
