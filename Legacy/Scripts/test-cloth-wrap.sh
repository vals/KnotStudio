#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
mkdir -p .build/module-cache artifacts/cloth-0.7
/usr/bin/xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" Sources/KnotCore/*.swift Tests/ClothWrapChecks.swift -o .build/cloth-wrap-checks
.build/cloth-wrap-checks | tee artifacts/cloth-0.7/wrap-checks.txt
/usr/bin/xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" Sources/KnotCore/*.swift Tools/ClothWrapProbe.swift -o .build/cloth-wrap-probe
.build/cloth-wrap-probe artifacts/cloth-0.7 | tee artifacts/cloth-0.7/wrap-probe.txt
