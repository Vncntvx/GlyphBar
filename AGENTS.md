# AGENTS.md

## Project Structure & Ownership

GlyphBar is a SwiftUI-first macOS menu bar app with narrow AppKit bridges. Main app code lives in `GlyphBar/`:

- `App/`: app lifecycle, status bar, panel, settings, menu, windows, and routing.
- `Core/`, `Kernel/`, `Execution/`, `Projection/`, `Platform/`, `ControlPlane/`: module contracts, runtime, command/effect execution, scheduling, projection, ingestion, storage, security, logging, and platform abstractions.
- `Modules/`: bundled modules. Built-in modules must follow the same public module contract as third-party modules.
- `DesignSystem/`: reusable SwiftUI components used only when native SwiftUI/AppKit controls do not cover the case.
- `WidgetShared/`: shared widget cache models and bridges.
- `GlyphBarWidgets/`: WidgetKit extension and App Intents.
- `Tests/`: Swift Testing suites. Use `Tests/CoreTests/`, `Tests/KernelTests/`, `Tests/ExecutionTests/`, `Tests/ContractTests/`, `Tests/ModuleTests/`, and related folders by responsibility.

Do not commit `DerivedData/` or `build/`.

## Build, Test, And Project File Commands

Use the project script for local work:

```sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --build
./script/build_and_run.sh --test
./script/build_and_run.sh --telemetry
```

The script detects full Xcode and uses project-local `DerivedData`. For direct checks:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -list -project GlyphBar.xcodeproj
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project GlyphBar.xcodeproj -scheme GlyphBar -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

The Xcode project uses explicit file references. After adding a Swift file, register it with:

```sh
python3 script/add_swift_file.py <new_disk_path> <sibling_disk_path>
plutil -lint GlyphBar.xcodeproj/project.pbxproj
```

Use simple Swift filenames without shell-special characters such as `+`. Keep paths stable and avoid metadata churn.

## Module Architecture Rules

GlyphBar uses one module data flow:

`User/System/Input -> Command -> Module.handle(command, capabilities, bridge) -> DomainTransition/Effect -> Runtime/EffectExecutor -> Snapshot/Projection -> UI/Widget/Tests`

Follow these rules for all module work:

- UI never owns module business state. SwiftUI bindings may update local view affordances, but module state changes must dispatch `Command`.
- Modules return `DomainTransition`, `Effect`, `ProjectionSet`, `SnapshotEnvelope`, and status candidates. They do not mutate status bar UI, WidgetKit timelines, settings screens, or runtime caches directly.
- Keep module business logic headless. A module must run without AppKit windows, SwiftUI views, `NSStatusItem`, quick panel, settings UI, or widget extension process.
- Inject capabilities through `GrantedCapabilities`, `CapabilityFactory`, `ModuleSecretStore`, storage namespaces, clocks, network, logging, and bridges. Do not reach into `AppEnvironment` or global singletons from module logic.
- Use `CommandPayloadDecoding` and typed payload helpers for command payloads. Avoid ad hoc string parsing when a structured model is practical.
- Built-in and third-party modules use the same development model. Trust level, manifest declarations, permission grants, and user consent express the difference.
- Do not add legacy compatibility paths. This is a new project; remove or replace duplicate old routes instead of keeping parallel code.

## Module Template Expectations

A new module should make the AI/developer path obvious in code:

- `ModuleNameModule.swift`: manifest, command routing, high-level status candidates, and protocol conformance.
- `ModuleNameModel.swift`: state, codable models, bounds, formatters, and pure domain helpers.
- `ModuleNamePanel.swift`: SwiftUI panel only. The panel dispatches commands; it does not own source-of-truth state.
- `ModuleNameSnapshot.swift` or equivalent: projection and widget snapshot building when the module has nontrivial output.
- `ModuleNameProvider.swift`: macOS platform adapters such as Network framework, ProcessInfo, Mach APIs, file import, or URLSession wrappers.
- Focused tests under `Tests/ModuleTests/` and contract coverage under `Tests/ContractTests/` when behavior affects the module contract.

