# Widget 集成

GlyphBar 通过共享 App Group 容器将模块数据传递给 WidgetKit 扩展。模块发布 `SnapshotEnvelope`，经 `WidgetEnvelopeBridge` 转换后写入 App Group，Widget 扩展在 timeline tick 时读取并渲染。

## 架构概览

```
Module.handle(.refresh)
    → DomainTransition(effects: [.publishSnapshot(envelope)])
    → EffectExecutor.execute(.publishSnapshot)
    → WidgetDataBridge.publish(envelope)
    → WidgetEnvelopeBridge: SnapshotEnvelope → WidgetModuleSnapshot
    → 写入 App Group UserDefaults
    → WidgetCenter.shared.reloadAllTimelines()
    → Widget 扩展: ModuleTimelineProvider 读取 App Group
    → 渲染 Widget UI
```

Widget 扩展与主 App 运行在不同进程中，通过 App Group UserDefaults 共享数据。`SnapshotEnvelope` 和 `ProjectionSet` 仅在主 App target 编译，Widget 扩展通过共享的 `WidgetModuleSnapshot` 类型读取数据。

## 数据流详解

### 1. 模块发布 Snapshot

模块在 `handle(.refresh)` 中返回 `DomainTransition`，包含 `.publishSnapshot(envelope)` Effect：

```swift
return DomainTransition(
    effects: [.publishSnapshot(envelope)],
    health: .healthy,
    refreshProjection: true
)
```

### 2. EffectExecutor 执行

`EffectExecutor` 将 `.publishSnapshot` 映射到 `WidgetDataBridge.publish(envelope)`：

```swift
case .publishSnapshot(let envelope):
    widgetBridge.publish(envelope)
```

### 3. WidgetEnvelopeBridge 转换

`WidgetEnvelopeBridge` 是 `WidgetDataBridge` 的扩展，从 `SnapshotEnvelope` 提取 `WidgetProjection` 并转换为 `WidgetModuleSnapshot`：

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

### 4. 写入 App Group

数据写入共享的 App Group UserDefaults：

```swift
let defaults = UserDefaults(suiteName: "group.com.wenjiexu.GlyphBar")
defaults?.set(encodedSnapshot, forKey: "widget.<moduleID>")
```

### 5. 触发 Timeline 刷新

```swift
WidgetCenter.shared.reloadAllTimelines()
```

这通知 WidgetKit 重新请求 timeline，Widget 扩展的 `ModuleTimelineProvider` 将被调用。

### 6. Widget 扩展读取

`ModuleTimelineProvider` 从 App Group 读取 `WidgetModuleSnapshot`：

```swift
func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let defaults = UserDefaults(suiteName: "group.com.wenjiexu.GlyphBar")
    let snapshot: WidgetModuleSnapshot? = readFromDefaults(defaults, forKey: "widget.<moduleID>")
    // 构建 Timeline Entry
    // completion(timeline)
}
```

## 共享类型

`WidgetShared/` 目录包含主 App 和 Widget 扩展共享的类型：

### WidgetModuleSnapshot

```swift
struct WidgetModuleSnapshot: Codable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let symbol: String?
    let severity: WidgetSeverity
    let metrics: [WidgetMetric]?
    let notes: [String]?
    let timestamp: Date
    let unavailableReason: String?
}
```

| 字段 | 类型 | 含义 |
|------|------|------|
| `id` | `String` | 模块 ID |
| `title` | `String` | 状态标题 |
| `subtitle` | `String?` | 状态副标题 |
| `symbol` | `String?` | SF Symbol 图标名 |
| `severity` | `WidgetSeverity` | 严重度 |
| `metrics` | `[WidgetMetric]?` | 指标列表 |
| `notes` | `[String]?` | 备注列表 |
| `timestamp` | `Date` | 数据时间戳 |
| `unavailableReason` | `String?` | 不可用原因 |

### WidgetMetric

```swift
struct WidgetMetric: Codable, Identifiable {
    let id: String
    let label: String
    let value: String
    let unit: String?
}
```

