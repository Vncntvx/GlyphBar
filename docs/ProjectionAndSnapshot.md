# 投影与快照

GlyphBar 使用**强类型投影**（Projection）和**版本化快照信封**（SnapshotEnvelope）来描述模块的状态快照。投影是模块状态的结构化、可丢弃视图；快照信封为投影添加了元数据（时间、健康、新鲜度）用于传输和缓存。

## 设计原则

> **Snapshot 是可丢弃投影，不是数据库。** 投影数据可以随时从模块领域状态重建，不应作为持久化存储使用。

| 原则 | 含义 |
|------|------|
| 强类型优于类型擦除 | `ProjectionSet` 使用可选 struct 字段，编译器强制 schema |
| 可丢弃 | 投影可随时从模块重建，不保证持久性 |
| 版本化 | `SnapshotEnvelope` 携带 `schemaVersion`，支持向前兼容 |
| 信封封装 | `SnapshotEnvelope` 包裹 `ProjectionSet`，添加元数据用于跨进程/跨组件传输 |

## ProjectionSet

`ProjectionSet` 是模块状态的结构化投影集合，使用**可选字段**而非类型擦除数组：

```swift
struct ProjectionSet: Sendable {
    var summary: SummaryProjection?
    var metrics: MetricsProjection?
    var list: ListProjection?
    var chart: ChartProjection?
    var statusCandidates: [StatusCandidate]
    var widget: WidgetProjection?
    var panelModel: PanelModelProjection?
}
```

这种设计让编译器强制执行 schema——每个投影类型都是明确的可选字段，而不是 `any SnapshotProjection` 存入数组后运行时才发现类型错误。

### SummaryProjection

```swift
struct SummaryProjection: Sendable {
    let title: String
    let subtitle: String
    let systemImage: String
}
```

模块的核心摘要信息，用于菜单栏展示和面板标题。

### MetricsProjection

```swift
struct MetricsProjection: Sendable {
    let metrics: [Metric]
}

struct Metric: Sendable, Identifiable {
    let id: String
    let label: String
    let value: Double
    let unit: String
    let systemImage: String?
}
```

结构化指标数据，替代旧的 `[String: Double]` 无类型字典。每个 metric 有明确的 id、标签、值和单位。

### ListProjection

```swift
struct ListProjection: Sendable, Codable {
    let items: [Item]
}

struct Item: Sendable, Identifiable, Codable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String?
    let severity: Severity?
}
```

列表数据，用于展示条目列表（如世界时钟列表、网络接口列表）。

### ChartProjection

```swift
struct ChartProjection: Sendable {
    let series: [Series]
}

struct Series: Sendable, Identifiable {
    let id: String
    let label: String
    let color: String?
    let points: [Point]
}

struct Point: Sendable {
    let x: Double
    let y: Double
}
```

图表数据，用于绘制折线图、面积图等。

### WidgetProjection

```swift
struct WidgetProjection: Sendable {
    let title: String
    let subtitle: String
    let systemImage: String
    let severity: Severity
    let metrics: [MetricsProjection.Metric]
    let notes: [String]
    let timestamp: Date
    let unavailableReason: String?
}
```

WidgetKit 专用的精简投影，提取自完整投影中适合小部件展示的数据。包含 severity、timestamp 和 unavailableReason，供 Widget 视图决定展示方式。

### PanelModelProjection

```swift
struct PanelModelProjection: Sendable, Codable {
    // Codable 声明式面板布局
    // 支持 text/metric/chart/list/action 元素
}
```

Codable 声明式面板布局，用于第三方模块和 XPC 模块。这些模块无法直接返回 SwiftUI View，因此通过声明式 schema 描述面板结构，由主 App 的通用渲染器绘制。

### StatusCandidates

```swift
var statusCandidates: [StatusCandidate]
```

直接嵌入 ProjectionSet 中的状态栏候选列表。详见 [状态栏仲裁](PresentationArbiter.md)。

## SnapshotEnvelope

`SnapshotEnvelope` 是包裹 `ProjectionSet` 的信封，添加传输和缓存所需的元数据：

```swift
struct SnapshotEnvelope: Sendable, Identifiable {
    let id: String              // 模块实例 ID
    let schemaVersion: Int      // schema 版本号
    let capturedAt: Date        // 采集时间
    let validUntil: Date?       // TTL 过期时间（nil = 永不过期）
    let freshness: SnapshotFreshness
    let health: ModuleHealth
    let projections: ProjectionSet
}
```

| 字段 | 类型 | 含义 |
|------|------|------|
| `id` | `String` | 模块实例标识符 |
| `schemaVersion` | `Int` | ProjectionSet 结构版本，当字段类型变化时递增 |
| `capturedAt` | `Date` | 快照采集时间戳 |
| `validUntil` | `Date?` | 过期时间，nil 表示永不过期 |
| `freshness` | `SnapshotFreshness` | 数据新鲜度 |
| `health` | `ModuleHealth` | 模块健康状态 |
| `projections` | `ProjectionSet` | 实际的投影数据 |

### SnapshotFreshness

```swift
enum SnapshotFreshness: Sendable {
    case fresh                           // 数据是新鲜的
    case stale(Date)                    // 数据过期，附带过期时间
    case unavailable(String)            // 数据不可用，附带原因描述
}
```

