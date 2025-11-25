#!/bin/bash
# SHAI Installation Script

set -e

INSTALL_DIR="${SHAI_INSTALL_DIR:-$HOME/.zsh/shai}"
REPO_URL="https://github.com/gevorggalstyan/shai.git"

echo "SHAI Installer"
echo "=============="
echo ""

# Check for ZSH
if ! command -v zsh &> /dev/null; then
    echo "Error: ZSH is required but not installed."
    exit 1
fi

# Check for dependencies
echo "Checking dependencies..."

if ! command -v jq &> /dev/null; then
    echo ""
    echo "Warning: jq is not installed."
    echo "Install it with:"
    echo "  macOS:  brew install jq"
    echo "  Debian: sudo apt install jq"
    echo "  Fedora: sudo dnf install jq"
    echo ""
fi

if ! command -v opencode &> /dev/null; then
    echo ""
    echo "Warning: opencode is not installed."
    echo "Install it with: npm install -g opencode-ai"
    echo ""
fi

# Create install directory
echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# If this script is run from the repo, copy files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/shai.zsh" ]]; then
    cp "$SCRIPT_DIR/shai.zsh" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/LICENSE" "$INSTALL_DIR/" 2>/dev/null || true
    cp "$SCRIPT_DIR/README.md" "$INSTALL_DIR/" 2>/dev/null || true
else
    # Clone from repo
    if command -v git &> /dev/null; then
        git clone "$REPO_URL" "$INSTALL_DIR"
    else
        echo "Error: git is required to clone the repository."
        echo "Please install git or download manually."
        exit 1
    fi
fi

echo ""
echo "Installation complete!"
echo ""
echo "Add this line to your ~/.zshrc:"
echo ""
echo "  source $INSTALL_DIR/shai.zsh"
echo ""
echo "Then reload your shell:"
echo ""
echo "  source ~/.zshrc"
echo ""
echo "Usage:"
echo "  Ctrl+]  - Toggle AI mode"
echo "  Ctrl+N  - Next model"
echo "  Ctrl+P  - Previous model"
echo "  Ctrl+X  - New conversation"
