#!/bin/zsh
# Paints the README pictures: docs/icon.png, docs/colors.png, docs/demo.gif and docs/strikes.gif.
# Needs ffmpeg for the GIFs (brew install ffmpeg).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=.build/release/LightTrail

"$BIN" --icon build-icon.png
sips -Z 256 build-icon.png --out docs/icon.png >/dev/null
rm build-icon.png

"$BIN" --colors docs/colors.png

for flag gif in --demo demo --strikes-demo strikes; do
  rm -rf docs/frames
  "$BIN" $flag docs/frames
  ffmpeg -loglevel error -y -framerate 30 -i docs/frames/frame_%04d.png \
    -vf "split[a][b];[a]palettegen=max_colors=256:stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a" \
    -loop 0 docs/$gif.gif
done
rm -rf docs/frames
echo "Painted docs/icon.png, docs/colors.png, docs/demo.gif and docs/strikes.gif"
