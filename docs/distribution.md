# Distribution: Signing, Notarization, and Homebrew Cask

How Micspresso ships as a notarized `.app` through Homebrew without
triggering Gatekeeper warnings.

## What "no warnings" requires

For a downloaded `.app` outside the App Store, macOS stays quiet only when
**all three** are true:

1. **Signed** with a *Developer ID Application* certificate (not ad-hoc).
2. **Hardened Runtime** enabled, with entitlements declaring protected
   resources — for Micspresso that's `com.apple.security.device.audio-input`
   (microphone access is blocked outright under the hardened runtime without
   it).
3. **Notarized** by Apple and the ticket **stapled** to the bundle.

A proper signed bundle also gives Micspresso a stable TCC identity: macOS
tracks the microphone permission by bundle ID + code signature, so upgrades
keep their grant. (Bare ad-hoc binaries get their permission orphaned
whenever the binary changes — a documented pain point of the predecessor
tool.)

## One-time Apple Developer setup

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/) ($99/year).
2. Create a **Developer ID Application** certificate (Xcode → Settings →
   Accounts → Manage Certificates → `+`), then verify:
   ```bash
   security find-identity -v -p codesigning
   # Should list: "Developer ID Application: <Team Name> (<TEAM_ID>)"
   ```
3. Create an app-specific password at [appleid.apple.com](https://appleid.apple.com)
   (Sign-In and Security → App-Specific Passwords), e.g. labeled
   `micspresso-notarization`.
4. Store notarization credentials in the keychain for local use:
   ```bash
   xcrun notarytool store-credentials "micspresso-notarization" \
     --apple-id "your@email.com" \
     --team-id "<TEAM_ID>" \
     --password "<app-specific-password>"
   ```

## Local signing & notarization

Copy `.env.example` to `.env` (gitignored) and fill in `TEAM_NAME` and
`TEAM_ID`. Then:

```bash
make notarize
```

This builds the release bundle, signs it with your Developer ID (hardened
runtime + timestamp + entitlements), submits to Apple via
`notarytool submit --wait` using the `micspresso-notarization` keychain
profile (override with `NOTARY_PROFILE=<other>`), staples the ticket, and
validates it.

Sanity checks:

```bash
codesign --display --verbose=2 .build/release/Micspresso.app
spctl --assess --type execute --verbose .build/release/Micspresso.app
# Expect: "accepted" and "source=Notarized Developer ID"
```

## Local dev builds and TCC

Builds without Developer ID credentials produce a separate dev app —
**"Micspresso Dev.app"** with bundle ID `com.moltenbits.micspresso.dev` — so
dev and release builds never share TCC permission records. (Reusing one
bundle ID across different signatures leaves stale mismatched TCC entries
that suppress prompts or block launches.)

Dev bundles are signed with the first available local code-signing
certificate — `Micspresso Dev`, then `Spacebar Dev` — falling back to ad-hoc
when neither exists. A real (even self-signed) certificate matters: TCC keys
the microphone grant to the app's designated requirement, and an ad-hoc
signature's requirement is the binary's cdhash, which changes every rebuild
and re-prompts every time. A certificate-signed dev build prompts once, ever.

To create the cert on a new machine: Keychain Access → Certificate Assistant
→ Create a Certificate… → name `Micspresso Dev`, type **Code Signing**. You
can also set `SIGN_IDENTITY=<cert name>` in `.env` to use any other identity.

## GitHub Actions release setup

The release workflow (`.github/workflows/release.yml`) runs on every `v*`
tag push.

### 1. Export the certificate

```bash
P12_PASS=$(openssl rand -base64 24)
echo "P12_PASSWORD (save this for the GitHub secret):"
echo "$P12_PASS"

security export \
  -k ~/Library/Keychains/login.keychain-db \
  -t identities \
  -f pkcs12 \
  -P "$P12_PASS" \
  -o ~/Desktop/micspresso-cert.p12

base64 -i ~/Desktop/micspresso-cert.p12 | pbcopy
echo "BUILD_CERTIFICATE_BASE64 copied to clipboard."
```

### 2. Add repository secrets

In **Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | The base64-encoded `.p12` |
| `P12_PASSWORD` | The password used when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | Any random string (the CI keychain is temporary) |
| `TEAM_NAME` | Team name as it appears in the Developer ID identity |
| `TEAM_ID` | Your team ID |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_APP_PASSWORD` | The app-specific password |
| `HOMEBREW_CASK_TOKEN` | A token with push access to `moltenbits/homebrew-tap` (if unset, the cask update step is skipped) |

### 3. What the workflow does

On a `v*` tag push:

1. Imports the certificate into a temporary keychain on the runner.
2. Runs `scripts/release.sh <version>`, which builds + signs
   (`scripts/bundle.sh`), notarizes, staples, and creates
   `dist/micspresso-<version>-macos.tar.gz`.
3. Creates a GitHub Release with the tarball attached.
4. Updates `Casks/micspresso.rb` in `moltenbits/homebrew-tap` with the new
   version, URL, and SHA256 (skipped for pre-release tags like `v1.2.0-rc.1`).

### 4. Cutting a release

```bash
git tag v1.0.0
git push origin v1.0.0
```

After the workflow completes:

```bash
brew install --cask moltenbits/tap/micspresso
```

## File reference

| File | Purpose |
|---|---|
| `.env` | Local signing config (gitignored): `TEAM_NAME`, `TEAM_ID` |
| `.env.example` | Committed template |
| `Resources/Micspresso.entitlements` | Hardened-runtime mic entitlement |
| `scripts/bundle.sh` | Builds the `.app`, stamps the version, signs (Developer ID if `.env`/env set, ad-hoc otherwise) |
| `scripts/release.sh` | Calls `bundle.sh`, conditionally notarizes + staples, creates `dist/*.tar.gz` |
| `scripts/make-icon.sh` | Regenerates `Resources/AppIcon.icns` from `icon.svg` (dev-time only; needs `brew install librsvg`) |
| `.github/workflows/release.yml` | CI: import cert, sign, notarize, release, update Homebrew tap |

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Notarization: "signature does not include a secure timestamp" | Missing `--timestamp` on `codesign` — check `bundle.sh` |
| Notarization: "does not have the hardened runtime enabled" | Missing `--options runtime` — check `bundle.sh` |
| App runs but mic access silently fails after signing | Entitlements file not applied — hardened runtime requires `com.apple.security.device.audio-input` |
| `spctl --assess` returns "rejected" | Ticket not stapled (`xcrun stapler validate` to confirm) or notarization failed — check `xcrun notarytool log <id>` |
| `errSecInternalComponent` during codesign in CI | Temporary keychain locked or cert untrusted — confirm the `set-key-partition-list` step ran |
