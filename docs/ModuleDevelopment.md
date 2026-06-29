# 声明式模块开发指南

GlyphBar 支持第三方模块通过**声明式 JSON 包**（Level 2 扩展）扩展功能。声明式模块是纯数据包，由 GlyphBar 的 `DeclarativeModule` 宿主解释渲染，**不执行任何原生代码**。

## 概述

声明式模块的特点：

- **纯数据**：只包含 JSON manifest 和 snapshot 数据，无 Swift/ObjC/脚本/可执行文件
- **宿主解释**：由 GlyphBar 内置的 `DeclarativeModule` 加载和渲染
- **安全隔离**：无代码执行，`trustLevel` 为 `.unsignedLocal`
- **功能受限**：无法直接访问系统 API，只能通过 manifest 声明的 action 触发预定义行为

## 包结构

创建一个以 `.glyphbarmodule` 为后缀的目录：

```text
MyModule.glyphbarmodule/
  glyphbar-module.json    ← 必需：模块 manifest
  snapshot.json           ← 可选但推荐：预缓存状态数据
  README.md               ← 可选：模块说明
  assets/                 ← 可选：资源文件（当前未使用）
```

### glyphbar-module.json

模块的完整声明文件，定义了模块的身份、功能、权限、动作和展示方式。详见 [Manifest 字段参考](ModuleManifest.md)。

### snapshot.json

模块的预缓存状态数据，提供导入后的初始展示。如果缺失，模块在首次 refresh 前显示为空。

## 开发流程

### 1. 创建目录结构

```sh
mkdir MyModule.glyphbarmodule
cd MyModule.glyphbarmodule
```

### 2. 编写 Manifest

创建 `glyphbar-module.json`：

```json
{
  "schemaVersion": 1,
  "id": "myModule",
  "displayName": "My Module",
  "subtitle": "A custom status module",
  "systemImage": "star",
  "version": "1.0.0",
  "author": "Your Name",
  "minimumGlyphBarVersion": "1.0",
  "capabilities": ["statusItem", "panel", "actions", "widgets", "deepLinks"],
  "permissions": ["pasteboard"],
  "refreshPolicy": { "type": "manual" },
  "actions": [
    {
      "id": "copyStatus",
      "title": "Copy Status",
      "systemImage": "doc.on.doc",
      "kind": "copy",
      "value": "Status: OK"
    }
  ],
  "widgets": [
    {
      "id": "myModule.widget",
      "title": "My Module",
      "subtitle": "Custom status",
      "systemImage": "star",
      "supportedFamilies": ["small", "medium"]
    }
  ],
  "panel": {
    "metricOrder": ["uptime", "health"],
    "noteTitle": "Details",
    "metadataKeys": ["version", "source"]
  }
}
```

> **重要**：`id` 一旦发布不应更改。它关联了所有已安装的用户数据和 Widget 缓存。

### 3. 编写 Snapshot 数据

创建 `snapshot.json`：

```json
{
  "title": "OK",
  "subtitle": "All systems normal",
  "metrics": {
    "uptime": 99.9,
    "health": 100
  },
  "notes": [
    "This module shows system health status."
  ],
  "metadata": {
    "version": "1.0.0",
    "source": "MyModule.glyphbarmodule"
  }
}
```

`metrics` 的键名应与 manifest 中 `panel.metricOrder` 的条目对应，这样面板会按指定顺序展示指标。

### 4. 本地导入测试

1. 打开 GlyphBar → Settings → Modules → Import Module
2. 选择 `MyModule.glyphbarmodule` 目录
3. 模块出现在模块列表中，启用后即可在菜单栏和面板中看到

### 5. 迭代修改

修改 manifest 或 snapshot 后，需要**移除并重新导入**模块：

1. Settings → Modules → 选择模块 → Remove
2. 重新 Import Module

> **提示**：保持 `id` 不变，这样重新导入后模块的设置和缓存数据可以保留。

### 6. 打包分发

将 `.glyphbarmodule` 目录打包为 ZIP 或其他归档格式分发。用户解压后通过 Import Module 导入。

**v1 限制**：
- 不要包含可执行文件（GlyphBar 不会加载）
- 不要包含动态库（.dylib/.framework）
- 不要包含脚本文件

## 导入生命周期

```
Import → Validate → Copy → Use
```

### Import

用户通过 Settings > Modules > Import Module 选择 `.glyphbarmodule` 目录。

### Validate

`ExternalModulePackageValidator` 执行以下验证：

1. **Manifest 存在**：`glyphbar-module.json` 文件必须存在
2. **Schema 版本匹配**：`schemaVersion` 必须为 `1`（当前唯一支持版本）
3. **ID 合法性**：`id` 仅包含安全字符（字母、数字、连字符、下划线）
4. **版本兼容性**：`minimumGlyphBarVersion` 不高于当前 GlyphBar 版本

验证失败时，导入被拒绝并显示错误信息。

### Copy

验证通过后，GlyphBar 将包复制到 Application Support 目录：

```
~/Library/Application Support/GlyphBar/Modules/<id>.glyphbarmodule/
```

### Use

模块被注册到 `ModuleRegistry`，`DeclarativeModule` 加载 manifest 和 snapshot 数据，模块可被启用、禁用、刷新、展示。

## DeclarativeModule 宿主行为

`DeclarativeModule` 是 GlyphBar 内置的声明式模块宿主，负责解释和渲染第三方 JSON 包。

### 数据渲染

`DeclarativeModule` 从 `snapshot.json` 读取数据并构建展示：

