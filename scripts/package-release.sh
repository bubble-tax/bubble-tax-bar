#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
release_version="${1:-0.1.0}"
if [[ ! "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a release version such as 0.1.0" >&2
    exit 1
fi
cd "$project_dir"
bash scripts/build-app.sh
app_dir="$project_dir/dist/Bubble Tax.app"
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")"
if [[ "$bundle_version" != "$release_version" ]]; then
    echo "App version $bundle_version does not match release $release_version" >&2
    exit 1
fi
codesign --verify --deep --strict --verbose=2 "$app_dir"
signing_status="This preview is ad-hoc signed and is not notarized by Apple."
if codesign -dvv "$app_dir" 2>&1 | grep -q 'Authority=Developer ID Application:'; then
    signing_status="This preview is Developer ID signed. Apple notarization has not been completed."
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    bash scripts/notarize-app.sh "$app_dir"
    signing_status="This preview is Developer ID signed and notarized by Apple."
fi
release_root="$project_dir/dist/releases/$release_version"
staging="$release_root/Bubble Tax $release_version"
mkdir -p "$staging"
ditto "$app_dir" "$staging/Bubble Tax.app"
cp "$project_dir/docs/releases/v$release_version.md" "$staging/RELEASE-NOTES.md"
cat > "$staging/INSTALL.txt" <<'INSTALL'
Bubble Tax Preview

Apple silicon / macOS 14+ required.
All collectors and their runtime are included. No Python, developer tools or server required.
Move Bubble Tax.app to Applications and open it. Look for † in your menu bar.
Sign in to supported AI tools, then open Settings to connect usage and logs.
If you move the app later, reconnect the Claude statusline bridge in Settings.
See RELEASE-NOTES.md for installation, first-launch and data details.
INSTALL
echo "$signing_status" >> "$staging/INSTALL.txt"
asset="Bubble-Tax-$release_version-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$staging" "$release_root/$asset"
(cd "$release_root" && shasum -a 256 "$asset" > SHA256SUMS.txt)
echo "Release asset: $release_root/$asset"
