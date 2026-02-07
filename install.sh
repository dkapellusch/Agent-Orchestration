#!/usr/bin/env bash
# install.sh - One-line installer for Agent Orchestration
# Usage: curl -fsSL https://raw.githubusercontent.com/dkapellusch/Agent-Orchestration/main/install.sh | bash
set -euo pipefail

REPO="https://github.com/dkapellusch/Agent-Orchestration.git"
INSTALL_DIR="${AO_INSTALL_DIR:-$HOME/agent-orchestration}"

info()  { printf "\033[0;34m%s\033[0m\n" "$*"; }
ok()    { printf "\033[0;32m%s\033[0m\n" "$*"; }
warn()  { printf "\033[0;33m%s\033[0m\n" "$*"; }
err()   { printf "\033[0;31m%s\033[0m\n" "$*" >&2; }

echo ""
info "Agent Orchestration Installer"
info "=============================="
echo ""

# --- Check dependencies ---
MISSING=()

if ! command -v git &>/dev/null; then
    MISSING+=("git")
fi

if ! command -v jq &>/dev/null; then
    MISSING+=("jq")
fi

BASH_VERSION_NUM="${BASH_VERSINFO[0]:-0}"
if [[ "$BASH_VERSION_NUM" -lt 4 ]]; then
    warn "bash 4.0+ required (found $BASH_VERSION). Install via: brew install bash"
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    err "Missing required dependencies: ${MISSING[*]}"
    echo ""
    if command -v brew &>/dev/null; then
        echo "  brew install ${MISSING[*]}"
    elif command -v apt-get &>/dev/null; then
        echo "  sudo apt-get install ${MISSING[*]}"
    else
        echo "  Install: ${MISSING[*]}"
    fi
    exit 1
fi

# --- Clone or update ---
if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Updating existing installation at $INSTALL_DIR..."
    git -C "$INSTALL_DIR" pull --ff-only origin main 2>/dev/null || {
        warn "Pull failed, continuing with existing version"
    }
else
    if [[ -d "$INSTALL_DIR" ]]; then
        err "$INSTALL_DIR already exists but is not a git repo"
        err "Remove it first: rm -rf $INSTALL_DIR"
        exit 1
    fi
    info "Cloning to $INSTALL_DIR..."
    git clone --depth 1 "$REPO" "$INSTALL_DIR"
fi

# --- Ensure scripts are executable ---
chmod +x "$INSTALL_DIR/ralph"
chmod +x "$INSTALL_DIR/tests.sh"
chmod +x "$INSTALL_DIR/gsd/gsd-runner" 2>/dev/null || true
chmod +x "$INSTALL_DIR/setup/ao.sh" 2>/dev/null || true

# --- Detect shell config ---
SHELL_NAME="$(basename "${SHELL:-/bin/bash}")"
case "$SHELL_NAME" in
    zsh)  RC_FILE="$HOME/.zshrc" ;;
    bash) RC_FILE="$HOME/.bashrc" ;;
    *)    RC_FILE="$HOME/.bashrc" ;;
esac

# --- Add to PATH and aliases ---
MARKER="# Agent Orchestration"

if grep -q "$MARKER" "$RC_FILE" 2>/dev/null; then
    ok "Shell config already set up in $RC_FILE"
else
    {
        echo ""
        echo "$MARKER"
        echo "export PATH=\"$INSTALL_DIR:\$PATH\""
        echo "alias ao='ralph loop'"
        echo "alias ao-models='ralph models'"
        echo "alias ao-cost='ralph cost'"
        echo "alias ao-stats='ralph stats'"
        echo "alias ao-agents='ralph agents'"
        echo "alias ao-cleanup='ralph cleanup'"
    } >> "$RC_FILE"
    ok "Added to $RC_FILE"
fi

# --- Check for optional deps ---
echo ""
info "Checking optional dependencies..."

if command -v opencode &>/dev/null; then
    ok "  opencode: installed"
else
    warn "  opencode: not found (install: npm install -g @anthropic-ai/opencode)"
fi

if command -v claude &>/dev/null; then
    ok "  claude:   installed"
else
    warn "  claude:   not found (install: brew install --cask claude-code)"
fi

if command -v docker &>/dev/null; then
    ok "  docker:   installed"
else
    warn "  docker:   not found (optional, for sandbox mode)"
fi

if command -v flock &>/dev/null; then
    ok "  flock:    installed"
else
    warn "  flock:    not found (optional, install: brew install flock)"
fi

# --- Done ---
echo ""
ok "=============================="
ok "Installation complete!"
ok "=============================="
echo ""
echo "Next steps:"
echo ""
echo "  1. Restart your terminal or run:"
echo "     source $RC_FILE"
echo ""
echo "  2. Authenticate (pick one or both):"
echo "     opencode auth login    # For OpenCode agent"
echo "     claude                 # For Claude Code agent"
echo ""
echo "  3. Start using it:"
echo "     ao \"Fix all lint errors\" --max 10"
echo "     ao \"Refactor auth\" --agent cc --tier high"
echo "     ralph --help"
echo ""
