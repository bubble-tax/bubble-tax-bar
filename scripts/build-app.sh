#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "SubRIP requires macOS 13+. Run this script on your Mac." >&2
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
python3 -m unittest discover -s tests -v
swift test
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$project_dir/dist/SubRIP.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/SubRIP" "$app_dir/Contents/MacOS/SubRIP"
cp "$project_dir/Sources/SubRIP/Resources/collector.py" "$app_dir/Contents/Resources/collector.py"
resource_bundle="$binary_dir/SubRIP_SubRIP.bundle"
if [[ ! -d "$resource_bundle" ]]; then
    echo "Missing SwiftPM resource bundle: $resource_bundle" >&2
    exit 1
fi
# Keep the SwiftPM bundle for development. Packaged apps resolve collector.py
# from Contents/Resources before touching Bundle.module's build-time fallback.
cp -R "$resource_bundle" "$app_dir/Contents/MacOS/"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>SubRIP</string>
<key>CFBundleDisplayName</key><string>SubRIP</string>
<key>CFBundleIdentifier</key><string>app.subrip.local</string>
<key>CFBundleExecutable</key><string>SubRIP</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app_dir"
echo "Built: $app_dir"
echo "Launch: open \"$app_dir\""
