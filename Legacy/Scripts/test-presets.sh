#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
mkdir -p .build/module-cache artifacts/premade-0.8
/usr/bin/xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" Sources/KnotCore/*.swift Tests/PresetChecks.swift -o .build/preset-checks
.build/preset-checks | tee artifacts/premade-0.8/preset-checks.txt
