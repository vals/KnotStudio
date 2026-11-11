#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
mkdir -p .build/module-cache artifacts/cloth-0.7
/usr/bin/xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" Sources/KnotCore/*.swift Tests/ClothSupportChecks.swift -o .build/cloth-support-checks
.build/cloth-support-checks | tee artifacts/cloth-0.7/support-checks.txt
