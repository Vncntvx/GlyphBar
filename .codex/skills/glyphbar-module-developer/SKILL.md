---
name: glyphbar-module-developer
description: Create new GlyphBar modules following the project's unified contract. Use when adding a new built-in module, scaffolding module files, writing module tests, or verifying a module follows the Command/Effect/Capability pipeline.
---

# GlyphBar Module Developer

## Overview

This skill scaffolds and implements new GlyphBar modules that follow the project's unified `ModuleContract` architecture. Every module — built-in or third-party — uses the same Command → handle → DomainTransition → Effect → Snapshot pipeline.

## When to Use

- Adding a new built-in module to `GlyphBar/Modules/`
- Scaffolding module files (manifest, model, panel, snapshot, provider, tests)
- Writing headless module tests using `ModuleHarness`
- Verifying a module follows the Command/Effect/Capability pipeline
- Adding Widget support to an existing module

## Module Structure

Every module follows this file structure. Create all files in `GlyphBar/Modules/<ModuleName>/`:

| File | Responsibility | Max Lines |
|------|---------------|-----------|
| `<Name>Module.swift` | Manifest, `handle()`, `buildProjection()`, `statusCandidates()`, protocol conformance | 300 |
| `<Name>Model.swift` | State struct, Codable models, bounds, formatters, pure domain helpers | 300 |
| `<Name>Panel.swift` | SwiftUI panel view — dispatches commands, never owns source-of-truth state | 300 |
| `<Name>Snapshot.swift` | (Optional) Snapshot/projection building for nontrivial modules | 200 |
| `<Name>Provider.swift` | (Optional) macOS platform adapters (Network, ProcessInfo, Mach, file import) | 300 |

## Implementation Checklist

Follow this exact order when creating a module:

### 1. Define the Manifest

```swift
static let staticManifest = ModuleManifest(
    id: "<moduleID>",              // stable, lowercase, no spaces
    displayName: "<Display Name>",
    subtitle: "<One-line description>",
    systemImage: "<sf.symbol>",    // valid SF Symbol
    version: "1.0.0",
    author: "Wenjie Xu",
    capabilities: [.statusItem, .panel, .actions, .widgets, .deepLinks],
    permissions: [],               // only what the module actually needs
    defaultRefreshPolicy: .manual,  // or .interval(seconds: N)
    actions: [
        ModuleAction(id: "refresh", title: "Refresh", systemImage: "arrow.clockwise", role: .refresh),
    ],
    widgets: [],                   // add ModuleWidgetDescriptor if Widget support needed
    priority: 0                    // 0=normal, 50=always-visible, 100=important
)
```

**Rules**:
- `id` is permanent — never change after release
- Only declare permissions the module actually uses (each grants a capability)
- `.appGroupStorage` grants `ModuleCacheNamespace` + `ModuleSettingsNamespace` + `ModuleSecretStore`
- `.openExternalURLs` grants `NetworkCapability`
- `.systemMetrics` grants `SystemMetricsCapability`
- `.pasteboard` grants `ClipboardCapability`
- `.localFiles` grants `FileImportCapability`

### 2. Define the State Model

Create a private state struct in `<Name>Model.swift`:

```swift
struct <Name>State: Codable {
    var someField: String
    var someFlag: Bool
}
```

State must be `Codable` for persistence via `ModuleSettingsNamespace` or `ModuleCacheNamespace`. Never put SwiftUI/AppKit types in state.

### 3. Implement handle()

This is the **only** business entry point. All mutations go through here:

```swift
func handle(
    command: Command,
    capabilities: GrantedCapabilities,
    bridge: ModuleBridge
) async -> DomainTransition {
    switch command {
    case .refresh:
        let envelope = ProjectionBuilder.buildEnvelope(from: buildSnapshot())
        return DomainTransition(
            effects: [.publishSnapshot(envelope)],
            health: .healthy,
            refreshProjection: true
        )

    case .userAction(let actionID, let payload):
        switch actionID {
        case "someAction":
            // Mutate state, then publish
            return DomainTransition(
                effects: [.publishSnapshot(envelope)],
                health: .healthy,
                refreshProjection: true
            )
        default:
            return .empty
        }

    default:
        return .empty
    }
}
```

