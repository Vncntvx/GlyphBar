# GlyphBar Module Development

GlyphBar modules publish small, glanceable status snapshots for the menu bar, compact panel, full module window, and widgets. Built-in modules are compiled with the app. Third-party modules in v1 are declarative packages imported by the user; GlyphBar does not load arbitrary native code from imported modules.

## Package Structure

Create a directory with a `.glyphbarmodule` suffix:

```text
ExampleStatus.glyphbarmodule/
  glyphbar-module.json
  snapshot.json
  README.md
  assets/
```

`glyphbar-module.json` is required. `snapshot.json` is optional but recommended because it provides the module status data shown by GlyphBar.

## Lifecycle

1. The user imports the package from Settings > Modules > Import Module.
2. GlyphBar validates the manifest, compatibility, permissions, and package structure.
3. GlyphBar copies the package into its Application Support modules directory.
4. The module can be enabled, disabled, refreshed, shown in the compact panel, used by deep links, and removed.

## Local Testing

During development, import the package folder directly. After changing the manifest or snapshot, remove and re-import the module. Keep module IDs stable and unique.

## Packaging

Ship the `.glyphbarmodule` directory as a folder or archive that users can expand before importing. Do not include executables for v1; they are not loaded by GlyphBar.
