# Auto-Update Feature Design Spec

## Overview

Add automatic update detection and installation to LedgeIt using the Sparkle 2 framework. The app checks for updates on launch and every 24 hours, notifies the user when a new version is available, and provides one-click install + relaunch.

## Goals

- Users are notified of new releases without manual checking
- One-click update experience (download, verify, install, relaunch)
- Secure updates via EdDSA signature verification
- Minimal code footprint — leverage Sparkle's battle-tested infrastructure

## Non-Goals

- Delta/binary-diff updates (standard full-DMG replacement is sufficient)
- Custom SwiftUI update UI (Sparkle's default AppKit dialog is acceptable)
- Beta/staging update channels
- App Store distribution (this is a direct-distribution app)

## Architecture

```
App Launch
  │
  ▼
SPUStandardUpdaterController (Sparkle 2)
  ├── Automatic check on launch
  ├── Periodic check every 24 hours
  └── Manual check via Settings > "Check for Updates"
  │
  ▼
Fetch appcast.xml (GitHub raw URL)
  │
  ▼
Compare sparkle:version with Bundle.main CFBundleShortVersionString
  │
  ▼
If newer version found:
  ├── Show Sparkle update dialog (release notes, version info)
  ├── User clicks "Install Update"
  ├── Download DMG from GitHub Release asset URL
  ├── Verify EdDSA signature
  ├── Extract and replace app bundle
  └── Relaunch
```

## Component 1: Dependencies & Integration

### Sparkle 2 via SPM

Add to `LedgeIt/Package.swift`:

```swift
// In dependencies array:
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),

// In executableTarget dependencies:
.product(name: "Sparkle", package: "Sparkle"),
```

Note: Sparkle 2 bundles its own XPC installer service for sandboxed apps. No additional XPC configuration is needed — it handles privilege escalation for app replacement automatically.

### Info.plist Configuration (in `build.sh`)

Add these keys to the `Info.plist` heredoc in `LedgeIt/build.sh`:

| Key | Value | Purpose |
|-----|-------|---------|
| `SUFeedURL` | `https://raw.githubusercontent.com/YuehChun/ledgeit/main/appcast.xml` | Appcast location |
| `SUPublicEDKey` | *(generated public key — see Component 2)* | EdDSA signature verification |
| `SUEnableAutomaticChecks` | `true` | Enable auto-check on launch |
| `SUScheduledCheckInterval` | `86400` | Check every 24 hours |

### Entitlements

No changes needed — `com.apple.security.network.client` is already present in `build.sh`'s Info.plist, which allows Sparkle to fetch the appcast and download updates.

### Version Handling

Sparkle uses `sparkle:version` in the appcast to compare against `CFBundleVersion` in the app's Info.plist. Both `CFBundleVersion` and `CFBundleShortVersionString` are set to the same semantic version string (e.g., `1.2.0`) in `build.sh`, so both appcast fields should match.

## Component 2: EdDSA Key Generation & Signing

### One-Time Setup

1. Clone Sparkle and build the CLI tools, or download from Sparkle releases:
   ```bash
   # Option A: From Sparkle release artifacts
   # Download Sparkle-2.x.x.tar.xz from https://github.com/sparkle-project/Sparkle/releases
   # Extract — CLI tools are in bin/

   # Option B: Build from source
   git clone https://github.com/sparkle-project/Sparkle.git
   cd Sparkle && make release
   ```
2. Generate EdDSA key pair:
   ```bash
   ./bin/generate_keys
   ```
   This prints the **public key** (base64 string) and stores the **private key** in the macOS Keychain of the machine that ran it.
3. Export the private key for CI:
   ```bash
   ./bin/generate_keys -x
   ```
   Save the output as GitHub Actions secret: `SPARKLE_EDDSA_PRIVATE_KEY`
4. Copy the public key string into `build.sh`'s Info.plist as `SUPublicEDKey`

### CI Signing Flow

After `build.sh` creates the DMG:
1. Write the private key secret to a temp file
2. Run: `./bin/sign_update LedgeIt-X.Y.Z.dmg -f <private_key_file>`
3. Output: `sparkle:edSignature="BASE64_SIGNATURE" length="FILE_SIZE"`
4. Parse signature and length for the appcast entry
5. Clean up temp key file

## Component 3: Appcast XML & GitHub Releases Integration

### Appcast File

`appcast.xml` at the repo root, served via `https://raw.githubusercontent.com/YuehChun/ledgeit/main/appcast.xml`.

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>LedgeIt Updates</title>
    <item>
      <title>Version X.Y.Z</title>
      <sparkle:version>X.Y.Z</sparkle:version>
      <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/YuehChun/ledgeit/releases/download/vX.Y.Z/LedgeIt-X.Y.Z.dmg"
                 length="FILE_SIZE_BYTES"
                 type="application/octet-stream"
                 sparkle:edSignature="BASE64_EDDSA_SIGNATURE" />
    </item>
  </channel>
</rss>
```

Note: The DMG filename in the release URL includes the version (e.g., `LedgeIt-1.2.0.dmg`), matching the existing CI convention.

### CI Workflow Update (`.github/workflows/release.yml`)

Add these steps between "Generate checksum" and "Create Release":

```yaml
- name: Download Sparkle CLI
  run: |
    SPARKLE_VERSION="2.7.5"
    curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip" -o sparkle.zip
    unzip -q sparkle.zip -d sparkle-tools
    chmod +x sparkle-tools/bin/sign_update

- name: Sign DMG with EdDSA
  working-directory: LedgeIt/.build
  run: |
    echo "${{ secrets.SPARKLE_EDDSA_PRIVATE_KEY }}" > /tmp/sparkle_private_key
    SIGN_OUTPUT=$(../sparkle-tools/bin/sign_update "LedgeIt-${{ steps.version.outputs.version }}.dmg" -f /tmp/sparkle_private_key)
    rm -f /tmp/sparkle_private_key
    # Parse: sparkle:edSignature="..." length="..."
    ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
    FILE_LENGTH=$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
    echo "ed_signature=$ED_SIGNATURE" >> "$GITHUB_OUTPUT"
    echo "file_length=$FILE_LENGTH" >> "$GITHUB_OUTPUT"
  id: sign

- name: Update appcast.xml
  run: |
    VERSION="${{ steps.version.outputs.version }}"
    ED_SIG="${{ steps.sign.outputs.ed_signature }}"
    FILE_LEN="${{ steps.sign.outputs.file_length }}"
    DMG_URL="https://github.com/YuehChun/ledgeit/releases/download/v${VERSION}/LedgeIt-${VERSION}.dmg"

    NEW_ITEM="    <item>\n      <title>Version ${VERSION}</title>\n      <sparkle:version>${VERSION}</sparkle:version>\n      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>\n      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>\n      <enclosure url=\"${DMG_URL}\"\n                 length=\"${FILE_LEN}\"\n                 type=\"application/octet-stream\"\n                 sparkle:edSignature=\"${ED_SIG}\" />\n    </item>"

    # Insert new item after <channel><title> line
    sed -i '' "/<title>LedgeIt Updates<\/title>/a\\
    ${NEW_ITEM}
    " appcast.xml

    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add appcast.xml
    git commit -m "chore: update appcast.xml for v${VERSION}"
    git push origin HEAD:main
```

## Component 4: App Code Changes

### AppDelegate (`LedgeIt/LedgeIt/AppDelegate.swift`)

New file — a supporting class (not replacing the SwiftUI App struct):

```swift
import Cocoa
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController: SPUStandardUpdaterController

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }
}
```

### App Entry Point Modification (`LedgeIt/LedgeIt/LedgeItApp.swift`)

Add the adaptor to the existing `@main` struct:

```swift
@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

