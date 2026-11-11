#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
mkdir -p .build/module-cache artifacts
/usr/bin/xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" Sources/KnotCore/*.swift Tests/Checks.swift -o .build/knot-checks
.build/knot-checks | tee artifacts/checks.txt
