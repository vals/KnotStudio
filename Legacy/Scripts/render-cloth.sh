#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
mkdir -p .build/module-cache
/usr/bin/xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" Sources/KnotCore/*.swift Sources/KnotStudio/Fabric.swift Sources/KnotStudio/FabricImage.swift Sources/KnotStudio/FabricViewState.swift Sources/KnotStudio/Scene.swift Sources/KnotStudio/ClothLab.swift Tools/ClothRender.swift -o .build/cloth-render -framework AppKit -framework SwiftUI -framework SceneKit
if [[ "${1:-}" != "--build-only" ]]; then
 .build/cloth-render "${1:-artifacts/cloth-0.5}"
fi
