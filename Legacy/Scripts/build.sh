#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
mkdir -p .build/module-cache build/KnotStudio.app/Contents/MacOS build/KnotStudio.app/Contents/Resources
SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
/usr/bin/xcrun swiftc -O -sdk "$SDK_PATH" -target arm64-apple-macosx13.0 -module-cache-path "$CLANG_MODULE_CACHE_PATH" -parse-as-library Sources/KnotCore/*.swift Sources/KnotStudio/*.swift -o build/KnotStudio.app/Contents/MacOS/KnotStudio -framework AppKit -framework SwiftUI -framework SceneKit
cat > build/KnotStudio.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>KnotStudio</string>
<key>CFBundleIdentifier</key><string>local.knotstudio.prototype</string>
<key>CFBundleName</key><string>Knot Studio</string>
<key>CFBundleDisplayName</key><string>Knot Studio</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.8</string>
<key>CFBundleVersion</key><string>10</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Sign in a private temporary folder: File Provider adds FinderInfo to app
# directories in Documents, which codesign rejects during signing.
STAGING_DIR="$(mktemp -d /tmp/knotstudio-sign.XXXXXX)"
trap 'rm -rf "$STAGING_DIR"' EXIT
/usr/bin/ditto --norsrc --noextattr build/KnotStudio.app "$STAGING_DIR/KnotStudio.app"
/usr/bin/codesign --force --sign - "$STAGING_DIR/KnotStudio.app"
# Canonical build output is a clean archive. File Provider may later reapply
# FinderInfo to expanded .app folders in Documents, even after scoped cleanup.
/usr/bin/ditto --norsrc --noextattr -c -k --keepParent "$STAGING_DIR/KnotStudio.app" build/KnotStudio.app.zip
/usr/bin/ditto --norsrc --noextattr -x -k build/KnotStudio.app.zip "$STAGING_DIR/verify"
/usr/bin/codesign --verify --strict "$STAGING_DIR/verify/KnotStudio.app"
/usr/bin/ditto --norsrc --noextattr "$STAGING_DIR/KnotStudio.app" build/KnotStudio.app
# Only a generated output is cleaned; unrelated metadata is left intact.
/usr/bin/xattr -dr com.apple.FinderInfo build/KnotStudio.app 2>/dev/null || true
print 'Built build/KnotStudio.app; verified clean extraction of build/KnotStudio.app.zip'
