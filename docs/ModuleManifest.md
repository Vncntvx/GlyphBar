# Manifest 字段参考

每个第三方模块包必须包含 `glyphbar-module.json` manifest 文件。本文档是该 JSON 格式的完整字段参考。内置模块使用相同的 `ModuleManifest` Swift 类型，但不通过 JSON 加载。

## glyphbar-module.json

### 顶层字段

| 字段 | 类型 | 必需 | 默认值 | 说明 |
|------|------|------|--------|------|
| `schemaVersion` | `Int` | ✅ | — | Manifest schema 版本号，当前为 `1` |
| `id` | `String` | ✅ | — | 模块唯一标识符，仅允许字母、数字、连字符、下划线 |
| `displayName` | `String` | ✅ | — | 模块显示名称 |
| `subtitle` | `String` | ❌ | `""` | 模块副标题 |
| `systemImage` | `String` | ✅ | — | SF Symbol 图标名称 |
| `version` | `String` | ✅ | — | 语义化版本号（如 `"1.0.0"`） |
| `author` | `String` | ❌ | `""` | 模块作者 |
| `minimumGlyphBarVersion` | `String` | ✅ | — | 最低兼容 GlyphBar 版本 |
| `maximumGlyphBarVersion` | `String` | ❌ | — | 最高兼容 GlyphBar 版本（不含） |
| `capabilities` | `[String]` | ✅ | — | 模块使用的功能列表 |
| `permissions` | `[String]` | ✅ | `[]` | 模块请求的权限列表 |
| `refreshPolicy` | `Object` | ✅ | — | 刷新策略 |
| `actions` | `[Object]` | ❌ | `[]` | 用户可执行的动作列表 |
| `widgets` | `[Object]` | ❌ | `[]` | Widget 描述符列表 |
| `panel` | `Object` | ❌ | — | 面板布局描述 |
| `priority` | `Int` | ❌ | `0` | 展示优先级 (0–1000) |

### capabilities — 功能声明

模块声明它使用了哪些功能。功能决定 GlyphBar 为模块启用哪些展示通道和基础设施。

| 值 | 含义 |
|---|------|
| `statusItem` | 在菜单栏展示状态 |
| `panel` | 在面板中展示内容 |
| `actions` | 提供用户可执行的动作 |
| `widgets` | 提供 Widget 数据 |
| `settings` | 需要模块设置命名空间 |
| `cachedState` | 需要缓存状态命名空间 |
| `permissions` | 需要权限管理 |
| `deepLinks` | 支持深度链接 |
| `storage` | 需要设置 + 缓存命名空间 |

**能力与权限的关系**：

- `capabilities` 声明模块**使用**的功能通道（如 statusItem、panel）
- `permissions` 声明模块**需要**的平台访问权限（如网络、剪贴板）
- `settings`/`cachedState`/`storage` 能力会触发 `CapabilityFactory` 补充授予对应的命名空间

### permissions — 权限声明

模块声明它需要哪些平台访问权限。权限必须经用户确认后才被授予（对第三方模块）。

| 值 | 含义 | 授予的能力 |
|---|------|-----------|
| `pasteboard` | 读写剪贴板 | `ClipboardCapability`（共享） |
| `notifications` | 发送通知 | （暂未实现） |
| `systemMetrics` | 读取系统指标 | `SystemMetricsCapability`（共享） |
| `appGroupStorage` | 访问 App Group 存储 | `ModuleCacheNamespace` + `ModuleSettingsNamespace` + `ModuleSecretStore`（独占） |
| `openExternalURLs` | 打开外部 URL / 发起网络请求 | `NetworkCapability`（共享） |
| `localFiles` | 访问本地文件 | `FileImportCapability`（独占） |

详见 [能力安全体系](Capabilities.md)。

### refreshPolicy — 刷新策略

```json
{ "type": "manual" }
{ "type": "onLaunch" }
{ "type": "interval", "seconds": 300 }
```

| 类型 | 含义 |
|------|------|
| `manual` | 仅在用户手动触发或 App 启动时刷新 |
| `onLaunch` | App 启动时自动刷新 |
| `interval` | 按指定间隔定时刷新，`seconds` 为间隔秒数（最小 5） |

> **注意**：实际刷新间隔可能被 `RefreshScheduler` 根据环境条件调整（面板关闭时 3x、低电量 2x、断网暂停、非活跃 2x）。

### actions — 用户动作

```json
{
  "id": "copyStatus",
  "title": "Copy Status",
  "systemImage": "doc.on.doc",
  "role": "standard"
}
```

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `id` | `String` | ✅ | 动作唯一标识符，在同一模块内不可重复 |
| `title` | `String` | ✅ | 动作显示标题 |
| `systemImage` | `String` | ❌ | SF Symbol 图标名 |
| `role` | `String` | ✅ | 动作角色类型 |

#### Action Roles

| Role | 含义 | 执行方式 |
|------|------|---------|
| `standard` | 标准动作 | 通过 `Command.userAction` 分发给模块处理 |
| `destructive` | 破坏性动作（如删除、重置） | 同上，UI 会额外提示确认 |
| `refresh` | 刷新动作 | 映射为 `Command.refresh(reason: .manual)` |

> **注意**：内置模块的 `ModuleAction` 使用 `role` 枚举（`standard`/`destructive`/`refresh`），不是旧的 `kind` + `value` 模式。声明式模块的 JSON manifest 中，action 处理仍通过预定义的 `kind`（copy/openURL/deepLink/refresh）执行，因为声明式模块没有原生 handle() 方法。