Keep files under 300 lines unless a generated file or compact data table gives a clear reason. Split by responsibility: model, panel, provider, parser, snapshot, runtime extension, and tests.

## Runtime And State Flow

Runtime code coordinates modules; it must not become a shortcut around the contract.

- Register and load modules through `ModuleRegistry`, `ModuleRuntime`, package stores, and the reconciler path.
- Enable/disable, refresh, unload, and scheduled local work must go through runtime command paths that tests can exercise.
- Snapshot caches, widget cache writes, status candidates, and live module projections must derive from module output. Do not keep a second UI-owned state model for the same facts.
- Do not use `UserDefaults` as an event bus. Use typed stores, ingestion APIs, commands, effects, and publishers already in the architecture.
- Scheduled work must be cancellable. Disabling or unloading a module must stop delayed commands from running.

## Security, Secrets, And Capabilities

Use honest names and enforced permissions.

- Store secrets through `ModuleSecretStore` and the project security abstractions. Do not store secrets in `UserDefaults.standard`.
- Do not call plaintext storage “secure.” If a store is plaintext, name it plaintext and restrict its use to non-secret data.
- Capabilities declared in a manifest must be enforced at capability creation or use time. UI display alone is not permission enforcement.
- Third-party modules receive capabilities only through granted permissions. Built-in modules may have default grants, but they still use the same capability surface.
- Cover permission denied, permission granted, secret write/read/delete, and secret isolation paths with tests.
- Keep app and widget App Group identifiers consistent: `group.com.wenjiexu.GlyphBar`. Do not remove entitlements to make unsigned CLI builds pass; use command-line signing overrides only for local verification.

## Widget And Intent Rules

Widget and intent code must stay connected to the module architecture.

- App Intents `perform()` methods must perform real work: route, dispatch a command, open the app, or return a useful result. Do not leave empty implementations.
- Widget data comes from module snapshots through `WidgetDataBridge` and shared widget models.
- Widget views should render metrics and notes together when both exist. Avoid mutually exclusive branches that hide valid sections.
- Modules expose widget support through manifest/widget descriptors and projection output.
- Add tests for widget envelope conversion, widget content sections, bridge publish/remove, and intent-visible behavior when practical.

## UI Design Principles

Prefer macOS native SwiftUI components over custom-drawn UI. Use `List` + `Section` instead of `ScrollView` + custom cards; `Toggle(.checkbox)` instead of hand-drawn checkmarks; `.contextMenu` instead of inline icon button groups; `.searchable` instead of custom search bars; system semantic colors such as `.primary`, `.secondary`, and `.accentColor` instead of hardcoded tints.

Use native frameworks before custom infrastructure: SwiftUI, AppKit bridges, Observation, Swift Concurrency, WidgetKit, App Intents, Network, Security/Keychain, UserNotifications, OSLog, Foundation, and Combine where the existing project uses it.

Only use `DesignSystem/` components when no native equivalent fits the specific use case. Do not put module business rules inside SwiftUI views.

## Coding Style

Use standard Swift formatting with 4-space indentation. Prefer `final` for concrete reference types and `@MainActor` for UI-facing coordinators.

Keep access control tight until a cross-file split needs internal access. Do not make properties public to work around design boundaries.

Use descriptive type names such as `ClockModule`, `StatusItemController`, `WidgetDataBridge`, `SystemPulseSnapshotProvider`, and `UsageExportFileParser`.

## Testing Requirements

Tests use Swift Testing:

```swift
import Testing
@Test
#expect(...)
#require(...)
```

Run tests before and after architectural changes. If baseline tests fail before a change, record that separately from failures introduced by the change.

Required coverage for module/runtime work:

- headless command dispatch through `ModuleHarness` or `ModuleRuntime`
- refresh, lifecycle start/stop/unload, and scheduled cancellation
- emitted effects and latest snapshot/projection assertions
- settings changes through commands, not direct view mutation
- status candidates and arbiter input/output
- widget snapshot publish and bridge behavior
- permission denied and granted paths
- secret read/write/delete/isolation paths

Keep tests focused. Split large test files by contract area once they approach 300 lines.
