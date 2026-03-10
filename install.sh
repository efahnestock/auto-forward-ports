#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Installing auto-forward-ports"
echo ""

# Determine script directory (works for git clone installs)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If files aren't local (curl | bash install), download them
if [[ ! -f "$SCRIPT_DIR/auto-forward-ports.zsh" && ! -f "$SCRIPT_DIR/auto-forward-ports.bash" ]]; then
    echo "Downloading auto-forward-ports..."
    TMPDIR=$(mktemp -d)
    REPO_URL="https://raw.githubusercontent.com/efahnestock/auto-forward-ports/main"
    curl -fsSL "$REPO_URL/auto-forward-ports.zsh" -o "$TMPDIR/auto-forward-ports.zsh"
    curl -fsSL "$REPO_URL/auto-forward-ports.bash" -o "$TMPDIR/auto-forward-ports.bash"
    SCRIPT_DIR="$TMPDIR"
fi

# Create ~/.local/bin if it doesn't exist
mkdir -p "$HOME/.local/bin"

# Detect shell and install the matching version
SHELL_NAME=$(basename "$SHELL")
case "$SHELL_NAME" in
    zsh)
        SOURCE_FILE="$SCRIPT_DIR/auto-forward-ports.zsh"
        ;;
    bash)
        SOURCE_FILE="$SCRIPT_DIR/auto-forward-ports.bash"
        ;;
    *)
        # Fallback: prefer bash if available, else zsh
        if command -v bash &>/dev/null; then
            SOURCE_FILE="$SCRIPT_DIR/auto-forward-ports.bash"
            echo -e "${YELLOW}⚠${NC} Unknown shell: $SHELL_NAME, defaulting to bash version"
        elif command -v zsh &>/dev/null; then
            SOURCE_FILE="$SCRIPT_DIR/auto-forward-ports.zsh"
            echo -e "${YELLOW}⚠${NC} Unknown shell: $SHELL_NAME, defaulting to zsh version"
        else
            echo -e "${RED}✗${NC} Could not find bash or zsh on this system"
            exit 1
        fi
        ;;
esac

if [[ ! -f "$SOURCE_FILE" ]]; then
    echo -e "${RED}✗${NC} Source file not found: $SOURCE_FILE"
    exit 1
fi

cp "$SOURCE_FILE" "$HOME/.local/bin/auto-forward-ports"
chmod +x "$HOME/.local/bin/auto-forward-ports"
echo -e "${GREEN}✓${NC} Installed auto-forward-ports to ~/.local/bin/auto-forward-ports ($(basename "$SOURCE_FILE" | sed 's/auto-forward-ports\.//' ) version)"

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo ""
    echo -e "${YELLOW}⚠${NC} ~/.local/bin is not in your PATH"
    RC_FILE="$HOME/.${SHELL_NAME}rc"
    echo "  Add this line to your $RC_FILE:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Usage:"
echo "  auto-forward-ports <host> [poll_interval]"
echo ""
echo "Example:"
echo "  auto-forward-ports myserver 10"
