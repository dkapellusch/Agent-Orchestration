# Agent Orchestration

Robust AI agent orchestration with iterative refinement, automatic rate limiting, and parallel execution.

**What it does**: Runs AI coding agents (Claude, Gemini, GPT, etc.) on your codebase with automatic retry logic, model fallbacks, struggle detection, and cost tracking.

**Why use this**: Production-grade reliability for agentic workflows—handles rate limits, detects when agents are stuck, manages concurrent tasks, and prevents cost overruns.

## Quick Start

### Install

```bash
git clone https://github.com/dkapellusch/Agent-Orchestration.git ~/agent-orchestration
export PATH="$HOME/agent-orchestration:$PATH"  # Add to ~/.zshrc or ~/.bashrc
opencode auth login  # One-time OAuth setup
```

See [INSTALLATION.md](INSTALLATION.md) for detailed setup.

### Basic Usage

```bash
cd ~/my-project

# Simple task - let it run until done
ao "Fix all lint errors"

# Cap iterations and set a budget
ao "Fix all lint errors" --max 10 --budget 2.00

# Use Claude Code instead of OpenCode
ao "Fix all lint errors" --agent cc
```

### Examples

```bash
# Thorough codebase cleanup: Claude Code, at least 5 iterations, fresh context
# every iteration, up to 20 attempts, isolated in Docker
ao "Address all issues found in this repo" \
  --agent cc --min 5 --reset 1 --max 20 --sandbox docker

# Quick bug fix with cost guard: medium tier, small budget, stop fast
ao "Fix the null pointer in src/auth/login.ts" \
  --tier medium --max 5 --budget 1.00

# Large feature with a spec file: high tier models, generous budget,
# validate completion with a second agent pass
ao --file feature-spec.md \
  --tier high --max 30 --budget 10.00 --completion-mode validate

# Overnight refactor: infinite iterations, reset context every 3 loops,
# sandboxed, high budget ceiling
ao "Refactor all database queries to use the new ORM" \
  --max 0 --reset 3 --budget 25.00 --sandbox anthropic

# Fast lint/format pass: low tier (cheap/fast), few iterations, no sandbox
ao "Run eslint --fix and prettier on all source files" \
  --tier low --max 3 --sandbox none

# Resume a previous session that was interrupted
ao --session swift-fox-runs

# Inject context into a running session from another terminal
ao --add-context "Focus on the edge case where user.email is null" \
  --session swift-fox-runs

# Target a specific model instead of a tier
ao "Optimize the hot path in src/engine.ts" \
  --model anthropic/claude-opus-4-5 --max 10

# Mount extra write paths when sandboxed
ao "Generate API docs into ~/docs" \
  --sandbox anthropic --allow-write ~/docs

# Pass MCP server config for tool access
ao "Query the database and fix schema drift" \
  --mcp-config ./mcp-servers.json --tier high
```

### Execution Modes

The `ao` command (alias for `ralph loop`) supports two modes via `--mode` or `-m`:

```bash
# Loop mode (default) - iterative until completion
ao "Fix all bugs" --max 10

# GSD mode - structured workflow with short commands
ao -m gsd new                    # Start new project
ao -m gsd plan 1                 # Plan phase 1
ao -m gsd execute 1 --tier high  # Execute phase 1
ao -m gsd verify 1               # Verify results
```

### Working Directory

Scripts work from the current directory by default, or use `--dir` to specify a path:

```bash
# Pattern 1: cd to project (recommended for interactive use)
cd ~/my-project
ao "Fix the bug"

# Pattern 2: specify --dir (useful for scripts/automation)
ao "Fix the bug" --dir ~/my-project

# Pattern 3: run multiple projects from anywhere
ao "Add tests" --dir ~/project-a &
ao "Fix lint" --dir ~/project-b &
wait
```

### Optional: Convenient Aliases

**Quick setup** (recommended):
```bash
./setup/ao.sh
```

This script automatically adds aliases to your shell config. Or add them manually to `~/.zshrc` or `~/.bashrc`:

```bash
# Agent Orchestration aliases
export PATH="$HOME/agent-orchestration:$PATH"

alias ao='ralph loop'
alias ao-models='ralph models'
alias ao-cost='ralph cost'
alias ao-stats='ralph stats'
alias ao-agents='ralph agents'
alias ao-cleanup='ralph cleanup'
alias ao-gsd='gsd/gsd-runner'

# Quick shortcuts
alias ao-list='ralph loop --list'
alias ao-help='ralph --help'
```

