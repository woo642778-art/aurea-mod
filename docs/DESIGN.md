# Aurea Studio integration design

User outcome: extend the supplied Aurea IPA with useful EffectCraft capabilities on iPhone and iPad while preserving Aurea and creating a testable unsigned IPA.

Evidence: Aurea contains a native ARM64 C++/SwiftUI engine and an Objective-C AureaEngine interface. Static findings are presence evidence, not proof that every feature works. Its source and runtime state are unavailable. EffectCraft has an official offline-capable WebAssembly release with public engine commands.

Decision: bundle the unmodified official EffectCraft 0.10.0 runtime as a separately attributed in-app workspace. Add a touch toolbar and native file/export bridge. Use the observed Objective-C interface only for selected-source reads and additive media imports. Do not overwrite projects, replace original effect registries, bypass licenses/payments, or describe this as native timeline/effect parity.

Architecture: a new ARM64 Objective-C extension loaded through a weak Mach-O load command; local-only HTTP delivery of bundled runtime; WKWebView with persistent storage; UIKit launcher and document/share controls; JS engine API for touch controls and project backup. Preserve original executable bytes outside its header and original resources.

Minimum iOS: 16.3. Device testing is not performed here. Native build, static package checks and actual Chromium/WASM checks are distinct evidence categories. Memory-heavy effects and device-specific WKWebView behavior require physical validation. No zero-bug assertion.

Security: bind only 127.0.0.1; token-protected paths; canonical path checks; reject malformed/oversized requests; only explicit registered media exposed. No public upload of original IPA. Bridge actions are whitelisted and restricted to the local main frame. No secrets or user media in source repository.

Delivery: unsigned experimental integrated IPA, reproducible source, evidence audit, provenance hashes, exact known limitations. A missing implementation or failing test must remain explicit.
