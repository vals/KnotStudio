#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
mkdir -p .build/module-cache artifacts/cloth-0.5
/usr/bin/xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" Sources/KnotCore/*.swift Tests/ClothSafetyChecks.swift -o .build/cloth-safety-checks
.build/cloth-safety-checks | tee artifacts/cloth-0.5/safety-checks.txt
