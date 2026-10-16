#!/bin/bash
# SPDX-License-Identifier: MIT
# Usage: bash tools/rebuild.sh ORIGINAL_IPA [OUTPUT_IPA]
set -euo pipefail
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo 'Usage: bash tools/rebuild.sh ORIGINAL_IPA [OUTPUT_IPA]' >&2
  exit 2
fi
if [ "$(uname -s)" != Darwin ]; then
  echo 'Native compilation requires macOS with Xcode and the iPhoneOS SDK.' >&2
  exit 2
fi
ORIGINAL="$(python3 -c 'import pathlib,sys;print(pathlib.Path(sys.argv[1]).resolve())' "$1")"
OUTPUT="$(python3 -c 'import pathlib,sys;print(pathlib.Path(sys.argv[1]).resolve())' "${2:-Aurea-Studio-rebuilt-unsigned.ipa}")"
cd "$(dirname "$0")/.."
xcrun --sdk iphoneos --find clang >/dev/null
mkdir -p dist/upstream
curl --fail --location --retry 3 https://github.com/storytold/effectcraft/releases/download/v0.10.0/effectcraft-web-0.10.0.zip -o dist/upstream/runtime.zip
curl --fail --location --retry 3 https://codeload.github.com/storytold/effectcraft/zip/7c733f4cc9043f011a5f87ef6a83d18c8fb6aa3b -o dist/upstream/source.zip
printf '%s\n' 'b922abeda2420391a7fd887f53ebae6948730e63720bad6a6eb3dc48dc1b46a8  dist/upstream/runtime.zip' 'fce1ce4a3af1ac194d047a9b4b30fdd9086b316695b3bbd4b970bc519c906487  dist/upstream/source.zip' | shasum -a 256 --check
unzip -q -o dist/upstream/source.zip -d dist/upstream
bash tools/build_native.sh
python3 tools/package_ipa.py --original "$ORIGINAL" --dylib dist/AureaCraft.dylib --runtime dist/upstream/runtime.zip --integration . --upstream dist/upstream/effectcraft-7c733f4cc9043f011a5f87ef6a83d18c8fb6aa3b --output "$OUTPUT" --report "$OUTPUT.json"
echo 'Unsigned IPA created. Re-sign all nested code, including AureaCraft.dylib, before device installation.'
