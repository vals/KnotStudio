#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
mkdir -p .build/module-cache
/usr/bin/xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" Sources/KnotStudio/Fabric.swift Sources/KnotStudio/FabricImage.swift Sources/KnotStudio/FabricViewState.swift Tests/ViewStateChecks.swift -o .build/knot-view-checks -framework AppKit
.build/knot-view-checks
