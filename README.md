# GlyphBar

GlyphBar is a native macOS SwiftUI-first menu bar modular information hub.

The app shell owns menu bar rendering, quick panel presentation, native menus, routing, runtime scheduling, and widget snapshot publishing. Bundled modules demonstrate clock, system metrics, notes, counter state, and async failure/stale-cache behavior.

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
./script/build_and_run.sh --test   # run XCTest
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
