#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
COMMON=(-O2 -Wall -Wextra -Wno-unused-parameter -I native)
xcrun --sdk iphoneos clang "${COMMON[@]}" -arch arm64 -miphoneos-version-min=16.3 -c native/AUHTTP.c -o dist/AUHTTP-ios.o
xcrun --sdk iphoneos clang "${COMMON[@]}" -arch arm64 -miphoneos-version-min=16.3 -fobjc-arc -fmodules -dynamiclib native/AUServer.m native/AUEngineAccess.m native/AUStudio.m dist/AUHTTP-ios.o -framework Foundation -framework UIKit -framework WebKit -framework UniformTypeIdentifiers -install_name @executable_path/Frameworks/AureaCraft.dylib -o dist/AureaCraft.dylib
xcrun --sdk macosx clang "${COMMON[@]}" -c native/AUHTTP.c -o dist/AUHTTP-mac.o
xcrun --sdk macosx clang "${COMMON[@]}" -fobjc-arc -fmodules -framework Foundation native/AUEngineAccess.m tests/engine_test.m -o dist/engine_test
./dist/engine_test
xcrun --sdk macosx clang "${COMMON[@]}" -fobjc-arc -fmodules -framework Foundation native/AUServer.m tests/server_main.m dist/AUHTTP-mac.o -o dist/server_test
python3 tests/test_server.py dist/server_test
file dist/AureaCraft.dylib | tee dist/binary-info.txt
xcrun otool -L dist/AureaCraft.dylib | tee -a dist/binary-info.txt
xcrun otool -l dist/AureaCraft.dylib > dist/load-commands.txt
shasum -a 256 dist/AureaCraft.dylib > dist/SHA256SUMS
