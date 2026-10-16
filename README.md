# Aurea Studio integration

An **experimental offline EffectCraft workspace inside Aurea**, with an additive media bridge. This is not full native effect/timeline parity. The original Aurea application and the pinned EffectCraft WASM binary are not contained in this source bundle.

## Build and verify

`bash tools/build_native.sh` on macOS with Xcode builds the arm64 iOS dylib and runs native Foundation bridge-contract and loopback HTTP tests. The engine bridge test uses a mock; it is not a test of the proprietary Aurea engine.

`node --test tests/core.test.mjs` and `python3 -m unittest discover -s tests -p test_http.py` run portable validation tests. `python3 tests/test_web.py DIST EVIDENCE` runs actual WASM tests against DIST, which must contain the verified official EffectCraft 0.10.0 web runtime overlaid with `web/`.

## Runtime provenance

Official EffectCraft web release: v0.10.0, release commit 05955c08b4fd025f1a09882df72e6dbff1a8148a.
Official ZIP SHA256: b922abeda2420391a7fd887f53ebae6948730e63720bad6a6eb3dc48dc1b46a8.
The upstream source audit additionally used main commit 7c733f4cc9043f011a5f87ef6a83d18c8fb6aa3b; this newer source is not silently substituted for the verified runtime.

## Data boundaries

The injected library observes only verified AureaEngine Objective-C signatures. It does not replace C++ engine code, bypass licensing, alter authentication, or overwrite existing layers. Original media can be copied into Studio. Supported rendered files can be imported as new Aurea layers. Project formats and editable effects are not interchangeable.

Files are served only on 127.0.0.1 with an unguessable per-process path, explicit file registration, same-origin checks, finite transfer sizes and range validation. Projects persist in WebKit storage; exports and manual `.ecproj` backups are stored in Documents/AureaStudio/Exports. A `.ecproj` does not embed source media; use a portable project or retain original files. Portable bundles are capped at 96 MiB; individual transfers at 256 MiB.

Device-specific WebKit, codecs, memory, Metal and the original SwiftUI synchronization still require physical-device testing. No claim of zero bugs, native feature parity, or full Adobe-compatible rendering is made.

This integration is unofficial. EffectCraft belongs to its contributors. Retain upstream LICENSE-MIT, LICENSE-APACHE, NOTICE and ATTRIBUTION.md when bundling the runtime. Newly authored integration code is MIT-licensed.