This gives Sparkle a proper app delegate lifecycle while keeping the SwiftUI app structure intact.

### Settings UI Addition (`LedgeIt/LedgeIt/Views/Settings/SettingsView.swift`)

Add an "Updates" section:

```swift
Section("Updates") {
    HStack {
        Text("Current Version")
        Spacer()
        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
            .foregroundStyle(.secondary)
    }

    Toggle("Automatically check for updates",
           isOn: Binding(
               get: { appDelegate.updaterController.updater.automaticallyChecksForUpdates },
               set: { appDelegate.updaterController.updater.automaticallyChecksForUpdates = $0 }
           ))

    Button("Check for Updates") {
        appDelegate.updaterController.checkForUpdates(nil)
    }
}
```

The `appDelegate` reference comes from `@EnvironmentObject` or passed down from the App struct.

### Files Changed

| File | Action |
|------|--------|
| `LedgeIt/Package.swift` | Add Sparkle 2 SPM dependency |
| `LedgeIt/LedgeIt/AppDelegate.swift` | Create — SPUStandardUpdaterController setup |
| `LedgeIt/LedgeIt/LedgeItApp.swift` | Modify — add `@NSApplicationDelegateAdaptor` |
| `LedgeIt/LedgeIt/Views/Settings/SettingsView.swift` | Modify — add Updates section |
| `LedgeIt/build.sh` | Modify — add SUFeedURL, SUPublicEDKey, etc. to Info.plist |
| `.github/workflows/release.yml` | Modify — add EdDSA signing and appcast generation steps |
| `appcast.xml` | Create — initial empty appcast at repo root |

## Security

- **EdDSA signatures** — Every DMG is signed with a private key stored only in GitHub Actions secrets. The app verifies against the embedded public key before installing.
- **HTTPS transport** — GitHub raw URLs use HTTPS, preventing MITM on appcast fetches.
- **Sandboxed** — Sparkle 2 handles sandboxed apps via its bundled XPC installer service. No additional entitlements required beyond `network.client`.
- **Key rotation** — If the private key is compromised, generate a new key pair, update `SUPublicEDKey` in `build.sh`, and update the GitHub secret. Users on old versions will need to manually download the next release (one-time).

## Testing

- **Local appcast test**: Build the app, create a test `appcast.xml` with a higher version number pointing to a local HTTP server (`python3 -m http.server`), set `SUFeedURL` to `http://localhost:8000/appcast.xml` temporarily, and verify the update dialog appears.
- **Signature verification test**: Tamper with the appcast signature and verify Sparkle refuses to install.
- **CI verification**: After a tag push, verify the release workflow produces a signed DMG and the appcast.xml is updated with the correct entry.
- **Version comparison**: Ensure `CFBundleVersion` in the built app matches the `sparkle:version` in appcast, and that Sparkle correctly detects a newer version.

## Error Handling

- **Network failure**: Sparkle silently retries on next scheduled check. No user-facing error for background checks.
- **Signature mismatch**: Sparkle shows an error dialog and aborts. The app remains on its current version.
- **Download failure**: Sparkle retries or shows an error. User can retry via Settings > "Check for Updates".
- **Corrupted DMG**: Sparkle validates the archive before extraction. If invalid, update is aborted.
