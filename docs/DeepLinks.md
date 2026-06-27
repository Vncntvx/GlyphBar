# Deep Links

GlyphBar uses the `glyphbar://` URL scheme.

## App Routes

- `glyphbar://app/panel` opens the compact menu-bar panel.
- `glyphbar://app/settings` opens Settings.
- `glyphbar://app/modules` opens Settings directly to Modules.
- `glyphbar://app/import-module` opens the module import flow.
- `glyphbar://app/logs` opens the current diagnostics surface.

## Module Routes

- `glyphbar://module/{moduleID}` opens the compact panel with that module selected.
- `glyphbar://module/{moduleID}/settings` opens module management for that module.
- `glyphbar://module/{moduleID}/widget` opens the module panel.
- `glyphbar://module/{moduleID}/action/{actionID}` runs a module action.

Routes are intentionally single-purpose. A settings route must not also open the panel unless a future route explicitly documents that behavior.
