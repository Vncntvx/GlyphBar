# Security And Permissions

GlyphBar v1 third-party modules are declarative packages. They are copied into the app-managed modules directory and interpreted by the host. GlyphBar does not load arbitrary Swift, Objective-C, dynamic libraries, shell scripts, or executables from imported packages.

## Trust

Imported packages are shown as `Unsigned Local Package`. Built-in modules are shown as `Bundled`.

Future versions can add signed package verification or XPC-backed native providers without changing the basic manifest/source model.

## Permissions

Manifests declare requested permissions such as `pasteboard`, `notifications`, `systemMetrics`, `appGroupStorage`, `openExternalURLs`, and `localFiles`. The host should expose these in Settings before enabling more powerful capabilities.

## Storage

GlyphBar copies imported modules into Application Support. Removing a third-party module deletes the package and can also clear cached module/widget data.
