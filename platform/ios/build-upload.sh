#!/bin/bash
# 在 Mac 上：Godot 匯出 Xcode 專案 → xcodebuild 封存 → 匯出並直接上傳到 App Store Connect。
# 要在 Mac 的「終端機」App 裡執行（SSH 進來時鑰匙圈是鎖的，簽章會失敗）：
#   osascript ~/Developer/xiaoke-flight/platform/ios/run-in-terminal.applescript "bash ~/Developer/xiaoke-flight/platform/ios/build-upload.sh"
# 加 --no-upload 只產生 App Store 用的 .ipa（不上傳）。
# log 在 ~/Developer/xiaoke-flight-build/upload.log，完成留下 upload.done（ok／fail）
PROJ=~/Developer/xiaoke-flight
ROOT=~/Developer/xiaoke-flight-build
OUT=$ROOT/ios
GODOT=~/Developer/godot/Godot.app/Contents/MacOS/Godot
VERSION=$(grep -E '^config/version=' "$PROJ/project.godot" | cut -d'"' -f2)
BUILD=$(grep -E '^application/version=' "$PROJ/export_presets.cfg" | tail -1 | cut -d'"' -f2)
PLIST="$PROJ/platform/ios/ExportOptions-AppStore.plist"
[ "$1" = "--no-upload" ] && PLIST="$PROJ/platform/ios/ExportOptions-AppStore-local.plist"

rm -rf "$OUT"
mkdir -p "$OUT"
exec > >(tee "$ROOT/upload.log") 2>&1
set -o pipefail
fail() { echo "fail" > "$ROOT/upload.done"; exit 1; }
rm -f "$ROOT/upload.done"

echo "== Xcode $(xcodebuild -version | head -1)，小柯真實飛行 v$VERSION ($BUILD)"
"$GODOT" --headless --path "$PROJ" --import >/dev/null 2>&1
"$GODOT" --headless --path "$PROJ" --export-release "iOS" "$OUT/XiaokeFlight.ipa" 2>&1 | grep -E "ERROR|DONE" || true
[ -d "$OUT/XiaokeFlight.xcodeproj" ] || fail

cd "$OUT"
SETTINGS=(CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=7BN6XJ59KP
	INFOPLIST_KEY_CFBundleDisplayName="小柯真實飛行" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD")
echo "== 封存"
xcodebuild -project XiaokeFlight.xcodeproj -scheme XiaokeFlight -configuration Release \
	-destination 'generic/platform=iOS' -archivePath build/XiaokeFlight.xcarchive \
	-allowProvisioningUpdates "${SETTINGS[@]}" archive | grep -E 'error|warning: .*sign|ARCHIVE' || fail
echo "== 匯出（App Store Connect）"
xcodebuild -exportArchive -archivePath build/XiaokeFlight.xcarchive -exportPath build/export \
	-exportOptionsPlist "$PLIST" -allowProvisioningUpdates || fail
find "$OUT" -name PrivacyInfo.xcprivacy -path "*XiaokeFlight*" | head -1 | xargs -I{} plutil -p {} || true
echo "ok" > "$ROOT/upload.done"
