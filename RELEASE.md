# Release Process

This document describes how to create a new release of Compote.

## Prerequisites

1. Ensure all changes are committed and pushed
2. All tests pass: `swift test`
3. Version is bumped in appropriate places
4. `CHANGELOG.md` is updated
5. Homebrew formula dependencies are current (`swift`, `xcode`, `socat`)
6. Bottle install smoke check passes: `./scripts/test-bottle-install.sh`
7. Release signing secrets are configured in GitHub (required)

## GitHub Signing Secrets Setup (Required)

The release workflow signs the `compote` binary with entitlements from `.github/entitlements/compote.entitlements`.

You must configure these repository secrets exactly:

- `MACOS_CERTIFICATE_P12`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_KEYCHAIN_PASSWORD`
- `MACOS_SIGNING_IDENTITY`

### Step 1: Export a Developer ID Application certificate as `.p12`

1. Open **Keychain Access** on your Mac.
2. In the **login** keychain, locate your **Developer ID Application** certificate.
3. Right-click it and choose **Export**.
4. Save as `compote-signing.p12`.
5. Set a strong export password and remember it.

### Step 2: Convert the `.p12` file to a one-line base64 value

```bash
base64 < compote-signing.p12 | tr -d '\n' > compote-signing.p12.base64
```

Use the full contents of `compote-signing.p12.base64` as the value for `MACOS_CERTIFICATE_P12`.

### Step 3: Get your signing identity string

Run:

```bash
security find-identity -v -p codesigning
```

Copy the full identity name, for example:

```text
Developer ID Application: Your Name (TEAMID)
```

Use that exact string as `MACOS_SIGNING_IDENTITY`.

### Step 4: Create repository secrets in GitHub

1. Open the repo on GitHub.
2. Go to **Settings** → **Secrets and variables** → **Actions**.
3. Click **New repository secret** for each secret below:
   - Name: `MACOS_CERTIFICATE_P12`
     Value: base64 output from Step 2
   - Name: `MACOS_CERTIFICATE_PASSWORD`
     Value: the `.p12` export password from Step 1
   - Name: `MACOS_KEYCHAIN_PASSWORD`
     Value: any strong random password (used only on the CI runner)
   - Name: `MACOS_SIGNING_IDENTITY`
     Value: exact identity string from Step 3

### Step 5: Verify signing after a release

After the workflow publishes a release archive, verify on macOS:

```bash
tar -xzf compote-vX.Y.Z-macos-arm64.tar.gz
codesign -d --entitlements :- ./compote
```

You should see:

- `com.apple.security.virtualization`
- `com.apple.vm.networking`

## Steps

### 1. Create a Git Tag

```bash
# Update version (if needed)
VERSION="0.1.0"

# Create and push tag
git tag -a "v${VERSION}" -m "Release v${VERSION}"
git push origin "v${VERSION}"
```

### 2. Automatic Release

The GitHub Actions workflow (`.github/workflows/release.yml`) will automatically:
1. Build the release binary
2. Sign the binary with required virtualization entitlements
3. Create a GitHub Release
4. Build and upload Homebrew bottle artifacts
5. Update the Homebrew formula (including bottle metadata)
6. Create a PR with the formula update

### 3. Merge Formula Update

1. Review the auto-generated PR
2. Merge it to update the formula

### 4. Announce

Users can now install with:
```bash
brew tap briannadoubt/tap
brew install compote
```

## Manual Release (if needed)

If the automated workflow fails:

### 1. Build Release Binary

```bash
swift build -c release
```

### 2. Create Archive

```bash
VERSION="0.1.0"
mkdir -p release
cp .build/release/compote release/
tar -czf "compote-v${VERSION}-macos-arm64.tar.gz" -C release compote
shasum -a 256 "compote-v${VERSION}-macos-arm64.tar.gz"
```

### 3. Create GitHub Release

1. Go to: https://github.com/briannadoubt/compote/releases/new
2. Choose the tag
3. Upload the `.tar.gz` file
4. Generate release notes
5. Publish

### 4. Update Formula

```bash
# Calculate SHA256
SHA256=$(shasum -a 256 compote-v${VERSION}-macos-arm64.tar.gz | awk '{print $1}')

# Update Formula/compote.rb:
# - url: https://github.com/briannadoubt/compote/archive/refs/tags/v${VERSION}.tar.gz
# - sha256: ${SHA256}
# - dependencies include: swift, xcode, socat

git add Formula/compote.rb
git commit -m "Update formula to v${VERSION}"
git push
```

## Version Numbering

We use [Semantic Versioning](https://semver.org/):

- **MAJOR**: Incompatible API changes
- **MINOR**: New functionality (backwards compatible)
- **PATCH**: Bug fixes (backwards compatible)

Examples:
- `0.1.0` - Initial release
- `0.2.0` - New features
- `0.2.1` - Bug fixes
- `1.0.0` - Production ready

## Checklist

Before releasing:

- [ ] All tests pass
- [ ] Documentation is updated
- [ ] README reflects current features
- [ ] `CHANGELOG.md` is updated
- [ ] Version is bumped
- [ ] No broken links in docs
- [ ] Formula dependencies are correct
- [ ] Installation tested on clean machine
- [ ] Bottle-only install verified (`brew install --force-bottle compote`)

After releasing:

- [ ] GitHub Release created
- [ ] Formula updated
- [ ] Installation verified: `brew install compote`
- [ ] Setup works: `compote setup`
- [ ] Basic functionality works: `compote up`
