#!/bin/bash
set -euo pipefail

# Verify Homebrew installs compote using a prebuilt bottle (no source build).
#
# Usage:
#   ./scripts/test-bottle-install.sh [tap/formula]
# Example:
#   ./scripts/test-bottle-install.sh briannadoubt/tap/compote

FORMULA_REF="${1:-briannadoubt/tap/compote}"
export HOMEBREW_NO_AUTO_UPDATE=1

if ! command -v brew >/dev/null 2>&1; then
    echo "❌ Error: Homebrew is not installed"
    echo "Install from: https://brew.sh"
    exit 1
fi

echo "🧪 Testing bottle-only install for ${FORMULA_REF}"
brew install --force-bottle "${FORMULA_REF}"

echo "✅ Testing installed binary..."
compote --version
compote setup || echo "⚠️  Setup check reported issues (this can happen on CI/dev machines)"

echo "🎉 Bottle install test complete!"
