#!/usr/bin/env bash
# 建置線上版：bash tools/build_web.sh → ../build/flight-web/ 與 ../build/xiaoke-flight-web.zip
set -euo pipefail
cd "$(dirname "$0")/.."
GD="${GODOT:-/e/從零建置 Godot 賽車遊戲/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
OUT=../build/flight-web
mkdir -p "$OUT"
find "$OUT" -mindepth 1 -maxdepth 1 -name 'index*' -delete
"$GD" --headless --path . --export-release "Web" "$OUT/index.html"
cp docs/version.json "$OUT/version.json"
python -I tools/patch_manifest.py "$OUT"
( cd "$OUT" && rm -f ../xiaoke-flight-web.zip && "/c/Program Files/7-Zip/7z.exe" a -tzip ../xiaoke-flight-web.zip ./* >/dev/null 2>&1 || powershell -NoProfile -Command "Compress-Archive -Path * -DestinationPath ../xiaoke-flight-web.zip -Force" )
ls -la "$OUT" ../build/xiaoke-flight-web.zip
