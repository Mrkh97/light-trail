#!/bin/zsh
# Paints the README pictures: docs/icon.png, docs/colors.png and docs/demo.gif.
# Needs ffmpeg for the GIF (brew install ffmpeg).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=.build/release/LightTrail

"$BIN" --icon build-icon.png
sips -Z 256 build-icon.png --out docs/icon.png >/dev/null
rm build-icon.png

"$BIN" --colors docs/colors.png

rm -rf docs/frames
"$BIN" --demo docs/frames
ffmpeg -loglevel error -y -framerate 30 -i docs/frames/frame_%04d.png \
  -vf "split[a][b];[a]palettegen=max_colors=256:stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a" \
  -loop 0 docs/demo.gif
rm -rf docs/frames
echo "Painted docs/icon.png, docs/colors.png and docs/demo.gif"
