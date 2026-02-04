# Release Process

This document describes how to create a new release of Compote.

## Prerequisites

1. Ensure all changes are committed and pushed
2. All tests pass: `swift test`
3. Version is bumped in appropriate places
4. CHANGELOG is updated

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
2. Create a GitHub Release
3. Upload release artifacts
4. Update the Homebrew formula
5. Create a PR with the formula update

### 3. Merge Formula Update

1. Review the auto-generated PR
2. Merge it to update the formula

### 4. Announce

Users can now install with:
```bash
brew tap OWNER/compote
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

1. Go to: https://github.com/OWNER/compote/releases/new
2. Choose the tag
3. Upload the `.tar.gz` file
4. Generate release notes
5. Publish

### 4. Update Formula

```bash
# Calculate SHA256
SHA256=$(shasum -a 256 compote-v${VERSION}-macos-arm64.tar.gz | awk '{print $1}')

# Update Formula/compote.rb:
# - url: https://github.com/OWNER/compote/archive/refs/tags/v${VERSION}.tar.gz
# - sha256: ${SHA256}

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
- [ ] CHANGELOG is updated
- [ ] Version is bumped
- [ ] No broken links in docs
- [ ] Formula dependencies are correct
- [ ] Installation tested on clean machine

After releasing:

- [ ] GitHub Release created
- [ ] Formula updated
- [ ] Installation verified: `brew install compote`
- [ ] Setup works: `compote setup`
- [ ] Basic functionality works: `compote up`
