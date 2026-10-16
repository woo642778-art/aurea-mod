# Aurea Studio implementation plan

Goal: package a usable offline EffectCraft workspace inside the original Aurea IPA.
Architecture: DESIGN.md. Objective-C/WebKit native host, unchanged upstream WASM, touch-oriented JS controls, project backup, Python binary/package verification.

1. Verify upstream in a real browser; record command schemas, render and save behavior. Characterize APIs before implementing controls.
2. Write tests for path/range handling, web helper validation, and binary load-command insertion. Implement only after observing expected failures.
3. Implement native loopback host, weakly observed engine bridge, launcher, WebKit downloads/document import, safe teardown and failure messages. Compile with Apple SDK in the authorized repository.
4. Implement touch toolbar using actual EffectCraft commands; project save/restore, file transfer and rendered-frame roundtrip. Run real browser end-to-end tests at phone and tablet sizes.
5. Download compiled extension, insert weak load command into a copy of original executable, package licenses and runtime, generate unsigned IPA. Verify ZIP, hashes, binary platform, no unintended original resource changes.
6. Review full changes, rerun tests, emit exact evidence and limitations. Never count static evidence as physical-device testing.
