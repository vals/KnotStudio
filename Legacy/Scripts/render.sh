#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
mkdir -p .build/module-cache
/usr/bin/xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" Sources/KnotCore/*.swift Sources/KnotStudio/Fabric.swift Sources/KnotStudio/FabricImage.swift Sources/KnotStudio/Scene.swift Tools/Render.swift -o .build/knot-render -framework AppKit -framework SwiftUI -framework SceneKit
if [[ "${1:-}" != "--build-only" ]]; then
  .build/knot-render "${1:-artifacts/revision}" "${2:-fabric,side,back,routing,faces,portrait}"
fi