Then use:
```bash
ao "Fix the bug" --budget 5.00
ao "Add tests" --tier medium
ao-cost --days 7
ao-models
```

## Core Concepts

### 1. Ralph Loop - Iterative Refinement

Runs the agent repeatedly until task completion, with automatic struggle detection:

```bash
# Create task specification
cat > task.md << 'EOF'
Implement user authentication:
1. Create User model with email/password
2. Add POST /api/auth/register endpoint
3. Add POST /api/auth/login with JWT
4. Write tests for all endpoints

Mark complete when all tests pass: <promise>COMPLETE</promise>
EOF

# Run until complete (auto-detects struggles, retries with better models)
ralph loop --file task.md --tier high --dir ~/project
```

**Features**:
- **Unique sessions** - Each loop gets an ID (e.g., `swift-fox-runs`) for concurrent execution
- **Struggle detection** - Identifies when agent is stuck (repeated errors, no file changes, short iterations)
- **Auto-escalation** - Falls back to better models when struggling
- **Progress tracking** - Saves iteration history, file changes, and summaries
- **Context injection** - Add context mid-loop: `ralph loop --add-context "Focus on edge cases" --session swift-fox-runs`

### 2. Rate Limiting & Model Fallbacks

Automatically handles rate limits across all model providers:

```bash
# Check model status
ralph models

# Tier fallback: high → medium → low
ralph loop "Task" --tier high  # Will try all tiers if rate-limited
```

**How it works**:
- Detects rate limit errors (429, quota messages)
- Marks model as rate-limited with cooldown period
- Falls back to next available model in same tier
- Falls back to lower tier if all models in tier are limited
- Tracks per-model concurrency limits

### 3. Cost Tracking & Budget Enforcement

Real-time cost tracking with automatic budget stops:

```bash
# Set $5 budget (stops at 100%, warns at 80%)
ralph loop "Task" --budget 5.00 --tier high --dir ~/project

# View costs
ralph cost                           # Overall stats
ralph cost --days 7 --models         # Last 7 days by model
ralph cost session swift-fox-runs    # Specific session breakdown
```

**Per-iteration cost display**:
```
Iteration Summary
────────────────────────────────────────────────────────────────────
Duration:   2m 15s
Exit code:  0
Files:      3 modified
Tokens: 12,543 in, 3,421 out | cache: 24,502 read, 0 write
Cost: $0.35 (iter) | $0.89 (total) | 89% of $1.00 used ⚠️
```

### 4. Sandboxed Execution

Isolate agent execution from your host system:

```bash
# Auto-detect best sandbox (anthropic > docker > none)
ralph loop "Task" --sandbox auto --dir ~/project

# Anthropic sandbox (recommended - lightweight, secure)
ralph loop "Task" --sandbox anthropic --dir ~/project

# Docker sandbox (heavy isolation)
./setup/contai.sh  # One-time setup
ralph loop "Task" --sandbox docker --dir ~/project

# Grant additional write paths
ralph loop "Task" --sandbox anthropic --allow-write ~/data --dir ~/project
```

### 5. Shared Agents

Centralized agent definitions available across all contexts:

| Agent | Purpose |
|-------|---------|
| `yolo` | Full autonomous execution without prompts |
| `explorer` | Read-only codebase exploration |
| `reviewer` | Code review without modifications |
| `fixer` | Fix lint/type/test errors |
| `planner` | Implementation planning |

```bash
ralph agents list                  # List all agents
ralph agents show yolo             # Show agent details
ralph agents validate              # Validate definitions
ralph agents sync --dir ~/project  # Sync to project
```

**Auto-sync**: All orchestrators (`ralph loop`, `gsd-runner`, `contai-opencode`) automatically sync agents before execution.

### 6. GSD (Get Shit Done) - Spec-Driven Development

Phase-based development with parallel task execution:

```bash
# Using ao with GSD mode (recommended)
ao -m gsd new                        # Create project spec
ao -m gsd plan 1                     # Plan first phase
ao -m gsd execute 1 --tier high      # Execute tasks in parallel
ao -m gsd verify 1                   # Verify results

# Or use gsd-runner directly
./gsd/gsd-runner /gsd:new-project
./gsd/gsd-runner /gsd:plan-phase 1
./gsd/gsd-runner /gsd:execute-phase 1
```

