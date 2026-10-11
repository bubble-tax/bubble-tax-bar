#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="${1:-$project_dir/dist/Bubble Tax.app}"
profile="${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool Keychain profile}"
codesign --verify --deep --strict "$app_dir"
signature_metadata="$(codesign -dvv "$app_dir" 2>&1)"
if [[ "$signature_metadata" != *"Authority=Developer ID Application:"* ]]; then
    echo "Developer ID signing is required before notarization." >&2
    exit 1
fi
submission_dir="$(mktemp -d "$project_dir/dist/notarization.XXXXXX")"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$submission_dir/Bubble-Tax.zip"
xcrun notarytool submit "$submission_dir/Bubble-Tax.zip" --keychain-profile "$profile" \
    --wait --timeout 20m --output-format json > "$submission_dir/submission.json"
python3 - "$submission_dir/submission.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
print('Notarization:', result.get('status'), 'Submission:', result.get('id'))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted. Inspect the submission log before publishing.')
PY
xcrun stapler staple "$app_dir"
xcrun stapler validate "$app_dir"
codesign --verify --deep --strict "$app_dir"
spctl --assess --type execute --verbose=2 "$app_dir"
echo "Notarized and stapled: $app_dir"