**Rules**:
- Never call `UserDefaults.standard`, `URLSession.shared`, `NSPasteboard`, `NSWorkspace`, `WidgetCenter` directly
- Use `capabilities.network` for network requests
- Use `capabilities.secretStore?.secret(for:)` / `setSecret(_:for:)` for secrets
- Use `capabilities.cache?.saveDomainState(_:)` / `loadDomainState()` for domain cache
- Use `capabilities.settings?.set(_:forKey:)` / `get(_:forKey:)` for settings
- Return `.empty` for unhandled commands

### 4. Implement buildProjection() and statusCandidates()

```swift
func buildProjection() -> ProjectionSet {
    ProjectionBuilder.build(from: buildSnapshot())
}

func statusCandidates() -> [StatusCandidate] {
    let snap = buildSnapshot()
    return snap.signals.map { signal in
        StatusCandidate(
            id: signal.id,
            sourceModule: manifest.id,
            semanticRole: .primary,
            severity: signal.severity,
            priority: signal.priority,
            text: signal.title,
            icon: signal.systemImage,
            createdAt: snap.timestamp,
            expiresAt: nil,
            interruptPolicy: .normal,
            trustLevel: .bundled
        )
    }
}
```

For alert candidates (e.g., threshold exceeded), use `semanticRole: .alert` and `interruptPolicy: .preempt`.

### 5. Implement the Panel

```swift
func panelContent(context: PanelHostContext) -> some View {
    <Name>Panel(
        snapshot: buildSnapshot(),
        onAction: { actionID, payload in
            context.dispatch(.userAction(actionID: actionID, payload: payload))
        }
    )
}
```

**Rules**:
- Panel dispatches commands via `context.dispatch()`, never mutates module state directly
- SwiftUI `Binding` set closures must dispatch commands
- Use native SwiftUI components: `List`+`Section`, `Toggle(.checkbox)`, `.contextMenu`, `.searchable`
- Do not put business logic in views

### 6. Persist State

```swift
private func persistState() {
    let state = <Name>State(...)
    settings?.set(state, forKey: "moduleState")
}

private static func loadState(from settings: ModuleSettingsNamespace?) -> <Name>State? {
    settings?.get(<Name>State.self, forKey: "moduleState")
}
```

Use `ModuleSettingsNamespace` for structured state. Use `ModuleCacheNamespace` for opaque domain data.

### 7. Write Tests

Create tests in `Tests/ModuleTests/<Name>ModuleTests.swift`:

```swift
import Testing
@testable import GlyphBar

struct <Name>ModuleTests {
    @MainActor
    @Test func refreshPublishesSnapshot() async {
        let harness = ModuleHarness(module: <Name>Module())
        let transition = await harness.refresh(reason: .manual)

        #expect(transition.refreshProjection == true)
        #expect(harness.latestSnapshot?.id == "<moduleID>")
    }

    @MainActor
    @Test func userActionMutatesState() async {
        let harness = ModuleHarness(module: <Name>Module())
        let transition = await harness.dispatch(
            .userAction(actionID: "someAction", payload: nil)
        )

        #expect(transition.refreshProjection == true)
        #expect(harness.emittedEffects.contains(where: {
            if case .publishSnapshot = $0 { return true }
            return false
        }))
    }

    @MainActor
    @Test func gracefulDegradationWithoutCapabilities() async {
        let module = <Name>Module()  // no capabilities injected
        let harness = ModuleHarness(module: module)
        let transition = await harness.refresh(reason: .manual)

        // Module should not crash even with nil capabilities
        #expect(transition.effects.isEmpty == false)
    }
}
```

**Required test coverage**:
- refresh produces snapshot
- at least one userAction
- graceful degradation when capabilities are nil
- settings change through command (if module has settings)
- permission denied/granted (if module needs capabilities)
- widget snapshot output (if module declares widgets)

