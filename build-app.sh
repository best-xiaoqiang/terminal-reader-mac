#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
app_dir="$project_dir/build/TerminalReader.app"

cd "$project_dir"
swift build -c release
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp ".build/release/TerminalReader" "$app_dir/Contents/MacOS/TerminalReader"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/TerminalReader.icns" "$app_dir/Contents/Resources/TerminalReader.icns"

echo "已生成：$app_dir"
