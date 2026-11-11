#!/bin/zsh
# Build the offscreen renderer (if sources changed) and render one image.
#   zsh Scripts/render.sh out.png "Li Ro Li Co T" [key=value ...]
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/module-cache
BIN=.build/knot-render
SOURCES=(Sources/KnotEngine/*.swift Sources/KnotStudio/Fabric.swift Sources/KnotStudio/FabricImage.swift Sources/KnotStudio/KnotScene.swift Tools/Render.swift)
NEWEST=$(ls -t $SOURCES | head -1)
if [[ ! -x $BIN || $NEWEST -nt $BIN ]]; then
  /usr/bin/xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" -parse-as-library $SOURCES -o $BIN -framework AppKit -framework SceneKit
fi
if [[ $# -gt 0 ]]; then $BIN "$@"; fi
