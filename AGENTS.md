# Repository Guidelines

## Project Structure & Module Organization

GlyphBar is a SwiftUI-first macOS menu bar app with narrow AppKit bridges. Main app code lives in `GlyphBar/`: `App/` contains app coordination, status bar, panel, settings, menu, windows, and routing; `Kernel/` contains module contracts, command/effect pipeline, capabilities, and effect execution; `Projection/` contains snapshot envelopes, projection sets, and the widget bridge; `Presentation/` contains the status-bar arbiter, panel host+contribution, and status-item renderer; `Core/` contains legacy runtime, registry, storage, security, and logging (being gradually migrated to Kernel/Projection/Presentation); `DesignSystem/` contains reusable SwiftUI components; `Modules/` contains bundled modules. Shared widget cache models live in `GlyphBar/WidgetShared/`. Widget extension code lives in `GlyphBarWidgets/`. Tests are split between `Tests/CoreTests/`, `Tests/KernelTests/`, and `Tests/ModuleTests/`. Do not commit `DerivedData/` or `build/`.

## Build, Test, and Development Commands

Use the project script for local work:

```sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --build
./script/build_and_run.sh --test
./script/build_and_run.sh --telemetry
```

The script detects full Xcode automatically and uses project-local `DerivedData`. For direct checks, use:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -list -project GlyphBar.xcodeproj
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project GlyphBar.xcodeproj -scheme GlyphBar -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

## Coding Style & Naming Conventions

Use standard Swift formatting with 4-space indentation. Prefer `final` for concrete reference types, `@MainActor` for UI-facing coordinators, and dependency injection through `GrantedCapabilities`. Keep modules isolated behind `ModuleContract`; modules must return `DomainTransition` (effects + health) rather than directly changing status bar UI or calling platform APIs. Use descriptive type names such as `ClockModule`, `StatusItemController`, and `WidgetDataBridge`.

## Architecture (Microkernel Platform)

- **ModuleContract** replaces `StatusModule`. Modules implement `handle(command:capabilities:bridge:)` returning `DomainTransition`.
- **Command/Effect** unidirectional data flow: all module inputs are `Command`, all side-effects are `Effect` submitted via `ModuleBridge`.
- **GrantedCapabilities** replaces god-`ModuleContext`. Capabilities are granted per-module based on manifest permissions via `CapabilityFactory`.
- **PresentationArbiter** replaces `StatusComposer`+`StatusRotationEngine`. Modules submit `StatusCandidate`s; the arbiter picks the winner with hysteresis, TTL, and rotation support.
- **SnapshotEnvelope + ProjectionSet** replace flat `ModuleSnapshot` for typed projections.
- **TypedModuleContribution** provides `@ViewBuilder` panel content for built-in modules; third-party/XPC modules use `AnyView`.
- **EffectExecutor** is the single global side-effect exit point (clipboard, URLs, settings, etc.).

## Testing Guidelines

Tests use Swift Testing (`import Testing`, `@Test`, `#expect`/`#require`). Add focused tests under `Tests/CoreTests/` for routing, scheduling, status composition, storage, and widget bridges. Add kernel/contract tests under `Tests/KernelTests/`. Add module behavior tests under `Tests/ModuleTests/`. Name test functions descriptively (no `test` prefix required by Swift Testing) and run `./script/build_and_run.sh --test` before opening a PR.

## Commit & Pull Request Guidelines

This repository has no commit history yet, so use concise imperative commit messages, for example `Fix widget snapshot fallback`. PRs should include a short summary, verification commands, screenshots or screen recordings for visible UI changes, and notes about signing/App Group impact.

## Security & Configuration Tips

Keep app and widget App Group identifiers consistent: `group.com.wenjiexu.GlyphBar`. Do not remove entitlements to make unsigned CLI builds pass; use command-line signing overrides only for local verification.
