# Module Manifest

Every third-party package must include `glyphbar-module.json`.

```json
{
  "schemaVersion": 1,
  "id": "exampleStatus",
  "displayName": "Example Status",
  "subtitle": "A sample third-party module",
  "systemImage": "sparkles",
  "version": "1.0.0",
  "author": "Example Developer",
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
      "value": "Example status"
    }
  ],
  "widgets": [
    {
      "id": "exampleStatus.widget",
      "title": "Example Status",
      "subtitle": "Cached status",
      "systemImage": "sparkles",
      "supportedFamilies": ["small", "medium"]
    }
  ],
  "panel": {
    "metricOrder": ["value"],
    "noteTitle": "Notes",
    "metadataKeys": ["source"]
  }
}
```

## Snapshot

`snapshot.json` uses a constrained status shape:

```json
{
  "title": "42",
  "subtitle": "Ready",
  "metrics": { "value": 42 },
  "notes": ["Imported module snapshot"],
  "metadata": { "source": "local package" }
}
```

Supported action kinds are `copy`, `openURL`, `deepLink`, and `refresh`.