- **标题区**：`title` + `subtitle`
- **指标区**：按 `panel.metricOrder` 指定的顺序展示 `metrics` 中的键值对
- **备注区**：`notes` 数组，标题由 `panel.noteTitle` 控制
- **元数据区**：按 `panel.metadataKeys` 指定的键展示 `metadata` 中的值

### Action 处理

用户点击动作按钮时，`DeclarativeModule` 根据 `kind` 执行对应行为：

| Kind | 处理方式 |
|------|---------|
| `copy` | 返回 `Effect.copyToClipboard(value)` |
| `openURL` | 返回 `Effect.openURL(URL(string:value)!)` |
| `deepLink` | 返回 `Effect.openURL(URL(string:value)!)`（触发内部路由） |
| `refresh` | 返回 `Command.refresh(reason: .manual)` |

所有 action 都通过 Command/Effect 管线执行，`DeclarativeModule` 不直接调用 `NSPasteboard` 或 `NSWorkspace`。

### StatusCandidate

`DeclarativeModule` 自动为第三方模块生成 `StatusCandidate`：

- `semanticRole`：`.primary`
- `trustLevel`：`.unsignedLocal`（低于内置模块的 `.bundled`）
- `interruptPolicy`：`.normal`
- `priority`：使用 manifest 中声明的值

由于 `trustLevel` 较低，第三方模块的候选在仲裁时不会抢占内置模块的展示位置。

### 面板渲染

`DeclarativeModule` 使用 `AnyView` 声明式面板（`DeclarativeModulePanel`），渲染 metrics、notes 和 metadata 的通用卡片布局。与内置模块的泛型 `@ViewBuilder` 面板不同，声明式面板无法自定义 SwiftUI 视图结构。

### Refresh 行为

- `manual`：仅在用户手动触发时 refresh，重新读取 `snapshot.json`
- `onLaunch`：App 启动时自动 refresh
- `interval`：按指定间隔定时 refresh（重新读取 `snapshot.json`）

由于声明式模块的 snapshot 是静态 JSON 文件，refresh 实际上是重新从磁盘读取文件。如果外部工具（CLI、Shortcuts）通过 IngestionAPI 更新了 snapshot 数据，refresh 会读取到新数据。

## 最佳实践

### ID 命名

- 使用反向域名风格（如 `com.example.mymodule`）或简短唯一标识符
- 一旦发布不要更改
- 避免与内置模块 ID 冲突（`clock`、`counter`、`deepseek`、`notesquick`、`systempulse`、`networkmock`）

### Snapshot 数据设计

- `metrics` 使用有意义的键名，与 `metricOrder` 对应
- `notes` 提供有用的上下文信息
- `metadata` 包含版本号、数据来源等辅助信息
- 数值使用 `Double` 类型，即使是整数也写为 `42.0` 或 `42`（JSON 会自动处理）

### Action 设计

- 每个动作提供清晰的 `title` 和 `systemImage`
- `copy` 动作的 `value` 应包含有意义的内容
- `openURL` 动作的 `value` 必须是有效的 URL 字符串
- `deepLink` 动作的 `value` 使用 `glyphbar://` 前缀

### metricOrder 和 metadataKeys

- `metricOrder` 控制面板中指标的展示顺序
- 未在 `metricOrder` 中列出的指标不会在面板展示
- `metadataKeys` 同理，只展示列出的元数据项
- 建议将最重要的指标放在前面

## 完整示例

参考 `examples/ExampleStatus.glyphbarmodule/` 目录：

```text
ExampleStatus.glyphbarmodule/
  glyphbar-module.json    ← manifest 声明
  snapshot.json           ← 预缓存数据
  README.md               ← 模块说明
```

**manifest** 声明了一个展示 "Example Status" 的模块，具有：
- `statusItem` + `panel` + `actions` + `widgets` + `deepLinks` 五项能力
- `pasteboard` 权限（用于 copy 动作）
- 一个 `copy` 动作（复制状态文本）
- 一个 Widget 描述符（支持 small 和 medium 尺寸）
- 面板按 `["value", "health"]` 顺序展示指标

**snapshot** 提供了初始数据：
- 标题 "Ready"
- 两个指标：`value: 42`、`health: 100`
- 一条备注
- 一条元数据

## 局限性

| 限制 | 原因 | 替代方案 |
|------|------|---------|
| 无法执行原生代码 | 安全隔离 | 使用 IngestionAPI（P4）从外部推送数据 |
| 无法动态创建 WidgetKit 扩展 | WidgetKit 要求编译期注册 | 通过 `widgets` 描述符提供数据，等待通用模板 Widget |
| 无法直接访问系统 API | 能力安全模型 | 通过 `permissions` 声明权限，宿主代为执行 |
| snapshot 数据为静态 JSON | 无代码执行 | 使用 CLI/Shortcuts/CI 通过 IngestionAPI 更新 |
| 面板布局固定 | 通用渲染器 | 使用 `panel.metricOrder`/`metadataKeys` 控制展示 |

## 相关文档

- [Manifest 字段参考](ModuleManifest.md) — JSON 字段的完整参考
- [架构总览](Architecture.md) — 微内核架构和扩展层级
- [安全与权限](SecurityAndPermissions.md) — 信任等级和权限系统
- [Widget 集成](WidgetIntegration.md) — 第三方模块的 Widget 策略
- [Command/Effect 管线](CommandEffectPipeline.md) — Action 如何通过 Effect 执行
