#!/bin/zsh
# Engine checks: notation, geometry invariants for all 85 classical knots, speed.
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/module-cache
/usr/bin/xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" -parse-as-library Sources/KnotEngine/*.swift Tests/Checks.swift -o .build/knot-checks
.build/knot-checks
