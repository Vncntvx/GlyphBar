# GlyphBar

GlyphBar is a native macOS SwiftUI-first menu bar modular information hub built on a **microkernel + unidirectional data flow + actor supervision + capability security** architecture.

The app shell owns menu bar rendering, quick panel presentation, native menus, routing, runtime scheduling, and widget snapshot publishing. Bundled modules demonstrate clock, system metrics, notes, counter state, and async failure/stale-cache behavior. Third-party modules are supported through declarative JSON packages and (future) XPC-isolated native modules.

Developer: Wenjie Xu, <wenjie.xu.cn@outlook.com>

## Build And Run

Use the project-local run script for daily development:

```sh
./script/build_and_run.sh --verify
```

The script detects full Xcode without requiring a global `xcode-select` change. It prefers an existing valid `DEVELOPER_DIR`, then the active full Xcode path, then `/Applications/Xcode-beta.app`, `/Applications/Xcode.app`, and other `/Applications/Xcode*.app` installs. It also cleans stale local LaunchServices registrations from `build/Debug` and `build/Release` before registering the project-local app bundle in `DerivedData`.

Useful modes:

```sh
./script/build_and_run.sh          # build and launch
./script/build_and_run.sh --build  # build only
./script/build_and_run.sh --test   # run Swift Testing tests
./script/build_and_run.sh --verify # build, launch, and verify the process
./script/build_and_run.sh --logs   # launch and stream process logs
./script/build_and_run.sh --telemetry
```

For direct Xcode command-line verification:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -list -project GlyphBar.xcodeproj
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project GlyphBar.xcodeproj -scheme GlyphBar -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project GlyphBar.xcodeproj -scheme GlyphBarWidgets -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

To run manually in Xcode, open `GlyphBar.xcodeproj`, select the `GlyphBar` scheme, choose `My Mac`, and run. For signed widget/App Group development, select an Apple Developer Team for both `GlyphBar` and `GlyphBarWidgets`.

The default bundle IDs are `com.wenjiexu.GlyphBar` and `com.wenjiexu.GlyphBar.widgets`. App Group support uses `group.com.wenjiexu.GlyphBar`; local unsigned builds fall back to standard `UserDefaults` for widget cache APIs.

## Architecture

GlyphBar follows a five-plane microkernel architecture:

| Plane | Responsibility |
|-------|---------------|
| **Presentation** | Menu bar rendering, panel display, status arbitration |
| **Projection** | Data projection, snapshot envelopes, widget bridge |
| **Kernel** | Module contracts, Command/Effect pipeline, capabilities, lifecycle |
| **Execution** | Refresh scheduling, environment awareness, presentation ticks |
| **Control Plane** | Desired/Observed state reconciliation, installation, upgrades |

All module behavior follows a **unidirectional data flow**:

```
Command → ModuleContract.handle() → DomainTransition → EffectExecutor → Side effects
```

Modules never directly access platform APIs (`NSPasteboard`, `URLSession`, `NSWorkspace`, `UserDefaults.standard`). All side effects are expressed as `Effect` values and executed by the single `EffectExecutor`.

Three extension levels are supported:

| Level | Type | Trust | Isolation |
|-------|------|-------|-----------|
| Level 1 | Built-in compiled modules | `.bundled` | Compile-time contract |
| Level 2 | Declarative JSON packages | `.unsignedLocal` | Data isolation |
| Level 3 | XPC-isolated native modules | `.signed` | Process isolation + capability proxy |

See [Architecture Overview](docs/Architecture.md) for the full architecture documentation.

## Documentation

### Architecture & Core Mechanisms

- [Architecture Overview](docs/Architecture.md) — Five-plane microkernel architecture, design principles, directory structure
- [Command/Effect Pipeline](docs/CommandEffectPipeline.md) — Unidirectional data flow, Command and Effect reference
- [Capabilities](docs/Capabilities.md) — GrantedCapabilities, CapabilityFactory, namespace isolation
- [Projection & Snapshot](docs/ProjectionAndSnapshot.md) — ProjectionSet, SnapshotEnvelope, ModuleHealth
- [Presentation Arbiter](docs/PresentationArbiter.md) — Status candidates, arbitration algorithm, hysteresis

### Module Development

- [Built-in Modules Reference](docs/BuiltInModules.md) — Clock, Counter, DeepSeek, NotesQuick, SystemPulse, NetworkMock
- [Declarative Module Development](docs/ModuleDevelopment.md) — Third-party JSON package guide (Level 2)
- [Native Module Development](docs/NativeModuleDevelopment.md) — Built-in and XPC module guide (Level 1 & 3)
- [Module Manifest Reference](docs/ModuleManifest.md) — `glyphbar-module.json` and `snapshot.json` field reference

### Integration & Security

- [Widget Integration](docs/WidgetIntegration.md) — Widget data flow, shared types, third-party widget strategy
- [Deep Links](docs/DeepLinks.md) — `glyphbar://` URL scheme routing
- [Security & Permissions](docs/SecurityAndPermissions.md) — Trust levels, permission system, storage security, XPC isolation
- [Testing Guide](docs/TestingGuide.md) — Swift Testing patterns, contract tests, test infrastructure

### Example

- `examples/ExampleStatus.glyphbarmodule/` — A working third-party module example
