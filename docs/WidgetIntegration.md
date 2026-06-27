# Widget Integration

GlyphBar widgets read cached snapshots through the shared app group. Built-in widgets are statically declared in the WidgetKit extension.

WidgetKit cannot load new third-party widget extensions from packages imported at runtime. Third-party modules should publish snapshot data that GlyphBar can render with generic/template widget layouts.

## Supported Model

- Module refresh creates a `ModuleSnapshot`.
- GlyphBar writes a widget snapshot through `WidgetDataBridge`.
- Generic widgets can render title, subtitle, severity, metrics, and notes.
- Widget taps deep-link back to `glyphbar://module/{moduleID}`.

## Limitation

Third-party packages cannot add new WidgetKit extension code dynamically. Native third-party widgets would require a separately installed app/extension or a future signed integration model.
