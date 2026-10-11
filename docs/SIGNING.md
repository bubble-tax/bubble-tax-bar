# GitHub distribution

Bubble Tax is distributed as a ZIP through GitHub Releases. These commands do not create a Mac App Store submission.

Local builds default to ad-hoc signing. To sign a release, use a Developer ID Application identity with its private key installed in the local Keychain:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  bash scripts/build-app.sh
```

Nested Mach-O libraries, frameworks and helper applications are signed inside-out, followed by the app. Developer ID builds enable Hardened Runtime and secure timestamps. No runtime exceptions are requested by default; test the packaged collectors after signing.

For notarization, register credentials directly in your terminal. Omit the password argument so Apple's tool prompts securely; do not put credentials in source, shell history, logs or chat:

```bash
xcrun notarytool store-credentials bubble-tax \
  --apple-id YOUR_DEVELOPER_APPLE_ID --team-id TEAMID
```

Then build, sign, notarize, staple and package:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE=bubble-tax bash scripts/package-release.sh 0.1.0
```

To notarize an already signed app without rebuilding:

```bash
NOTARY_PROFILE=bubble-tax bash scripts/notarize-app.sh
```

The script requires an Accepted result, staples and validates the ticket, and checks Gatekeeper before returning success. Submission receipts remain in ignored `dist/notarization.*` directories. Recreate the release ZIP after stapling; publish only the verified artifact and matching checksum. A Developer ID signature alone is not Apple notarization.

References: [Apple notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [Developer ID](https://developer.apple.com/developer-id/).
