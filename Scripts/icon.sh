#!/bin/zsh
# Render Tools/Icon.swift and pack it into Resources/AppIcon.icns (checked in; build.sh copies it into the app).
set -euo pipefail
cd "${0:A:h}/.."
WORK="$(mktemp -d /tmp/knotstudio-icon.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p .build/module-cache Resources "$WORK/AppIcon.iconset"
/usr/bin/xcrun swift -module-cache-path "$PWD/.build/module-cache" Tools/Icon.swift "$WORK/icon_1024.png" >/dev/null
for s in 16 32 128 256 512; do
  /usr/bin/sips -z $s $s "$WORK/icon_1024.png" --out "$WORK/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  /usr/bin/sips -z $((s*2)) $((s*2)) "$WORK/icon_1024.png" --out "$WORK/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$WORK/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$WORK/icon_1024.png" docs/media/icon.png
print 'Wrote Resources/AppIcon.icns and docs/media/icon.png'