**GSD Short Commands** (via `ao -m gsd`):
| Command | Full Form | Description |
|---------|-----------|-------------|
| `new` | `/gsd:new-project` | Start new project |
| `map` | `/gsd:map-codebase` | Analyze existing code |
| `plan N` | `/gsd:plan-phase N` | Plan phase N |
| `execute N` | `/gsd:execute-phase N` | Execute phase N |
| `verify N` | `/gsd:verify-work N` | Verify phase N |
| `quick` | `/gsd:quick` | Ad-hoc task |
| `debug` | `/gsd:debug` | Systematic debugging |

**Benefits**: Context-efficient parallel execution, automatic task distribution, fresh agent instances per task.

## Essential Commands

### Core Commands

| Command | Description |
|---------|-------------|
| `ralph loop` | Iterative loop with sandbox modes + budgets |
| `ralph models` | Show models and rate-limit status |
| `ralph cost` | Cost reporting and session breakdowns |
| `ralph stats` | Session statistics |
| `ralph cleanup` | Clean old sessions |
| `ralph agents` | Manage shared agent definitions |

### Session Management

```bash
ralph loop --list                              # List all sessions
ralph loop --status --session swift-fox-runs   # Session status
ralph loop --session swift-fox-runs            # Resume session
ralph cleanup                                  # Clean old sessions
ralph stats                                    # Session statistics
```

## Model Tiers

Models accessed via [OpenCode](https://github.com/opencode-ai/opencode) with OAuth (no API keys needed).

| Tier | OpenCode Models | Use Case |
|------|-----------------|----------|
| **high** | `anthropic/claude-opus-4-5`, `google/gemini-3-pro-preview` | Complex reasoning |
| **medium** | `anthropic/claude-sonnet-4-5`, `google/gemini-3-flash-preview` | Standard coding |
| **low** | `anthropic/claude-haiku-4-5`, `google/gemini-3-flash-preview` | Simple/quick tasks |

**Concurrency limits** (configurable in `config/models.json`):
- Opus: 2 concurrent
- Sonnet: 3 concurrent
- Gemini Pro: 5 concurrent
- Gemini Flash: 10 concurrent

## Configuration

### config/models.json

Model tiers, concurrency limits, retry settings:

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
      "anthropic/claude-opus-4-5": 2,
      "anthropic/claude-sonnet-4-5": 3
    }
  }
}
```

### config/sandbox.json

Anthropic sandbox allowlists:

```json
{
  "network": {
    "allowedDomains": [
      "api.anthropic.com",
      "github.com",
      "*.github.com",
      "registry.npmjs.org"
    ],
    "deniedDomains": []
  },
  "filesystem": {
    "denyRead": ["~/.ssh", "~/.aws"],
    "allowWrite": [".", "./**", "/tmp", "/tmp/**"],
    "denyWrite": []
  }
}
```

## Key Options

### ao / ralph loop

```
--mode, -m MODE          Execution mode: loop, gsd (default: loop)
--file FILE              Read prompt from file
--tier high|medium|low   Model tier (default: high)
--agent oc|cc            Agent: oc (opencode), cc (claudecode) (default: oc)
--dir DIR                Working directory (default: current directory)
--max N                  Max iterations (default: 50, 0=infinite)
--min N                  Minimum before completion allowed (default: 1)
--reset N                Reset state every N iterations (default: 5, 0=disable)
--stall N                Timeout without output in seconds (default: 600)
--promise TEXT           Expected completion text (default: COMPLETE)
--completion-mode MODE   Completion detection mode (default: promise)
                         promise: marker only (deterministic)
                         validate: marker + validator agent confirmation
--sandbox MODE           Sandbox: auto|none|docker|anthropic
--budget AMOUNT          Stop at cost limit, e.g., 5.00
--allow-write PATH       Add write path to allowlist (repeatable)
--session ID             Resume session
--list                   List all sessions
--status                 Show session status
--add-context TEXT       Inject context into next iteration
```

## Architecture

### Project Structure

```
Agent-Orchestration/
├── ralph                        # Main dispatcher
├── cmd/                         # Subcommand implementations
│   ├── loop.sh                  # Iterative agent loop
│   ├── models.sh                # Show available models
│   ├── cost.sh                  # Cost reporting
│   ├── stats.sh                 # Session statistics
│   ├── cleanup.sh               # Clean old sessions
│   └── agents.sh                # Manage shared agents
├── lib/                         # Shared libraries
│   ├── common.sh                # Entry point (sources all libs)
│   ├── core.sh                  # Locking, JSON, utilities
│   ├── model.sh                 # Model selection, rate limits
│   ├── sandbox.sh               # Sandbox execution
│   ├── agent.sh                 # Agent execution
│   ├── agents.sh                # Agent sync & management
│   ├── cost.sh                  # Cost tracking
│   └── stream-formatter.sh      # Claude Code stream-json formatter
├── config/                      # Configuration
│   ├── models.json              # Model tiers and settings
│   └── sandbox.json             # Sandbox allowlists
├── wrappers/
│   └── opencode-wrapped         # Rate limit + concurrency wrapper
├── agents/                      # Shared agent definitions
│   ├── yolo.md, explorer.md, reviewer.md, fixer.md, planner.md
├── gsd/                         # GSD integration
│   ├── install.sh, gsd-runner
├── setup/                       # Setup scripts
│   ├── ao.sh                    # Alias installation
│   └── contai.sh                # Docker sandbox setup
└── state/                       # Runtime state (created on first run)
    ├── rate-limits.json
    └── ralph/{session}/         # Session history
