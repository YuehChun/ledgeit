# Auto-Update (Sparkle 2) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automatic update detection and one-click installation to LedgeIt using Sparkle 2.

**Architecture:** Sparkle 2 added via SPM, initialized in an `AppDelegate` class wired to the SwiftUI `@main` struct via `@NSApplicationDelegateAdaptor`. CI workflow signs DMGs with EdDSA and updates an `appcast.xml` in the repo root.

**Tech Stack:** Sparkle 2 (SPM), EdDSA signing, GitHub Actions, GitHub raw URL for appcast

**Spec:** `docs/superpowers/specs/2026-03-13-auto-update-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `LedgeIt/Package.swift` | Modify | Add Sparkle 2 SPM dependency |
| `LedgeIt/LedgeIt/AppDelegate.swift` | Create | Initialize `SPUStandardUpdaterController` |
| `LedgeIt/LedgeIt/LedgeItApp.swift` | Modify | Wire AppDelegate via `@NSApplicationDelegateAdaptor` |
| `LedgeIt/LedgeIt/Views/SettingsView.swift` | Modify | Add "Updates" section with check button + auto-check toggle |
| `LedgeIt/build.sh` | Modify | Add Sparkle Info.plist keys (SUFeedURL, SUPublicEDKey, etc.) |
| `appcast.xml` | Create | Initial empty appcast XML at repo root |
| `.github/workflows/release.yml` | Modify | Add EdDSA signing + appcast generation steps |

---

## Chunk 1: App-Side Integration

### Task 1: Add Sparkle 2 SPM Dependency

**Files:**
- Modify: `LedgeIt/Package.swift`

- [ ] **Step 1: Add Sparkle to Package.swift dependencies array**

In `LedgeIt/Package.swift`, add to the `dependencies` array (after the ZIPFoundation line):

```swift
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
```

- [ ] **Step 2: Add Sparkle to executableTarget dependencies**

In the `executableTarget` dependencies array, add:

```swift
.product(name: "Sparkle", package: "Sparkle"),
```

- [ ] **Step 3: Resolve and build**

Run from `LedgeIt/`:
```bash
swift package resolve && swift build
```

Expected: Build succeeds. Sparkle framework is downloaded and linked.

- [ ] **Step 4: Commit**

```bash
git add LedgeIt/Package.swift
git commit -m "feat(update): add Sparkle 2 SPM dependency"
```

---

### Task 2: Create AppDelegate with Sparkle Updater

**Files:**
- Create: `LedgeIt/LedgeIt/AppDelegate.swift`
- Modify: `LedgeIt/LedgeIt/LedgeItApp.swift`

- [ ] **Step 1: Create AppDelegate.swift**

Create `LedgeIt/LedgeIt/AppDelegate.swift`:

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

This class:
- Conforms to `NSApplicationDelegate` (required by `@NSApplicationDelegateAdaptor`)
- Creates Sparkle's `SPUStandardUpdaterController` which starts checking for updates on launch
- The `startingUpdater: true` parameter means Sparkle begins its auto-check cycle immediately

- [ ] **Step 2: Wire AppDelegate into LedgeItApp.swift**

In `LedgeIt/LedgeIt/LedgeItApp.swift`, add the adaptor property inside the struct, right after the `@State private var database` line:

```swift
@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

The file should look like:

```swift
import SwiftUI

@main
struct LedgeItApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var database = AppDatabase.shared

    init() {
        KeychainService.preload()
        AIProviderConfigStore.migrateFromLegacy()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(database)
                .task {
                    print("[EmbeddingService] Starting batch indexing task...")
                    let embeddingService = EmbeddingService()
                    do {
                        try await embeddingService.indexUnembeddedTransactions { current, total in
                            print("[EmbeddingService] Indexing \(current)/\(total) transactions...")
                        }
                        print("[EmbeddingService] Batch indexing complete.")
                    } catch {
                        print("[EmbeddingService] Batch indexing failed: \(error)")
                    }
                }
        }
        Settings {
            SettingsView()
                .environment(database)
        }
    }
}
```

- [ ] **Step 3: Build to verify**

Run from `LedgeIt/`:
```bash
swift build
```

Expected: Build succeeds. Sparkle's updater controller is initialized on app launch.

