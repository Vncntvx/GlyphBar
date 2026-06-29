# 状态栏仲裁

GlyphBar 的菜单栏状态由 `PresentationArbiter` 统一决定。模块通过 `StatusCandidate` 提交展示候选，仲裁器根据优先级、严重度、信任等级、TTL、滞回等规则选出最终显示内容。**模块提交候选，不决定最终菜单栏内容。**

## 设计动机

在旧架构中，`StatusComposer` 只做简单的优先级排序，`StatusRotationEngine` 的 `tick` 永远返回 `.normal`，导致：

- 无防闪烁机制，状态栏频繁切换
- 无 TTL 过期清理，过期候选持续显示
- 第三方模块可抢占内置模块的展示位置
- 无最短展示时长，瞬间切换导致用户无法阅读

`PresentationArbiter` 解决了这些问题，提供了完整的仲裁机制。

## StatusCandidate — 展示候选

每个模块通过 `statusCandidates()` 返回一组候选：

```swift
struct StatusCandidate: Sendable, Identifiable {
    let id: String                    // 去重键
    let sourceModule: String          // 来源模块 ID
    let semanticRole: SemanticRole    // 语义角色
    let severity: Severity            // 严重度
    let priority: Int                 // 优先级 (0...1000)
    let text: String                  // 展示文本
    let icon: String                  // SF Symbol 名称
    let createdAt: Date               // 创建时间
    let expiresAt: Date?              // 过期时间（TTL）
    let interruptPolicy: InterruptPolicy  // 抢占策略
    let trustLevel: TrustLevel        // 信任等级
}
```

### 字段详解

| 字段 | 类型 | 含义 | 约束 |
|------|------|------|------|
| `id` | `String` | 去重键，相同 id 的候选只保留最新 | 必须稳定、唯一 |
| `sourceModule` | `String` | 来源模块 ID | 必须与 `manifest.id` 一致 |
| `semanticRole` | `SemanticRole` | 候选的语义角色 | 见下表 |
| `severity` | `Severity` | 候选的严重度 | `.normal` / `.info` / `.warning` / `.critical` |
| `priority` | `Int` | 同语义角色内的排序优先级 | 0...1000，越大越优先 |
| `text` | `String` | 菜单栏展示文本 | 非空 |
| `icon` | `String` | SF Symbol 图标名 | 有效的 SF Symbol |
| `createdAt` | `Date` | 候选创建时间 | 用于时间排序 |
| `expiresAt` | `Date?` | 过期时间，nil 表示永不过期 | 过期后被过滤 |
| `interruptPolicy` | `InterruptPolicy` | 抢占行为 | 见下表 |
| `trustLevel` | `TrustLevel` | 信任等级，影响排序 | 见下表 |

### SemanticRole

```swift
enum SemanticRole: Sendable {
    case primary          // 主要信息（默认角色）
    case alert            // 告警信息（如网络断开、CPU 过高）
    case informational    // 信息提示（如"已复制"）
    case rotation         // 轮换候选（如世界时钟列表）
}
```

| 角色 | 含义 | 典型场景 |
|------|------|----------|
| `.primary` | 模块的主要状态展示 | Clock 显示当前时间 |
| `.alert` | 需要用户关注的告警 | SystemPulse 的 CPU 过高警告、NetworkMock 的网络断开 |
| `.informational` | 临时信息提示 | 复制成功的短暂提示 |
| `.rotation` | 参与轮换展示的候选 | Clock 的多个世界时钟 |

### InterruptPolicy

```swift
enum InterruptPolicy: Sendable {
    case normal       // 遵守最短展示时长，不强制打断
    case preempt      // 立即打断当前展示
    case persistent   // 不被低严重度候选抢占
}
```

| 策略 | 行为 |
|------|------|
| `.normal` | 遵守 `minimumDisplayDuration`，等当前候选展示完毕后再切换 |
| `.preempt` | 无视最短展示时长，立即抢占（如 `.critical` + `.alert` 告警） |
| `.persistent` | 一旦展示，不被更低严重度的候选抢占（如持续的网络断开提示） |

### TrustLevel

```swift
enum TrustLevel: Sendable, Comparable {
    case untrusted       // 不可信（rank 0）
    case unsignedLocal   // 未签名的本地包（rank 1）
    case bundled         // 内置模块（rank 2）
    case signed          // 已签名模块（rank 3）
}
```

信任等级作为排序的决胜因素（tiebreaker）：当两个候选的严重度和优先级相同时，信任等级高的优先。这保证了内置模块不会被第三方模块的候选饿死。

## 仲裁算法

`PresentationArbiter` 的仲裁过程：

```
submit(candidates, now) → 更新候选池
tick(now) → 产生 PresentationDecision
```

### Step 1：去重

按 `id` 去重，相同 id 的候选只保留最新提交的。

### Step 2：过滤过期

移除 `expiresAt < now` 的候选。

### Step 3：排序

候选按以下顺序排序（降序）：

1. **severity** — 严重度高的优先（`.critical` > `.warning` > `.info` > `.normal`）
2. **priority** — 同严重度下优先级高的优先（0...1000，越大越优先）
3. **trustLevel** — 同优先级下信任等级高的优先（`.signed` > `.bundled` > `.unsignedLocal` > `.untrusted`）
4. **createdAt** — 同信任等级下先创建的优先（FIFO）

### Step 4：最短展示时长

当前候选必须展示至少 `minimumDisplayDuration`（默认 3 秒），除非新候选的 `interruptPolicy` 为 `.preempt`。

### Step 5：抢占策略

- `.preempt` 候选立即打断当前展示，无视最短展示时长
- `.persistent` 候选一旦展示，不被更低严重度的候选抢占

