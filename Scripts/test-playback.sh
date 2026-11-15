#!/bin/zsh
# Model checks without launching a window or touching user data.
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/module-cache
/usr/bin/xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" -parse-as-library \
  Sources/KnotEngine/*.swift Sources/KnotStudio/{Fabric,FabricImage,KnotScene,StudioModel}.swift \
  Tests/PlaybackChecks.swift -o .build/playback-checks -framework AppKit -framework SwiftUI -framework SceneKit
.build/playback-checks
