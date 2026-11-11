#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
mkdir -p .build/module-cache
/usr/bin/xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" Sources/KnotCore/*.swift Sources/KnotStudio/Fabric.swift Sources/KnotStudio/FabricImage.swift Sources/KnotStudio/Scene.swift Tests/RenderingChecks.swift -o .build/knot-rendering-checks -framework AppKit -framework SwiftUI -framework SceneKit
if [[ "${1:-}" != "--build-only" ]]; then
 .build/knot-rendering-checks "${1:-artifacts/v0.3-tests}"
fi