```

### How Rate Limiting Works

The `opencode-wrapped` wrapper intercepts all agent calls:

```
Agent Script
    ↓
opencode-wrapped
    ↓ (check rate limits)
    ↓ (acquire concurrency slot)
    ↓ (update state)
    ↓
Real OpenCode CLI
```

**GSD parallel execution**: Each subagent automatically uses the wrapper, preventing rate limit conflicts.

### How Shared Agents Work

1. **Source of truth**: `agents/*.md` files
2. **Auto-sync**: Scripts call `ensure_agents()` → syncs to `.opencode/agents/`
3. **No clobber**: Project-specific agents are never overwritten
4. **Docker**: Agents mounted at `/opt/shared-agents`, synced by `docker-entrypoint.sh`

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Not authenticated" | Run `opencode auth login` |
| "All models rate-limited" | Wait for cooldown or add models to `config/models.json` |
| "Docker not running" | Start Docker Desktop |
| "Anthropic sandbox not found" | `npm install -g @anthropic-ai/sandbox-runtime` |
| "GSD commands not found" | Run `./gsd/install.sh --opencode --global` |
| Session stuck/struggling | Check `ralph loop --status --session {id}` for struggle indicators |

## Advanced Usage

### Recommended Patterns

**Thorough autonomous work** (code cleanup, audits, large refactors):
```bash
ao "Address all lint and type errors in this repo" \
  --agent cc --min 5 --reset 1 --max 20 --sandbox docker
```
- `--min 5` prevents premature completion (agent must run at least 5 iterations)
- `--reset 1` clears context every iteration for fresh analysis (avoids fixating on stale approaches)
- `--sandbox docker` isolates execution so the agent can't break your host

**Supervised feature development** (new features, complex changes):
```bash
ao --file feature-spec.md \
  --tier high --max 15 --budget 8.00 --completion-mode validate
```
- `--file` loads a detailed spec so the agent knows exactly what to build
- `--completion-mode validate` runs a second agent to verify the work before marking complete
- `--budget` prevents runaway costs

**Quick fixes** (linting, formatting, small bugs):
```bash
ao "Fix the broken import in src/utils/index.ts" \
  --tier low --max 3 --sandbox none
```
- `--tier low` uses fast/cheap models (Haiku, Gemini Flash)
- `--max 3` stops quickly if it can't figure it out
- `--sandbox none` avoids overhead for low-risk work

**Overnight / unattended runs**:
```bash
ao "Migrate all API endpoints from v1 to v2 format" \
  --max 0 --reset 3 --budget 25.00 --sandbox anthropic --tier high
```
- `--max 0` means infinite iterations (runs until done or budget exhausted)
- `--reset 3` forces fresh context periodically so it doesn't get stuck in loops
- `--budget 25.00` is the hard stop that protects your wallet

### Completion Detection

```bash
# Default: agent must output <promise>COMPLETE</promise>
ao "Fix all tests" --max 10

# Custom marker text
ao --promise "ALL TESTS PASS" --file task.md
# Agent must output: <promise>ALL TESTS PASS</promise>

# Validate mode: marker + a validator agent confirms completion
ao "Implement auth" --completion-mode validate --tier high
```

### Claude Code vs OpenCode

```bash
# OpenCode (default) - supports Gemini, Claude, GPT via OAuth
ao "Fix bugs" --agent oc --tier medium

# Claude Code - Anthropic's official CLI, streaming output
ao "Fix bugs" --agent cc --tier medium
# Output shows thinking, tool use, and results in real-time
```

Use `--agent cc` when you want Claude-specific features (thinking, tool streaming) or when OpenCode is rate-limited. Use `--agent oc` (default) for multi-provider fallback.

### Session Lifecycle

```bash
# Start a session (gets unique ID like swift-fox-runs)
ao "Refactor the auth module" --tier high

# In another terminal: check progress
ao --status --session swift-fox-runs

# Inject context mid-run (agent sees this next iteration)
ao --add-context "The JWT secret is in .env, not hardcoded" \
  --session swift-fox-runs

# If you Ctrl+C, resume where you left off
ao --session swift-fox-runs

# List all sessions across all projects
ao --list

# Clean up sessions older than 7 days
ralph cleanup --days 7
```

### State Reset

Agent state (`state.md` and `history.json`) resets every 5 iterations by default. This prevents the agent from accumulating stale context:

```bash
# Default: reset every 5 iterations
ao "Big refactor" --max 50

# Reset every iteration (fresh eyes each time, best for cleanup tasks)
ao "Fix all issues" --reset 1 --max 20

# Never reset (agent keeps full memory, good for complex multi-step features)
ao "Build the payment system" --reset 0 --max 30

# Reset every 10 (compromise for long runs)
ao "Migrate database" --reset 10 --max 100
```

### Sandbox Setup

```bash
# Auto-detect best available sandbox
ao "Task" --sandbox auto

# Anthropic sandbox (lightweight, recommended)
npm install -g @anthropic-ai/sandbox-runtime  # one-time
ao "Task" --sandbox anthropic

# Docker sandbox (heavy isolation, supports OpenCode agents)
./setup/contai.sh  # one-time: clones contai, builds image
ao "Task" --sandbox docker

# Grant additional write paths when sandboxed
ao "Generate docs" --sandbox anthropic --allow-write ~/docs --allow-write ~/output

# Build a project-specific container from a Dockerfile
ao "Task" --sandbox docker --build-container ./Dockerfile.dev

# No sandbox (direct host execution)
ao "Task" --sandbox none
```

### MCP Server Integration

```bash
# Pass MCP config so the agent has access to external tools
ao "Query the prod database and fix the schema drift" \
  --mcp-config ./mcp-servers.json --tier high

# MCP config is forwarded to whichever agent runs:
# - Claude Code: passed via --mcp-config flag
# - OpenCode: mounted to ~/.config/opencode/mcp.json
```

### Parallel Execution

Run multiple sessions concurrently across different projects:

```bash
# Background multiple tasks
ao "Fix lint errors" --dir ~/project-a --budget 3.00 &
ao "Add unit tests" --dir ~/project-b --budget 5.00 &
ao "Update dependencies" --dir ~/project-c --tier low &
wait

# Rate limiting is shared: all sessions respect the same model concurrency limits
```

## Requirements

- **bash 4.0+**
- **jq** - JSON processing
- **[OpenCode CLI](https://github.com/opencode-ai/opencode)** - `npm install -g @anthropic-ai/opencode`

**Optional**:
- **Docker** - For Docker sandbox mode
- **Node.js 18+** - For Anthropic sandbox runtime
- **flock** - File locking (included on Linux, `brew install flock` on macOS)

## Acknowledgements

This project builds on ideas and tools from the AI-assisted development community:

- [everything is a ralph loop](https://ghuntley.com/loop/) - Geoff Huntley's original concept of iterative agent loops
- [Ralph Wiggum as a "software engineer"](https://ghuntley.com/ralph/) - The foundational blog post on autonomous AI coding loops
- [how to build a coding agent](https://ghuntley.com/agent/) - Geoff Huntley's free workshop on building coding agents
- [Get Shit Done (GSD)](https://github.com/glittercowboy/get-shit-done) - Spec-driven development framework for Claude Code
- [OpenCode](https://opencode.ai/) - Open source AI coding agent ([GitHub](https://github.com/opencode-ai/opencode))
- [Claude Code](https://github.com/anthropics/claude-code) - Anthropic's agentic coding tool
- [Claude Code best practices](https://www.anthropic.com/engineering/claude-code-best-practices) - Anthropic's guide to agentic coding

## License

MIT - See [LICENSE](LICENSE)

---

**See also**:
- [INSTALLATION.md](INSTALLATION.md) - Detailed setup guide
- [CONTRIBUTING.md](CONTRIBUTING.md) - How to contribute
- [SECURITY.md](SECURITY.md) - Security policy and vulnerability reporting
- [CLAUDE.md](CLAUDE.md) - Instructions for AI agents