### widgets — Widget 描述符

```json
{
  "id": "exampleStatus.widget",
  "title": "Example Status",
  "subtitle": "Cached status",
  "systemImage": "sparkles",
  "supportedFamilies": ["small", "medium"]
}
```

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `id` | `String` | ✅ | Widget 唯一标识符 |
| `title` | `String` | ✅ | Widget 标题 |
| `subtitle` | `String` | ❌ | Widget 副标题 |
| `systemImage` | `String` | ❌ | SF Symbol 图标名 |
| `supportedFamilies` | `[String]` | ✅ | 支持的 Widget 尺寸家族 |

> **限制**：第三方模块无法动态添加 WidgetKit 扩展。Widget 描述符用于声明模块愿意提供 Widget 数据，实际渲染依赖 GlyphBar 的内置 Widget 或未来的通用模板。详见 [Widget 集成](WidgetIntegration.md)。

### panel — 面板布局描述

```json
{
  "metricOrder": ["value", "health"],
  "noteTitle": "Notes",
  "metadataKeys": ["source"]
}
```

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `metricOrder` | `[String]` | ❌ | 指标展示顺序，按此数组排列 snapshot 中的 metrics |
| `noteTitle` | `String` | ❌ | 备注区标题（默认 "Notes"） |
| `metadataKeys` | `[String]` | ❌ | 要展示的元数据键名列表 |

面板布局由 `DeclarativeModule` 的通用渲染器解释。`metricOrder` 控制指标的展示顺序，未列出的指标不展示。`metadataKeys` 指定要展示的元数据项。

### priority — 展示优先级

`priority` 取值范围 0–1000，影响 `PresentationArbiter` 的排序。相同严重度和语义角色下，高优先级候选优先展示。

| 优先级 | 典型用途 |
|--------|---------|
| 0 | 普通信息模块（默认值） |
| 50 | 常驻展示模块（如 Clock） |
| 100 | 重要模块（如 DeepSeek） |
| 500–1000 | 关键告警（保留给高严重度场景） |

## snapshot.json

`snapshot.json` 是可选的预缓存数据文件，提供模块的初始状态展示：

```json
{
  "title": "42",
  "subtitle": "Ready",
  "metrics": {
    "value": 42,
    "health": 100
  },
  "notes": [
    "Imported module snapshot"
  ],
  "metadata": {
    "source": "local package"
  }
}
```

### 字段参考

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `title` | `String` | ✅ | 状态标题文本 |
| `subtitle` | `String` | ❌ | 状态副标题 |
| `metrics` | `[String: Double]` | ❌ | 指标键值对，键名应与 manifest `panel.metricOrder` 对应 |
| `notes` | `[String]` | ❌ | 备注条目列表 |
| `metadata` | `[String: String]` | ❌ | 元数据键值对，键名应与 manifest `panel.metadataKeys` 对应 |

### 数据类型约束

- `metrics` 值必须为 `Double`（整数会自动转换）
- `notes` 元素为纯文本字符串
- `metadata` 值为纯文本字符串
- 所有文本建议使用 UTF-8 编码

## ID 命名约束

模块 `id` 必须满足：

- 仅包含 ASCII 字母（a-z, A-Z）、数字（0-9）、连字符（-）、下划线（_）
- 长度 1–128 字符
- 在所有已安装模块中唯一
- **稳定**：一旦发布不应更改，否则已安装的用户数据将无法关联

动作 `id` 必须满足：

- 同一模块内唯一
- 稳定，不应随版本更改

## 版本兼容规则

- `minimumGlyphBarVersion`：低于此版本的 GlyphBar 拒绝加载该模块
- `maximumGlyphBarVersion`：高于或等于此版本的 GlyphBar 拒绝加载该模块（可选）
- `schemaVersion`：当前为 `1`，不匹配时 `ExternalModulePackageValidator` 拒绝加载

## 完整示例

```json
{
  "schemaVersion": 1,
  "id": "exampleStatus",
  "displayName": "Example Status",
  "subtitle": "A sample third-party module",
  "systemImage": "sparkles",
  "version": "1.0.0",
  "author": "Example Developer",
  "minimumGlyphBarVersion": "1.0",
  "capabilities": ["statusItem", "panel", "actions", "widgets", "deepLinks"],
  "permissions": ["pasteboard"],
  "refreshPolicy": { "type": "manual" },
  "actions": [
    {
      "id": "copyStatus",
      "title": "Copy Status",
      "systemImage": "doc.on.doc",
      "role": "standard"
    },
    {
      "id": "refreshData",
      "title": "Refresh",
      "systemImage": "arrow.clockwise",
      "role": "refresh"
    }
  ],
  "widgets": [
    {
      "id": "exampleStatus.widget",
      "title": "Example Status",
      "subtitle": "Cached sample status",
      "systemImage": "sparkles",
      "supportedFamilies": ["small", "medium"]
    }
  ],
  "panel": {
    "metricOrder": ["value", "health"],
    "noteTitle": "Notes",
    "metadataKeys": ["source"]
  },
  "priority": 0
}
```

## 相关文档

- [声明式模块开发](ModuleDevelopment.md) — 如何编写 manifest 和 snapshot
- [能力安全体系](Capabilities.md) — permissions 和 capabilities 如何映射到能力
- [Widget 集成](WidgetIntegration.md) — widgets 字段如何影响 Widget 展示
- [安全与权限](SecurityAndPermissions.md) — 权限验证和安全模型