### WidgetSeverity

```swift
enum WidgetSeverity: String, Codable {
    case normal
    case info
    case warning
    case critical
}
```

### AppGroup

```swift
struct AppGroup {
    static let identifier = "group.com.wenjiexu.GlyphBar"
    static func defaults() -> UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
```

## 内置 Widget

GlyphBar 包含 5 个内置 Widget，每个对应一个内置模块：

| Widget | 模块 | 展示内容 |
|--------|------|---------|
| `ClockWidget` | ClockModule | 当前时间、世界时钟 |
| `CounterWidget` | CounterModule | 当前计数值 |
| `NetworkMockWidget` | NetworkMockModule | 网络状态 |
| `NotesQuickWidget` | NotesQuickModule | 备忘录内容 |
| `SystemPulseWidget` | SystemPulseModule | CPU/内存/磁盘使用率 |

每个 Widget 使用 `ModuleTimelineProvider` 从 App Group 读取对应模块的 `WidgetModuleSnapshot`。

## ModuleTimelineProvider

`ModuleTimelineProvider` 是所有内置 Widget 共用的 timeline 提供者：

1. 从 App Group UserDefaults 读取 `WidgetModuleSnapshot`
2. 如果数据可用，构建正常 Entry
3. 如果数据不可用，构建占位 Entry（显示 "Unavailable"）
4. 设置 timeline 的 `reloadPolicy`：根据 snapshot 的 `timestamp` 和模块的刷新间隔决定下次刷新时间

## 第三方模块的 Widget 策略

### 当前限制

WidgetKit 要求 Widget kind 在编译期确定，无法在运行时动态注册新的 Widget 扩展。因此：

- **第三方模块无法添加自定义 WidgetKit 扩展**
- 第三方模块的 `widgets` 描述符仅声明模块愿意提供 Widget 数据
- 实际 Widget 渲染依赖 GlyphBar 的内置 Widget 或未来的通用模板

### 数据提供

第三方模块可以通过 `widgets` 描述符声明 Widget 数据，`DeclarativeModule` 会将 snapshot 数据写入 App Group。如果未来 GlyphBar 提供通用模板 Widget，这些数据将自动可用。

### 未来方向

- **通用模板 Widget**：GlyphBar 可能提供一个通用 Widget，根据模块的 `WidgetProjection` 动态渲染
- **Widget kind codegen**：P4 可能通过 codegen 预定义 kind 集合，支持第三方模块注册 Widget kind
- **IngestionAPI**：P4 允许外部工具（CLI/Shortcuts/CI）推送 snapshot 数据，间接更新 Widget

## Widget 数据的 Schema 版本化

`WidgetModuleSnapshot` 的结构可能随版本演进。P3 引入 schema 版本化：

- `WidgetModuleSnapshot` 将添加 `schemaVersion` 字段
- Widget 扩展检查版本号，不匹配时降级处理（显示基本标题/副标题）
- 主 App 在写入时使用当前版本号

## OpenGlyphBarIntent

GlyphBar 提供 `OpenGlyphBarIntent`（Siri Shortcuts 集成），允许用户通过 Shortcuts 打开 App：

```swift
struct OpenGlyphBarIntent: AppIntent {
    static var title: LocalizedStringResource = "Open GlyphBar"
    static var description = IntentDescription("Opens the GlyphBar menu bar app")

    func perform() async throws -> some IntentResult {
        // 激活 GlyphBar
    }
}
```

## 相关文档

- [架构总览](Architecture.md) — 五平面架构
- [投影与快照](ProjectionAndSnapshot.md) — SnapshotEnvelope 和 WidgetProjection
- [Command/Effect 管线](CommandEffectPipeline.md) — .publishSnapshot Effect 的执行
- [声明式模块开发](ModuleDevelopment.md) — 第三方模块的 Widget 策略
- [安全与权限](SecurityAndPermissions.md) — App Group 数据隔离