### 8. Register the Module

Add registration in `AppEnvironment`:

```swift
registry.register { [capabilityFactory, bridge] in
    let capabilities = capabilityFactory.makeCapabilities(
        for: <Name>Module.staticManifest,
        bridge: bridge
    )
    return <Name>Module(capabilities: capabilities)
}
```

### 9. Add to Xcode Project

```sh
python3 script/add_swift_file.py <new_disk_path> <sibling_disk_path>
plutil -lint GlyphBar.xcodeproj/project.pbxproj
```

## Forbidden Patterns

Never do these in a module:

| Forbidden | Instead |
|-----------|---------|
| View/Binding directly writes module state | Dispatch command via `context.dispatch()` |
| `UserDefaults.standard` | `ModuleSettingsNamespace` or `ModuleCacheNamespace` |
| `URLSession.shared` | `capabilities.network?.send(_:)` |
| `NSPasteboard.general` | `Effect.copyToClipboard` or `capabilities.clipboard` |
| `NSWorkspace.shared` | `Effect.openURL` |
| `WidgetCenter.shared` | `Effect.publishSnapshot` |
| Secret in UserDefaults | `capabilities.secretStore?.setSecret(_:for:)` |
| Module reads another module's state | Modules are isolated; communicate through kernel |

## Capability Quick Reference

| Capability | Granted by | Shared/Exclusive | Key API |
|-----------|-----------|-----------------|---------|
| `ModuleSecretStore` | `.appGroupStorage` | Exclusive | `setSecret(_:for:)`, `secret(for:)`, `deleteSecret(for:)` |
| `ModuleCacheNamespace` | `.appGroupStorage` or `.cachedState` | Exclusive | `saveDomainState(_:)`, `loadDomainState()`, `clearDomainState()` |
| `ModuleSettingsNamespace` | `.appGroupStorage` or `.settings` | Exclusive | `set(_:forKey:)`, `get(_:forKey:)`, `subscript(rawKey:)` |
| `NetworkCapability` | `.openExternalURLs` | Shared | `send(_:) async throws -> (Data, HTTPURLResponse)` |
| `FileImportCapability` | `.localFiles` | Exclusive | `requestImport(allowedTypes:) -> URL?` |
| `ClipboardCapability` | `.pasteboard` | Shared | `read()`, `write(_:)` |
| `SystemMetricsCapability` | `.systemMetrics` | Shared | `cpuUsage()`, `memoryUsage()`, `diskUsage()` |
| `LoggingCapability` | Always granted | Exclusive | `info(_:)`, `warn(_:)`, `error(_:)`, `debug(_:)` |
| `ModuleBridge` | Always granted | — | `submit(_:)` |

## ModuleHarness API

| Method/Property | Purpose |
|-----------------|---------|
| `dispatch(_ command:) -> DomainTransition` | Send command and await result |
| `refresh(reason:) -> DomainTransition` | Convenience for `.refresh` |
| `stop()` | Cancel in-flight work |
| `unload()` | Remove from supervisor |
| `resetCapturedOutput()` | Clear captured effects/transitions/snapshots |
| `emittedEffects: [Effect]` | All captured effects |
| `transitions: [DomainTransition]` | All captured transitions |
| `latestEnvelope: SnapshotEnvelope?` | Latest snapshot envelope |
| `latestSnapshot: ModuleSnapshot?` | Latest module snapshot |
| `latestWidgetSnapshot: WidgetModuleSnapshot?` | Latest widget snapshot |
| `isLoaded: Bool` | Whether module is loaded |

## Resources

### references/
- `../../docs/Architecture.md` — Full architecture overview
- `../../docs/NativeModuleDevelopment.md` — Native module development guide
- `../../docs/Capabilities.md` — Capability system reference
- `../../docs/CommandEffectPipeline.md` — Command/Effect pipeline reference
- `../../docs/TestingGuide.md` — Testing patterns and conventions