- `.fresh`：刚从模块获取的最新数据
- `.stale(_:)`：数据已过期但仍可展示（如网络断开时显示缓存数据）
- `.unavailable(_:)`：数据完全不可用（如首次启动无缓存）

### Schema 版本化

`schemaVersion` 用于向前兼容：

- 当 `ProjectionSet` 的字段类型发生变化时递增
- Consumer（如 Widget 扩展）检查版本号，不匹配时降级处理

## ModuleHealth

`ModuleHealth` 将业务信号与健康状态分离：

```swift
enum ModuleHealth: Sendable, Equatable {
    case healthy
    case degraded(reason: HealthReason)
    case unavailable(reason: HealthReason)
    case blocked(reason: HealthReason)
    case misconfigured(reason: HealthReason)
    case suspended
}

enum HealthReason: Sendable, Equatable {
    case missingSecret(String)           // 缺少密钥（如 API Key）
    case networkError(String)            // 网络错误
    case authFailed                      // 认证失败
    case rateLimited                     // 被限流
    case staleCache(age: TimeInterval)   // 缓存过期
    case permissionDenied(CapabilityKey)  // 权限被拒
    case unknown(String)                 // 未知错误
}
```

| 健康状态 | 含义 | 是否不健康 | 是否终态 |
|---------|------|-----------|---------|
| `.healthy` | 正常运行 | 否 | 否 |
| `.degraded(reason:)` | 功能降级，部分功能不可用 | 是 | 否 |
| `.unavailable(reason:)` | 完全不可用 | 是 | 是 |
| `.blocked(reason:)` | 被阻止（如权限被撤销） | 是 | 是 |
| `.misconfigured(reason:)` | 配置错误（如缺少 API Key） | 是 | 是 |
| `.suspended` | 被暂停 | 是 | 是 |

**关键区别**：`.degraded` 是非终态（可能恢复），而 `.unavailable`/`.blocked`/`.misconfigured`/`.suspended` 是终态（需要用户干预）。

### 健康状态与展示的关系

- `.healthy`：正常展示数据
- `.degraded`：展示缓存数据，标记为 stale
- `.unavailable`/`.blocked`/`.misconfigured`/`.suspended`：展示降级候选（"模块不可用"），由 `PresentationArbiter` 决定是否在菜单栏显示

## ProjectionBuilder

`ProjectionBuilder` 在 `ModuleSnapshot` 和 `ProjectionSet`/`SnapshotEnvelope` 之间桥接：

```swift
enum ProjectionBuilder {
    static func build(from snapshot: ModuleSnapshot, health: ModuleHealth) -> ProjectionSet
    static func buildEnvelope(from snapshot: ModuleSnapshot, health: ModuleHealth, validUntil: Date?) -> SnapshotEnvelope
    static func buildSnapshot(from envelope: SnapshotEnvelope) -> ModuleSnapshot
}
```

- `build(from:)`：从 `ModuleSnapshot` 构建 `ProjectionSet`，包括 summary、metrics、list、widget、statusCandidates
- `buildEnvelope(from:)`：从 `ModuleSnapshot` 构建 `SnapshotEnvelope`
- `buildSnapshot(from:)`：从 `SnapshotEnvelope` 重建 `ModuleSnapshot`，用于 runtime snapshot 缓存

## Widget 数据流

投影数据最终流向 WidgetKit 的完整路径：

```
Module.handle(.refresh)
    → DomainTransition(effects: [.publishSnapshot(envelope)])
    → EffectExecutor.execute(.publishSnapshot(envelope))
    → CacheStore.save(snapshot)
    → WidgetDataBridge.publish(envelope)
    → WidgetEnvelopeBridge: 提取 WidgetProjection → 转为 WidgetModuleSnapshot
    → 写入 App Group UserDefaults (group.com.wenjiexu.GlyphBar)
    → WidgetCenter.shared.reloadAllTimelines()
    → Widget 扩展: ModuleTimelineProvider 在 timeline tick 读取 App Group
    → 渲染 ModuleWidgetView
```

### WidgetEnvelopeBridge

`WidgetEnvelopeBridge` 是 `WidgetDataBridge` 的扩展，将 `SnapshotEnvelope` 转换为 Widget 可用的 `WidgetModuleSnapshot`：

```swift
extension WidgetDataBridge {
    func publish(_ envelope: SnapshotEnvelope) {
        // 从 envelope.projections.widget 提取 WidgetProjection
        // 转换为 WidgetModuleSnapshot
        // 写入 App Group UserDefaults
        // 调用 WidgetCenter.shared.reloadAllTimelines()
    }
}
```

`SnapshotEnvelope` 和 `ProjectionSet` 仅在主 App target 编译，Widget 扩展通过共享的 `WidgetModuleSnapshot` 类型读取数据。

## 相关文档

- [架构总览](Architecture.md) — 五平面架构
- [Command/Effect 管线](CommandEffectPipeline.md) — 数据如何触发投影构建
- [状态栏仲裁](PresentationArbiter.md) — StatusCandidate 如何参与仲裁
- [Widget 集成](WidgetIntegration.md) — Widget 数据流的详细说明
- [原生模块开发](NativeModuleDevelopment.md) — 如何实现 buildProjection()
