# 深度链接

GlyphBar 使用 `glyphbar://` URL scheme 进行内部路由。所有路由均为**单一用途**——一个路由只做一件事，不产生未文档化的副作用。

## App 路由

| 路由 | 功能 |
|------|------|
| `glyphbar://app/panel` | 打开菜单栏面板 |
| `glyphbar://app/settings` | 打开设置窗口 |
| `glyphbar://app/modules` | 打开设置并定位到模块管理 |
| `glyphbar://app/import-module` | 打开模块导入流程 |
| `glyphbar://app/logs` | 打开诊断日志窗口 |

## 模块路由

| 路由 | 功能 |
|------|------|
| `glyphbar://module/{moduleID}` | 打开面板并选中指定模块 |
| `glyphbar://module/{moduleID}/settings` | 打开指定模块的管理页面 |
| `glyphbar://module/{moduleID}/widget` | 打开指定模块的面板 |
| `glyphbar://module/{moduleID}/action/{actionID}` | 执行指定模块的动作 |

### 动作路由

`glyphbar://module/{moduleID}/action/{actionID}` 路由通过 `DeepLinkRouter` 转换为 `Command.userAction`：

```
glyphbar://module/deepseek/action/copyUsage
    → Command.userAction(actionID: "copyUsage", payload: nil)
    → DeepSeekModule.handle(.userAction("copyUsage", nil))
    → DomainTransition(effects: [.copyToClipboard(usageText)])
```

模块不需要特殊处理——深度链接触发的动作与用户在面板中点击按钮触发的动作走相同的 Command 路径。

## Ingestion API 路由（P4）

P4 将通过 `IngestionAPI` 支持外部数据发布：

| 端点 | 功能 |
|------|------|
| `glyphbar://ingest/{moduleID}` | 为指定模块发布 snapshot 数据 |
| `glyphbar://ingest/{moduleID}/invalidate` | 使指定模块的缓存数据失效 |
| `glyphbar://ingest/{moduleID}/clear` | 清除指定模块的实例状态 |

Ingestion API 的 URL scheme 端点用于 CLI/Shortcuts/CI 等外部工具推送数据，详见 [安全与权限](SecurityAndPermissions.md)。

## 设计原则

- **单一用途**：每个路由只做一件事。`settings` 路由只打开设置，不会同时打开面板
- **无副作用**：路由不会修改模块状态或触发刷新，除非路由的文档化行为明确包含该动作
- **可组合**：多个路由可通过 Shortcuts 等工具组合使用

## 相关文档

- [架构总览](Architecture.md) — URL scheme 路由在架构中的位置
- [声明式模块开发](ModuleDevelopment.md) — 声明式模块的 deepLink action
- [Command/Effect 管线](CommandEffectPipeline.md) — 动作路由如何转换为 Command
