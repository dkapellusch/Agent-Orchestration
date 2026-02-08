#!/usr/bin/env bash
# setup-sandbox - Set up sandboxed agent execution with opencode
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_ROOT="$(dirname "$SCRIPT_DIR")"
SANDBOX_DIR="$SCRIPT_DIR/contai"
CONTAI_REPO="https://github.com/frequenz-floss/contai.git"
OPENCODE_AUTH_DIR="$HOME/.local/share/opencode"
WRAPPERS_DIR="$RALPH_ROOT/wrappers"

echo "Agent Orchestrator - Sandbox Setup"
echo "==================================="
echo ""

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is required but not installed."
    echo "Please install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo "Error: Docker is not running."
    echo "Please start Docker and try again."
    exit 1
fi

# Check for opencode auth
if [[ ! -f "$OPENCODE_AUTH_DIR/auth.json" ]]; then
    echo "Warning: No OpenCode authentication found."
    echo ""
    echo "You need to authenticate with OpenCode first:"
    echo "  opencode auth login"
    echo ""
    echo "This will set up OAuth tokens for Google, Anthropic, etc."
    echo "The container will use these tokens (mounted read-only)."
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Clone or update contai
if [[ -d "$SANDBOX_DIR" ]]; then
    echo "Updating existing contai installation..."
    cd "$SANDBOX_DIR"
    git pull
else
    echo "Cloning contai repository..."
    git clone "$CONTAI_REPO" "$SANDBOX_DIR"
    cd "$SANDBOX_DIR"
fi

echo ""
echo "Building contai base image..."
./build.sh

echo ""
echo "Building custom opencode image..."
cd "$SCRIPT_DIR"

# Build custom image with opencode and plugins
docker build \
    --build-arg BASE_IMAGE=contai:latest \
    -t agent-sandbox:latest \
    -f Dockerfile.opencode \
    .

echo ""
echo "Setup complete!"
echo ""
echo "OpenCode auth directory: $OPENCODE_AUTH_DIR"
echo "Contai installation: $SANDBOX_DIR"
echo "Custom image: agent-sandbox:latest"
echo "Wrapper script: $WRAPPERS_DIR/agent-sandbox"
echo ""
echo "Usage:"
echo "  ralph loop \"Your prompt\" --sandbox docker --dir /path/to/project"
echo ""
if [[ -f "$OPENCODE_AUTH_DIR/auth.json" ]]; then
    echo "OpenCode auth status:"
    opencode auth status 2>/dev/null || echo "  (run 'opencode auth status' to check)"
else
    echo "Next step: Run 'opencode auth login' to authenticate"
fi
