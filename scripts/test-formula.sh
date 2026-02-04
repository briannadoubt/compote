#!/bin/bash
set -e

# Test the Homebrew formula locally
#
# Usage:
#   ./scripts/test-formula.sh

echo "🧪 Testing Compote Homebrew formula..."

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

echo "📋 Checking formula syntax..."
brew audit --strict --online Formula/compote.rb || echo "⚠️  Audit warnings (can be ignored for local testing)"

echo ""
echo "🔨 Testing installation from local formula..."
brew install --build-from-source ./Formula/compote.rb

echo ""
echo "✅ Testing installed binary..."
compote --version
compote setup

echo ""
echo "🎉 Formula test complete!"
echo ""
echo "To uninstall:"
echo "  brew uninstall compote"
