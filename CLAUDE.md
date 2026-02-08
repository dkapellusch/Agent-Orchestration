# CLAUDE.md - Agent Orchestrator

Instructions for AI agents working in this codebase.

## What This Is

Agent Orchestrator runs AI coding agents via OpenCode or Claude Code with rate limit handling. The main tool is `ao` (alias for `ralph loop`) which iterates the same prompt until you signal completion.

Supports multiple execution modes:
- **loop** (default) - Iterative until completion marker
- **gsd** - Structured GSD workflow (`ao -m gsd plan 1`)

## How Ralph Loop Works

1. You receive a task prompt with Mission Control Protocol instructions
2. **ORIENT FIRST**: Study the spec, state file, and existing code
3. Work on tasks, delegating research to subagents
4. Update `state.md` with progress and discoveries
5. If you're not done, describe progress and STOP - next iteration continues
6. When truly complete, output the **completion marker**: `<promise>COMPLETE</promise>`

**Key insight:** Your state file `.ralph/{SESSION_ID}/state.md` persists between iterations (resets every 5 iterations by default). Use it to track tasks, discoveries, and blockers.

## The State File

Each session creates `.ralph/{SESSION_ID}/state.md` in the working directory. Structure it like this:

```markdown
# Task: [spec name]
Session: abc12345

## Plan (prioritized tasks remaining)
- [ ] Implement feature X
- [ ] Add tests for feature X
- [x] Set up project structure

## Discoveries (learnings for future iterations)
- Found existing utility at src/lib/utils.ts
- Build command: `npm run build`
- Pattern: All services use Result<T> return type

## Blockers
- None currently
```

**Critical**: Read this file FIRST every iteration. Update it as you work.

**Note**: State resets every 5 iterations by default (`--reset-after 5`). This clears both `state.md` and `history.json` to force fresh analysis and prevent stale context from accumulating.

## Orientation Phase (Do This FIRST)

Every iteration, before doing any work:
1. Study the spec file to understand requirements
2. Read your state file to see what's done and what remains
3. Check for `AGENTS.md` or `CLAUDE.md` for build/test commands
4. Search existing code before implementing - **don't assume not implemented**

## Context Efficiency

Use your main context as a **scheduler**, not a worker:
- Spawn parallel subagents for file searches and reading code
- Spawn parallel subagents for file modifications
- Use only **1 subagent** for running build/tests (backpressure)

This keeps your main context clean for reasoning and coordination.

## Critical Principle: Don't Assume Not Implemented

Before adding any functionality, **search the codebase first** to confirm it doesn't already exist. Duplicate implementations waste iterations. This is the Achilles' heel of autonomous agents.

## Signaling Completion

Output the completion marker when your task is **fully complete**:
```
<promise>COMPLETE</promise>
```

The exact marker text may be customized via `--completion-promise`. Check the Mission Control Protocol in your prompt for the expected marker.

**Completion modes** (controlled by `--completion-mode`):
- `promise` (default) - Just output the marker
- `validate` - Marker + a validator agent must also confirm completion

Before outputting:
- ALL checkboxes in state file must be [x]
- ALL tests must PASS (show actual output)
- NO TODO/FIXME/placeholder markers in code
- Record all discoveries in state file

## Guardrails (higher number = more critical)

```
99.        Use subagents for research to preserve main context
999.       Capture discoveries in state file - future iterations depend on this
9999.      When you learn build/test commands, record them in Discoveries
99999.     Implement completely - placeholders and stubs waste iterations
999999.    DON'T ASSUME NOT IMPLEMENTED - search codebase before adding
9999999.   Tests must PASS with real output shown
99999999.  ALL checkboxes must be [x] before completion marker
999999999. DO NOT LIE. This is production code.
```

## Key Files

| File/Directory | Purpose |
|----------------|---------|
| `ralph` | Main dispatcher - routes to subcommands |
| `cmd/loop.sh` | Iterative agent loop (supports loop/gsd modes) |
| `cmd/models.sh` | Show available models |
| `cmd/cost.sh` | Cost reporting |
| `cmd/stats.sh` | Session statistics |
| `cmd/cleanup.sh` | Clean old sessions |
| `lib/common.sh` | Entry point that sources all libraries |
| `lib/core.sh` | Core utility functions (locking, date, file helpers) |
| `lib/model.sh` | Model selection, rate limiting, and concurrency |
| `lib/sandbox.sh` | Sandbox setup and state directory management |
| `lib/agents.sh` | Shared agent management |
| `lib/cost.sh` | Cost tracking functions |
| `lib/stream-formatter.sh` | Formats Claude Code stream-json output |
| `lib/oc-formatter.sh` | Formats OpenCode JSON output |
| `lib/mcp-convert.sh` | Converts MCP configs between Claude/OpenCode formats |
| `gsd/gsd-runner` | GSD workflow executor |
| `wrappers/agent-sandbox` | Docker container wrapper with auth forwarding |
| `config/models.json` | Model tiers and settings |
| `tests.sh` | Test suite - run with `./tests.sh` |

## Making Changes

When modifying these scripts:
1. Follow existing bash style (shellcheck clean)
2. Use functions from `lib/common.sh` for locking/JSON ops
3. Run `./tests.sh` to verify changes
4. Ensure macOS compatibility (bash 4.0+, BSD tools)

## Testing

```bash
# Run all tests
./tests.sh

# Tests cover:
# - lib/common.sh locking and JSON functions
# - Script help outputs for all ralph subcommands
# - Completion detection with <promise>COMPLETE</promise> markers
# - Completion modes (promise, validate)
# - ralph cleanup session management
# - Cost tracking functions
# - Shared agent management
# - Rate limit detection (avoiding false positives)
```

## Architecture

```
ralph <subcommand>  (or ao alias)
    ├── Sources lib/common.sh (loads all libraries)
    ├── Dispatches to cmd/{subcommand}.sh
    │
    └── cmd/loop.sh (main iterative loop)
        ├── Parses args (--mode: loop/gsd/run)
        ├── Creates .ralph/{SESSION_ID}/ task directory
        ├── Main loop:
        │   ├── build_mission_prompt() - builds prompt with context
        │   ├── get_available_model() - picks model, handles rate limits
        │   ├── run_agent() - executes via OpenCode or Claude Code
        │   ├── check_completion() - looks for <promise>COMPLETE</promise>
        │   ├── reset state every N iterations (default: 5)
        │   └── update_session() - increments iteration count
        └── Exits on completion or max iterations
```

## Do Not

- Change completion detection to be fuzzy (must be exact match)
- Break macOS compatibility (test with bash 4.0+)
- Skip the orientation phase - always read state file first
- Pollute main context with research - use subagents
- Assume functionality doesn't exist - search first