- [ ] **Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/AppDelegate.swift LedgeIt/LedgeIt/LedgeItApp.swift
git commit -m "feat(update): create AppDelegate with Sparkle updater controller"
```

---

### Task 3: Add Updates Section to SettingsView

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/SettingsView.swift`

The SettingsView uses a two-column layout. The "Updates" section goes in the right column (`VStack(spacing: 16)` starting around line 120), after the action buttons section and before the closing of the right column VStack.

- [ ] **Step 1: Add the Updates section**

In `LedgeIt/LedgeIt/Views/SettingsView.swift`, add this section inside the right column VStack, after the action buttons `VStack(spacing: 8) { ... }` block (after line 230) and before the closing `}` on line 231 (the right column's closing brace):

```swift
SettingsSection(title: "Updates", icon: "arrow.triangle.2.circlepath", color: .purple) {
    VStack(alignment: .leading, spacing: 10) {
        HStack {
            Text("Current Version")
                .foregroundStyle(.secondary)
            Spacer()
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.callout)

        Divider()

        Toggle("Automatically check for updates", isOn: Binding(
            get: {
                (NSApp.delegate as? AppDelegate)?.updaterController.updater.automaticallyChecksForUpdates ?? true
            },
            set: { newValue in
                (NSApp.delegate as? AppDelegate)?.updaterController.updater.automaticallyChecksForUpdates = newValue
            }
        ))
        .font(.callout)

        Button {
            (NSApp.delegate as? AppDelegate)?.updaterController.checkForUpdates(nil)
        } label: {
            Label("Check for Updates", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.regular)
    }
}
```

Key design decisions:
- Uses `NSApp.delegate as? AppDelegate` to access the updater controller — this avoids threading `appDelegate` through the view hierarchy since `SettingsView` is used both in `ContentView` detail and `LedgeItApp` Settings scene
- Follows existing `SettingsSection` component pattern
- Uses `.callout` font to match existing sections
- Shows current version using `CFBundleShortVersionString` from the bundle

- [ ] **Step 2: Build to verify**

Run from `LedgeIt/`:
```bash
swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Views/SettingsView.swift
git commit -m "feat(update): add Updates section to SettingsView"
```

---

### Task 4: Add Sparkle Info.plist Keys to build.sh

**Files:**
- Modify: `LedgeIt/build.sh`

- [ ] **Step 1: Add Sparkle keys to Info.plist heredoc**

In `LedgeIt/build.sh`, add these keys inside the `<dict>` block of the Info.plist heredoc, before the closing `</dict>` tag (before line 59):

```xml
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/YuehChun/ledgeit/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>PLACEHOLDER_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
```

Note: `SUPublicEDKey` uses a placeholder value. It must be replaced with the actual EdDSA public key after running Sparkle's `generate_keys` tool (a one-time manual step before the first release). The key generation process is documented in the spec under "Component 2: EdDSA Key Generation & Signing".

- [ ] **Step 2: Verify build.sh still works**

Run from `LedgeIt/`:
```bash
bash build.sh 0.0.1-test
```

Expected: Build succeeds, DMG created. Verify Info.plist contains Sparkle keys:
```bash
cat .build/LedgeIt.app/Contents/Info.plist | grep -A1 SUFeedURL
```

- [ ] **Step 3: Clean up test build**

```bash
rm -rf LedgeIt/.build/LedgeIt.app LedgeIt/.build/LedgeIt-0.0.1-test.dmg
```

- [ ] **Step 4: Commit**

```bash
git add LedgeIt/build.sh
git commit -m "feat(update): add Sparkle Info.plist keys to build.sh"
```

---

## Chunk 2: CI & Appcast Integration

### Task 5: Create Initial Appcast XML

**Files:**
- Create: `appcast.xml` (repo root)

- [ ] **Step 1: Create empty appcast.xml**

Create `appcast.xml` at the repository root:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>LedgeIt Updates</title>
  </channel>
</rss>
```

This is the initial empty appcast. The CI workflow will append `<item>` entries as releases are made.

- [ ] **Step 2: Commit**

```bash
git add appcast.xml
git commit -m "feat(update): create initial empty appcast.xml"
```

---

### Task 6: Update CI Workflow for EdDSA Signing & Appcast

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add Sparkle CLI download step**

In `.github/workflows/release.yml`, add this step after "Generate checksum" (after line 44) and before "Create Release":

```yaml
      - name: Download Sparkle CLI
        run: |
          SPARKLE_VERSION="2.7.5"
          curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip" -o sparkle.zip
          unzip -q sparkle.zip -d sparkle-tools
          chmod +x sparkle-tools/bin/sign_update
```

- [ ] **Step 2: Add DMG signing step**

Add after the "Download Sparkle CLI" step:

```yaml
      - name: Sign DMG with EdDSA
        working-directory: LedgeIt/.build
        id: sign
        run: |
          echo "${{ secrets.SPARKLE_EDDSA_PRIVATE_KEY }}" > /tmp/sparkle_private_key
          SIGN_OUTPUT=$(../../sparkle-tools/bin/sign_update "LedgeIt-${{ steps.version.outputs.version }}.dmg" -f /tmp/sparkle_private_key)
          rm -f /tmp/sparkle_private_key
          ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
          FILE_LENGTH=$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
          echo "ed_signature=$ED_SIGNATURE" >> "$GITHUB_OUTPUT"
          echo "file_length=$FILE_LENGTH" >> "$GITHUB_OUTPUT"
```

Note the `working-directory` is `LedgeIt/.build` so the path to sparkle-tools is `../../sparkle-tools/bin/sign_update` (two levels up from `.build`).

- [ ] **Step 3: Add appcast update step**

Add after the "Sign DMG with EdDSA" step:

```yaml
      - name: Update appcast.xml
        run: |
          VERSION="${{ steps.version.outputs.version }}"
          ED_SIG="${{ steps.sign.outputs.ed_signature }}"
          FILE_LEN="${{ steps.sign.outputs.file_length }}"
          DMG_URL="https://github.com/YuehChun/ledgeit/releases/download/v${VERSION}/LedgeIt-${VERSION}.dmg"

          # Build the new <item> block
          NEW_ITEM=$(cat <<ITEM
              <item>
                <title>Version ${VERSION}</title>
                <sparkle:version>${VERSION}</sparkle:version>
                <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
                <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
                <enclosure url="${DMG_URL}"
                           length="${FILE_LEN}"
                           type="application/octet-stream"
                           sparkle:edSignature="${ED_SIG}" />
              </item>
          ITEM
          )

          # Insert new item before </channel>
          awk -v item="$NEW_ITEM" '/<\/channel>/{print item}1' appcast.xml > appcast_tmp.xml
          mv appcast_tmp.xml appcast.xml

          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add appcast.xml
          git commit -m "chore: update appcast.xml for v${VERSION}"
          git push origin HEAD:main
```

This uses `awk` instead of `sed` for more reliable cross-platform XML insertion. It inserts the new `<item>` block right before `</channel>`.

- [ ] **Step 4: Verify the complete workflow file**

The final `.github/workflows/release.yml` should have steps in this order:
1. Checkout
2. Determine version
3. Setup Swift
4. Build DMG
5. Generate checksum
6. **Download Sparkle CLI** (new)
7. **Sign DMG with EdDSA** (new)
8. **Update appcast.xml** (new)
9. Create Release

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat(update): add EdDSA signing and appcast generation to CI"
```

---

### Task 7: Manual Setup Documentation

This task documents the one-time manual steps needed before the first auto-update-enabled release.

- [ ] **Step 1: Verify all changes build**

Run from `LedgeIt/`:
```bash
swift build
```

Expected: Clean build with no errors.

- [ ] **Step 2: Document the one-time setup steps**

The following manual steps must be completed before the first release:

1. **Generate EdDSA key pair** — Download Sparkle CLI tools from the Sparkle GitHub releases page, run `./bin/generate_keys` to create a key pair, then run `./bin/generate_keys -x` to export the private key.

2. **Store private key in GitHub** — Go to repo Settings > Secrets > Actions, create secret `SPARKLE_EDDSA_PRIVATE_KEY` with the exported private key.

3. **Update SUPublicEDKey in build.sh** — Replace the `PLACEHOLDER_PUBLIC_KEY` value in `build.sh`'s Info.plist with the actual public key string printed by `generate_keys`.

4. **Tag and release** — Push a version tag (e.g., `git tag v1.3.0 && git push origin v1.3.0`) to trigger the CI workflow which will build, sign, update the appcast, and create the GitHub release.

- [ ] **Step 3: Final commit (if any remaining changes)**

```bash
git status
# If there are uncommitted changes:
git add -A
git commit -m "feat(update): complete Sparkle 2 auto-update integration"
```
