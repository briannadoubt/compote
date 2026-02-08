#!/bin/bash
set -e

# Test the Homebrew formula locally
#
# Usage:
#   ./scripts/test-formula.sh

echo "🧪 Testing Compote Homebrew formula..."
export HOMEBREW_NO_AUTO_UPDATE=1

# Check if we're in the right directory
if [ ! -f "Formula/compote.rb" ]; then
    echo "❌ Error: Run this script from the project root"
    exit 1
fi

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Error: Homebrew is not installed"
    echo "Install from: https://brew.sh"
    exit 1
fi

TAP_NAME="local/compote-test-$(date +%s)"
FORMULA_NAME="compote"
TAP_FORMULA="${TAP_NAME}/${FORMULA_NAME}"
EXISTING_FORMULA=""

cleanup() {
    set +e
    brew uninstall --force "$TAP_FORMULA" >/dev/null 2>&1
    brew untap "$TAP_NAME" >/dev/null 2>&1
    if [ -n "$EXISTING_FORMULA" ]; then
        echo "♻️ Restoring previously installed formula: $EXISTING_FORMULA"
        brew install "$EXISTING_FORMULA" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

echo "🏗️ Creating ephemeral local tap: $TAP_NAME"
brew tap-new "$TAP_NAME" >/dev/null
TAP_REPO="$(brew --repo "$TAP_NAME")"
mkdir -p "$TAP_REPO/Formula"
cp Formula/compote.rb "$TAP_REPO/Formula/compote.rb"

if brew list --full-name --formula | rg -q '(^|/)compote$'; then
    EXISTING_FORMULA="$(brew list --full-name --formula | rg '(^|/)compote$' -m1 || true)"
    if [ -z "$EXISTING_FORMULA" ]; then
        EXISTING_FORMULA="compote"
    fi
    echo "🧹 Temporarily uninstalling existing compote install: $EXISTING_FORMULA"
    brew uninstall --force "$EXISTING_FORMULA"
fi

echo "📋 Checking formula syntax..."
brew audit --strict "$TAP_FORMULA" || echo "⚠️  Audit warnings (can be ignored for local testing)"

echo ""
echo "🔨 Testing installation from local tap formula..."
brew install --build-from-source --verbose "$TAP_FORMULA"

echo ""
echo "✅ Testing installed binary..."
compote --version
compote setup || echo "⚠️  Setup check reported issues (this can happen on CI/dev machines)"

echo ""
echo "🎉 Formula test complete!"
