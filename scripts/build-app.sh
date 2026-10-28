#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Bubble Tax requires macOS 14+. Run this script on your Mac." >&2
    exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
    echo "Install Xcode Command Line Tools first: xcode-select --install" >&2
    exit 1
fi
if ! python3 -c 'import sys; assert sys.version_info >= (3, 9)' >/dev/null 2>&1; then
    echo "Python 3.9+ is required (included with recent Xcode Command Line Tools)." >&2
    exit 1
fi
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests -v
swift test
bash scripts/build-collector.sh
swift scripts/render-app-icon.swift
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$project_dir/dist/Bubble Tax.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/BubbleTaxBar" "$app_dir/Contents/MacOS/BubbleTaxBar"
cp "$project_dir/Sources/BubbleTaxBar/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/Sources/BubbleTaxBar/Resources/collector.py" "$app_dir/Contents/Resources/collector.py"
cp "$project_dir/Sources/BubbleTaxBar/Resources/live_usage.py" "$app_dir/Contents/Resources/live_usage.py"
cp "$project_dir/Sources/BubbleTaxBar/Resources/claude_statusline.py" "$app_dir/Contents/Resources/claude_statusline.py"
mkdir -p "$app_dir/Contents/Helpers"
for old_helper in "$app_dir/Contents/Helpers/BubbleTaxCollector" "$app_dir/Contents/Helpers/BubbleTaxCollector.app"; do
    if [[ -d "$old_helper" ]]; then
        mv "$old_helper" "$(mktemp -d "$project_dir/dist/old-collector.XXXXXX")/"
    fi
done
ditto "$project_dir/dist/collector/BubbleTaxCollector.app" "$app_dir/Contents/Helpers/BubbleTaxCollector.app"
cp "$project_dir/dist/collector-licenses.txt" "$app_dir/Contents/Resources/Collector-LICENSES.txt"
mkdir -p "$app_dir/Contents/Resources/Personas"
cp "$project_dir/Sources/BubbleTaxBar/Resources/Personas/"*.png "$app_dir/Contents/Resources/Personas/"
if [[ -x "$project_dir/vendor/codexbar/CodexBarCLI" ]]; then
    mkdir -p "$app_dir/Contents/Helpers"
    cp "$project_dir/vendor/codexbar/CodexBarCLI" "$app_dir/Contents/Helpers/"
    cp -R "$project_dir/vendor/codexbar/CodexBar_CodexBarCore.bundle" "$app_dir/Contents/Helpers/"
    cp "$project_dir/vendor/codexbar/LICENSE" "$app_dir/Contents/Resources/CodexBar-LICENSE.txt"
fi
# The local collector and its runtime ship as a nested helper app.
# Preserve legacy output outside the app before signing; SwiftPM resource
# directories without Info.plist cannot be nested under Contents/MacOS.
legacy_bundle="$app_dir/Contents/MacOS/BubbleTaxBar_BubbleTaxBar.bundle"
if [[ -d "$legacy_bundle" ]]; then
    backup_dir="$(mktemp -d "$project_dir/dist/legacy-resources.XXXXXX")"
    mv "$legacy_bundle" "$backup_dir/"
fi
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Bubble Tax</string>
<key>CFBundleDisplayName</key><string>Bubble Tax</string>
<key>CFBundleIdentifier</key><string>app.bubbletaxbar.local</string>
<key>CFBundleExecutable</key><string>BubbleTaxBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>14</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 scripts/verify-bundled-collector.py "$app_dir/Contents/Helpers/BubbleTaxCollector.app"
python3 scripts/sign-app.py "$app_dir"
echo "Built: $app_dir"
echo "Launch: open \"$app_dir\""
