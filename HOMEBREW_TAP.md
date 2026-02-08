# Setting Up a Homebrew Tap

This guide explains how to create and publish a Homebrew tap for Compote.

## What is a Tap?

A Homebrew "tap" is a third-party repository of formulae. It allows users to install your software with:
```bash
brew tap briannadoubt/tap
brew install compote
```

## Option 1: Quick Start (Recommended)

### 1. Create a Tap Repository

Create a new GitHub repository named `homebrew-compote`:
```bash
# On GitHub, create: https://github.com/briannadoubt/homebrew-compote
```

**Important**: The repository name MUST start with `homebrew-`.

### 2. Copy Formula

```bash
# Clone your new tap repo
git clone https://github.com/briannadoubt/homebrew-compote.git
cd homebrew-compote

# Copy formula from main repo
cp /path/to/compote/Formula/compote.rb ./Formula/compote.rb

# Update briannadoubt placeholder
sed -i '' 's/briannadoubt/your-github-username/g' Formula/compote.rb

# Commit and push
git add Formula/compote.rb
git commit -m "Add compote formula"
git push origin main
```

### 3. Users Can Now Install

```bash
brew tap briannadoubt/tap
brew install compote
```

## Option 2: In-Repo Formula (Alternative)

You can keep the formula in the main Compote repository. Users install with:

```bash
brew install --build-from-source \
  https://raw.githubusercontent.com/briannadoubt/compote/main/Formula/compote.rb
```

This is simpler but:
- Less discoverable
- Requires `--build-from-source` flag
- No automatic updates via `brew upgrade`

## Maintaining the Formula

### When Releasing a New Version

The GitHub Actions workflow automatically:
1. Calculates new SHA256
2. Updates the formula
3. Creates a PR

Or manually:

```bash
# Get the SHA256 of your release tarball
curl -L https://github.com/briannadoubt/compote/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256

# Update Formula/compote.rb with:
# - New version in url
# - New sha256

# Test locally
./scripts/test-formula.sh

# Commit and push
git add Formula/compote.rb
git commit -m "Update to v0.1.0"
git push
```

## Submitting to Homebrew Core (Optional)

For wider distribution, submit to the official Homebrew repository:

### Requirements

1. **Stable releases**: At least 30 days of history
2. **GitHub stars**: Some minimum threshold
3. **Active maintenance**: Regular updates
4. **Good documentation**: README, LICENSE
5. **Working formula**: Passes all brew audit checks

### Process

```bash
# Fork https://github.com/Homebrew/homebrew-core

# Add your formula
cp Formula/compote.rb homebrew-core/Formula/c/compote.rb

# Test thoroughly
brew test-bot compote

# Create PR
# Follow: https://docs.brew.sh/How-To-Open-a-Homebrew-Pull-Request
```

## Testing Your Tap

### Local Testing

```bash
# Test formula + install from an ephemeral local tap
./scripts/test-formula.sh

# Verify
compote setup
```

### Test from Tap

```bash
# Remove local installation
brew uninstall compote

# Install from tap
brew tap briannadoubt/tap
brew install compote

# Verify
compote --version
compote setup
```

## CI/CD Integration

The `.github/workflows/release.yml` file automatically:

1. **On tag push**: Creates GitHub release
2. **Builds binary**: For macOS ARM64
3. **Updates formula**: With new version and SHA
4. **Creates PR**: In tap repository (if separate)

## Troubleshooting

### Formula Audit Failures

```bash
# Check what's wrong
brew audit --strict --online Formula/compote.rb

# Common issues:
# - Missing license
# - Incorrect SHA256
# - Dependency problems
# - URL not accessible
```

### Installation Failures

```bash
# Try verbose mode
brew install --build-from-source --verbose Formula/compote.rb

# Check logs
cat ~/Library/Logs/Homebrew/compote/
```

### Dependency Issues

```bash
# Ensure containerization is in a tap or core
brew search containerization
brew search socat

# If not available, users need to install dependencies first
brew tap apple/containerization
brew install containerization socat
```

## Best Practices

1. **Test before releasing**: Always test formula locally
2. **Use semantic versioning**: v0.1.0, v0.2.0, etc.
3. **Keep formula updated**: Automated via GitHub Actions
4. **Document dependencies**: In formula caveats (`containerization`, `socat`)
5. **Provide test block**: Verify installation works

## Resources

- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [Homebrew Acceptable Formulae](https://docs.brew.sh/Acceptable-Formulae)
- [Creating Taps](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
