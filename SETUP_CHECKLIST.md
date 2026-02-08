# Compote Setup Checklist

This checklist will help you publish Compote with Homebrew support.

## ✅ What's Already Done

The following files have been created for you:

- ✅ `Formula/compote.rb` - Homebrew formula
- ✅ `.github/workflows/release.yml` - Automated releases
- ✅ `.github/workflows/test.yml` - CI testing
- ✅ `README.md` - Updated with Homebrew installation instructions
- ✅ `RELEASE.md` - Release process documentation
- ✅ `HOMEBREW_TAP.md` - Guide to setting up a Homebrew tap
- ✅ `scripts/test-formula.sh` - Local formula testing script
- ✅ `.github/ISSUE_TEMPLATE/bug_report.md` - Bug report template

## 📝 What You Need to Do

### 1. Update Placeholders (Only if Forking)

If you are publishing under a different account, replace `briannadoubt` with your GitHub username in these files:

```bash
# Use your editor or run:
find . -type f \( -name "*.rb" -o -name "*.md" -o -name "*.yml" \) -exec sed -i '' 's/briannadoubt/your-github-username/g' {} +
```

Files with placeholders:
- `Formula/compote.rb`
- `README.md`
- `.github/workflows/release.yml`
- `RELEASE.md`
- `HOMEBREW_TAP.md`

### 2. Set Up GitHub Repository

```bash
# Initialize git if not already done
git init
git add .
git commit -m "Initial commit"

# Create repo on GitHub, then:
git remote add origin https://github.com/briannadoubt/compote.git
git branch -M main
git push -u origin main
```

### 3. Create Homebrew Tap Repository

Option A: **Separate Tap Repository (Recommended)**

```bash
# On GitHub, create: https://github.com/briannadoubt/homebrew-compote
git clone https://github.com/briannadoubt/homebrew-compote.git
cd homebrew-compote

# Create Formula directory
mkdir -p Formula

# Copy formula
cp /path/to/compote/Formula/compote.rb Formula/

# Commit and push
git add Formula/compote.rb
git commit -m "Add compote formula"
git push origin main
```

Option B: **In-Repo Formula**
- Keep formula in main repo
- Users install with full URL (less convenient)

### 4. Test Locally

```bash
# Test the formula
./scripts/test-formula.sh

# Or manually:
brew install --build-from-source ./Formula/compote.rb
compote setup
brew uninstall compote

# Confirm dependencies expected by runtime paths are present
brew list socat >/dev/null
```

### 5. Create First Release

```bash
# Update changelog and docs first
git add CHANGELOG.md README.md RELEASE.md SETUP_CHECKLIST.md HOMEBREW_TAP.md
git commit -m "docs: prepare release notes and checklists"

# Make sure everything is committed
git add .
git commit -m "Prepare for v0.1.0 release"
git push

# Create and push tag
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

The GitHub Actions workflow will automatically:
1. Build the release
2. Create GitHub Release
3. Upload artifacts
4. Update formula

### 6. Verify Installation

After the release is published:

```bash
# If using separate tap:
brew tap briannadoubt/tap
brew install compote

# Verify
compote --version
compote setup
```

## 📚 Documentation

- **For users**: `README.md` has installation instructions
- **For contributors**: `RELEASE.md` has release process
- **For maintainers**: `HOMEBREW_TAP.md` has tap management guide

## 🔧 Maintenance

### Regular Tasks

1. **Update formula** on each release (automated)
2. **Test installation** before releasing
3. **Monitor issues** for installation problems
4. **Keep dependencies** up to date

### When containerization Updates

If Apple updates the containerization framework:

```bash
# Update dependency in Formula/compote.rb if needed
depends_on "containerization@2" => "2.0"  # if they version it

# Test
brew reinstall compote
compote setup
```

## 🚀 Next Steps

1. [ ] Replace all `briannadoubt` placeholders
2. [ ] Push to GitHub
3. [ ] Create homebrew-compote tap repo (optional but recommended)
4. [ ] Create v0.1.0 release
5. [ ] Test installation via Homebrew
6. [ ] Share with users!

## 💡 Tips

- **Start with v0.1.0**: Semantic versioning from the beginning
- **Test thoroughly**: Use `scripts/test-formula.sh`
- **Document changes**: Keep README and CHANGELOG updated
- **Automate everything**: Let GitHub Actions handle releases
- **Get feedback**: Users via GitHub Issues

## 🆘 Need Help?

- Formula not working? Run: `brew audit --strict Formula/compote.rb`
- Build failing? Check: `.github/workflows/release.yml`
- Installation issues? Check: `compote setup --verbose`

See `HOMEBREW_TAP.md` for detailed troubleshooting.
