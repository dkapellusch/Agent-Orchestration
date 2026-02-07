# Installation Guide

This guide covers setting up the Agent Orchestration toolkit as a standalone installation.

## Prerequisites

### Required
- **Bash 4.0+** - Modern bash features required
  ```bash
  bash --version  # Should show 4.0+
  ```
- **jq** - JSON processing
  ```bash
  brew install jq  # macOS
  apt install jq   # Linux
  ```
- **OpenCode CLI** - AI coding assistant
  ```bash
  # Install via npm
  npm install -g @anthropic-ai/opencode

  # Or via brew (if available)
  brew install opencode
  ```

### Optional
- **Claude Code CLI** - Alternative to OpenCode for Claude-native execution
- **Docker** - For sandboxed execution
- **Node.js 18+** - For Anthropic sandbox runtime
- **flock** - For file locking (included in util-linux on Linux, install via `brew install flock` on macOS)

## Installation

### Quick Install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/dkapellusch/Agent-Orchestration/main/install.sh | bash
```

This handles cloning, PATH setup, aliases, and dependency checks. Restart your terminal after running.

To customize the install location: `AO_INSTALL_DIR=~/my-dir curl -fsSL ... | bash`

### Manual Install

#### 1. Clone the Repository

```bash
git clone https://github.com/dkapellusch/Agent-Orchestration.git ~/agent-orchestration
cd ~/agent-orchestration
```

### 2. Add to PATH

Add to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
export PATH="$HOME/agent-orchestration:$PATH"
```

Then reload:
```bash
source ~/.bashrc  # or ~/.zshrc
```

### 3. Authenticate OpenCode

```bash
opencode auth login
```

This opens a browser for OAuth authentication. Your credentials are stored in `~/.opencode/`.

### 4. Install Aliases (Recommended)

```bash
./setup/ao.sh
```

This adds convenient aliases like `ao` (for `ralph loop`) to your shell config.

### 5. Verify Installation

```bash
# Check available models
ralph models

# Show help
ao --help

# List shared agents
ralph agents list

# Test a simple task
ao "Say hello" --agent cc --tier low --max 1
```

## Optional Setup

### Docker Sandbox

For isolated execution in containers:

```bash
# Build the container image
./setup/contai.sh

# Test container execution
./wrappers/contai-opencode --help
```

### Anthropic Sandbox Runtime

For lightweight sandboxing without Docker:

```bash
npm install -g @anthropic-ai/sandbox-runtime
```

Then use `--sandbox anthropic` flag:
```bash
ao "Your task" --dir /path/to/project --sandbox anthropic
```

## Configuration

### config/models.json

Main configuration for models, tiers, and concurrency:

```json
{
  "agents": {
    "opencode": {
      "tiers": {
        "high": {
          "models": ["google/gemini-3-pro-preview", "anthropic/claude-opus-4-5"],
          "description": "Complex reasoning tasks"
        },
        "medium": {
          "models": ["google/gemini-3-flash-preview", "anthropic/claude-sonnet-4-5"],
          "description": "Standard coding tasks"
        },
        "low": {
          "models": ["google/gemini-3-flash-preview", "anthropic/claude-haiku-4-5"],
          "description": "Simple/quick tasks"
        }
      }
    }
  },
  "defaults": {
    "maxRetries": 10,
    "retryDelaySeconds": 300,
    "cooldownSeconds": 900
  },
  "concurrency": {
    "defaultMaxSlots": 3,
    "modelLimits": {
      "anthropic/claude-opus-4-5": 2
    }
  }
}
```

### config/sandbox.json

Allowlists for Anthropic sandbox execution:

```json
{
  "network": {
    "allowedDomains": [
      "api.anthropic.com",
      "github.com",
      "*.github.com",
      "registry.npmjs.org"
    ]
  },
  "filesystem": {
    "denyRead": ["~/.ssh", "~/.aws"],
    "allowWrite": [".", "./**", "/tmp", "/tmp/**"]
  }
}
```

## Directory Structure After Installation

```
~/agent-orchestration/
├── ralph                   # Main dispatcher
├── cmd/                    # Subcommand implementations
│   ├── loop.sh             # Iterative loop with sandbox + budgets
│   ├── models.sh           # List models
│   ├── cost.sh             # Cost reporting
│   ├── stats.sh            # Session statistics
│   ├── cleanup.sh          # Clean old sessions
│   └── agents.sh           # Agent management
├── lib/                    # Core libraries
│   ├── common.sh           # Entry point (sources all libs)
│   ├── core.sh             # Locking, JSON utilities
│   ├── model.sh            # Model selection, rate limiting
│   ├── agent.sh            # Agent execution
│   ├── agents.sh           # Agent sync & management
│   ├── sandbox.sh          # Sandbox execution
│   ├── cost.sh             # Cost tracking
│   └── stream-formatter.sh # Claude Code stream output formatter
├── config/                 # Configuration
│   ├── models.json         # Model tiers and settings
│   └── sandbox.json        # Sandbox allowlists
├── wrappers/               # CLI wrappers
├── setup/                  # Setup scripts
│   ├── ao.sh               # Alias installation
│   └── contai.sh           # Docker sandbox setup
├── gsd/                    # GSD integration
├── agents/                 # Shared agent definitions
└── specs/                  # Design documentation
```

## Runtime Directories (Created Automatically)

These directories are created on first use:

- `.ralph/` - Session state and history (in working directory)
- `state/` - Rate limit tracking, queue, history

## Troubleshooting

### "command not found: opencode"

Ensure OpenCode is installed and in your PATH:
```bash
which opencode
npm install -g @anthropic-ai/opencode
```

### "flock: command not found"

Install flock for file locking:
```bash
# macOS
brew install flock

# Linux (usually pre-installed)
apt install util-linux
```

### Rate Limit Errors

The orchestrator handles rate limits automatically with exponential backoff. If you see persistent errors:

1. Check your API quota
2. Reduce concurrency in `config/models.json`
3. Use a lower tier model

### Permission Denied

Make the main script executable:
```bash
chmod +x ralph
```

## Quick Start

After installation, try:

```bash
# Simple task with iterative refinement (using ao alias)
ao "Fix the bug in auth.js" --dir /path/to/project

# With sandbox isolation
ao "Refactor the API" --dir /path/to/project --sandbox anthropic

# Use Claude Code instead of OpenCode (shows thinking + tool uses)
ao "Add tests" --dir /path/to/project --agent cc

# GSD mode for structured workflow
ao -m gsd new --dir /path/to/project
ao -m gsd plan 1 --dir /path/to/project
ao -m gsd execute 1 --dir /path/to/project
```

See [README.md](README.md) for comprehensive usage documentation.