### Step 6：轮换

在每次 `tick()` 调用时：

1. **非轮换候选优先**：如果存在 `.primary`/`.alert`/`.informational` 候选，优先展示
2. **轮换候选循环**：如果没有更高优先级的候选，`.rotation` 候选按 `rotationIndex` 循环展示

轮换由 `PresentationTicker`（P2）定时驱动 `tick()`。

## HysteresisTracker — 滞回防闪烁

`HysteresisTracker` 使用双阈值滞回机制防止临界值频繁切换：

```swift
struct HysteresisTracker {
    let enterThreshold: Double        // 进入阈值
    let exitThreshold: Double         // 退出阈值（低于进入阈值）
    let minDurationToEnter: TimeInterval  // 进入前的最短持续时间
    let minDurationToExit: TimeInterval   // 退出前的最短持续时间

    private(set) var currentState: Bool = false
    private(set) var since: Date = Date()

    mutating func update(value: Double, now: Date) -> Bool
}
```

**工作原理**：

```
                    enterThreshold
                        │
  ──────────────────────┼──────────────────
           ↑            │           ↑
           │   HYSTERESIS BAND     │
           │            │           │
  ──────────────────────┼──────────────────
                        │
                   exitThreshold

  状态从 false → true：value >= enterThreshold 且持续 minDurationToEnter
  状态从 true → false：value < exitThreshold 且持续 minDurationToExit
```

**典型应用**：SystemPulseModule 的 CPU 使用率告警——CPU 在 80% 附近波动时，不会因为 79%↔81% 的抖动导致告警频繁开关。

`PresentationArbiter` 为每个候选 ID 维护一个 `HysteresisTracker`（`hysteresis: [String: HysteresisTracker]`）。

## ArbitrationPolicy — 可注入的仲裁策略

```swift
protocol ArbitrationPolicy: Sendable {
    func compare(_ a: StatusCandidate, _ b: StatusCandidate) -> ComparisonResult
    func shouldPreempt(current: PresentationDecision, candidate: StatusCandidate, now: Date) -> Bool
    func minDisplayTime(for role: StatusCandidate.SemanticRole) -> TimeInterval
    func cooldown(for severity: Severity) -> TimeInterval
}
```

`DefaultArbitrationPolicy` 实现了上述默认仲裁算法。P4 支持注入自定义策略，例如：

- 为不同语义角色设置不同的最短展示时长
- 为不同严重度设置冷却期
- 自定义抢占规则

## PresentationDecision — 仲裁结果

```swift
struct PresentationDecision: Equatable {
    var title: String
    var systemImage: String
    var severity: Severity
    var tooltip: String
    var accessibilityLabel: String
    var accessibilityHint: String
    var sourceModule: String?
    var isCritical: Bool
}
```

`PresentationDecision` 是 `Equatable` 的，`StatusItemRenderer` 只在决策变化时更新 `NSStatusItem`，避免无谓的重绘。

## StatusItemRenderer — 渲染到菜单栏

`StatusItemRenderer` 将 `PresentationDecision` 写入 `NSStatusItem.button`：

- `title` → `button.title`
- `systemImage` → `button.image`（SF Symbol）
- `tooltip` → `button.toolTip`
- `accessibilityLabel` → `button.accessibilityLabel`
- `accessibilityHint` → `button.accessibilityHint`

`StatusItemController`（交互层）持有 `NSStatusItem` 和 `StatusItemRenderer`，监听 Arbiter 的决策变化并调用渲染器。

## 模块如何参与仲裁

模块通过 `statusCandidates()` 返回候选列表：

```swift
func statusCandidates() -> [StatusCandidate] {
    let now = Date()
    return [
        StatusCandidate(
            id: "clock.primary",
            sourceModule: manifest.id,
            semanticRole: .primary,
            severity: .normal,
            priority: manifest.priority,
            text: currentTimeString,
            icon: "clock",
            createdAt: now,
            expiresAt: nil,
            interruptPolicy: .normal,
            trustLevel: .bundled
        ),
        // 多个世界时钟参与轮换
        StatusCandidate(
            id: "clock.tokyo",
            sourceModule: manifest.id,
            semanticRole: .rotation,
            severity: .normal,
            priority: 0,
            text: tokyoTimeString,
            icon: "clock",
            createdAt: now,
            expiresAt: nil,
            interruptPolicy: .normal,
            trustLevel: .bundled
        )
    ]
}
```

### 内置模块的候选特征

| 模块 | semanticRole | interruptPolicy | trustLevel | 特殊行为 |
|------|-------------|----------------|------------|---------|
| Clock | `.primary` + `.rotation` | `.normal` | `.bundled` | 多个世界时钟参与轮换 |
| Counter | `.primary` | `.normal` | `.bundled` | — |
| DeepSeek | `.primary` | `.normal` | `.bundled` | priority=100 |
| NotesQuick | `.primary` | `.normal` | `.bundled` | — |
| SystemPulse | `.alert`（CPU/内存过高时） | `.preempt` | `.bundled` | 告警时立即抢占 |
| NetworkMock | `.alert`（网络断开时） | `.preempt` | `.bundled` | 告警时立即抢占 |

### 第三方模块的候选

`DeclarativeModule` 为第三方模块自动生成候选，`trustLevel` 为 `.unsignedLocal`（低于 `.bundled`），确保第三方模块不会饿死内置模块。

## 相关文档

- [架构总览](Architecture.md) — 五平面架构
- [投影与快照](ProjectionAndSnapshot.md) — StatusCandidate 嵌入 ProjectionSet
- [内置模块参考](BuiltInModules.md) — 各模块的候选行为
- [安全与权限](SecurityAndPermissions.md) — TrustLevel 详解
