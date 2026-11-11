#!/bin/zsh
# Render the illustration GIFs into docs/media (needs ffmpeg).
set -euo pipefail
cd "${0:A:h}/.."
zsh Scripts/render.sh
OUT=docs/media
TMP=$(mktemp -d /tmp/knotstudio-gif.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p $OUT
gif() {  # name, then knot-render arguments
  local name=$1; shift
  .build/knot-render "$TMP/$name" "$@" fps=25
  ffmpeg -loglevel error -y -framerate 25 -i "$TMP/$name/f%04d.png" \
    -vf "split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    "$OUT/$name.gif"
  print "$OUT/$name.gif  $(du -h "$OUT/$name.gif" | cut -f1)"
}
gif four-in-hand "Li Ro Li Co T" record=6.8 size=480 zoom=13 lift=-3
gif windsor "Li Co Ri Lo Ci Ro Li Co T" record=10.8 size=480 zoom=13 lift=-3
gif pratt-inside-out "Lo Ci Lo Ri Co T" record=7.8 size=480 zoom=13 lift=-3 display=faces
gif tuck "Li Ro Li Co T" from="Li Ro Li" record=3.8 size=480 zoom=9 lift=1.5 collar=off
gif turntable "Li Co Ri Lo Ci Ro Li Co T" from="Li Co Ri Lo Ci Ro Li Co T" record=7 size=420 zoom=10 \
  at=2.4:display=faces at=4.8:display=fabric orbit=32
gif cloth "Li Ro Ci Lo Ri Co T" from="Li Ro Ci Lo Ri Co T" record=7 size=480 zoom=8 lift=-1 \
  at=0.3:cloth=finesilk at=2.5:cloth=wool at=4.8:cloth=silktwill

# The whole interface, recorded from the real app playing scripted sessions.
zsh Scripts/build.sh > /dev/null
build/KnotStudio.app/Contents/MacOS/KnotStudio --record "$TMP/app" > /dev/null 2>&1
for session in "$TMP"/app/*(/); do
  name=${session:t}
  ffmpeg -loglevel error -y -framerate 15 -i "$session/f%04d.png" \
    -vf "scale=900:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=200:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
    "$OUT/$name.gif"
  print "$OUT/$name.gif  $(du -h "$OUT/$name.gif" | cut -f1)"
done
