# Architecture

## Module Dependency Graph

```
ralph (dispatcher)
  ├── lib/common.sh (entry point, sources all libs)
  │     ├── lib/core.sh      - Locking, date, file helpers, JSON ops
  │     ├── lib/model.sh     - Model selection, rate limiting, concurrency
  │     └── lib/sandbox.sh   - Sandbox setup, state directory management
  │
  ├── cmd/loop.sh (main iterative loop)
  │     ├── lib/agents.sh    - Shared agent management
  │     ├── lib/cost.sh      - Cost tracking functions
  │     ├── lib/stream-formatter.sh - Claude Code stream-json formatter
  │     ├── lib/oc-formatter.sh     - OpenCode JSON formatter
  │     └── lib/mcp-convert.sh      - MCP config conversion (Claude <-> OpenCode)
  │
  ├── cmd/cost.sh       - Cost reporting
  ├── cmd/stats.sh      - Session statistics
  ├── cmd/cleanup.sh    - Old session cleanup
  ├── cmd/models.sh     - Model listing
  └── cmd/agents.sh     - Agent definition management

wrappers/
  └── agent-sandbox     - Docker container wrapper with auth forwarding

gsd/
  └── gsd-runner        - GSD workflow executor

config/
  ├── models.json       - Model tiers, rate limits, pricing
  └── sandbox.json      - Anthropic sandbox settings
```

## Data Flow

### Session Lifecycle

```
ralph loop "task prompt"
  │
  ├─ Generate session ID (e.g., swift-fox-runs-a1b2)
  ├─ Create .ralph/{session}/ directory
  │     ├── loop-state.json   - Active/inactive, iteration count, model
  │     ├── history.json      - Per-iteration timing, files, struggle indicators
  │     ├── state.md          - Agent-managed task tracking (read/written by agent)
  │     ├── context.md        - User-injected mid-loop context
  │     ├── cost-summary.json - Aggregated cost data
  │     └── logs/
  │           └── iteration-N.log  - Raw agent output per iteration
  │
  ├─ Main loop (iteration 1..N):
  │     ├── Capture git snapshot (before)
  │     ├── Build mission prompt with context
  │     ├── Select model (tier + rate limit awareness)
  │     ├── Run agent (via sandbox mode)
  │     ├── Capture git snapshot (after)
  │     ├── Diff snapshots → modified files
  │     ├── Check for completion marker
  │     ├── Record iteration to history
  │     ├── Track costs
  │     └── Check struggle indicators
  │
  └─ Exit on: completion, max iterations, or budget exceeded
```

### State File Structures

**loop-state.json** — Session metadata:
```json
{
  "active": true,
  "iteration": 3,
  "model": "anthropic/claude-sonnet-4-20250514",
  "maxIterations": 50,
  "minIterations": 1,
  "completionPromise": "COMPLETE",
  "startedAt": "2026-02-09T10:00:00Z"
}
```

**history.json** — Iteration records and struggle detection:
```json
{
  "iterations": [
    {
      "iteration": 1,
      "durationMs": 45000,
      "exitCode": 0,
      "completionDetected": false,
      "filesModified": ["M src/app.ts", "A tests/app.test.ts"]
    }
  ],
  "totalDurationMs": 45000,
  "struggleIndicators": {
    "repeatedErrors": {},
    "noProgressIterations": 0,
    "shortIterations": 0
  }
}
```

**cost-summary.json** — Per-iteration cost tracking:
```json
{
  "totalCost": 2.45,
  "iterations": [
    {"iteration": 1, "cost": "0.82"},
    {"iteration": 2, "cost": "1.63"}
  ]
}
```

## Rate Limiting

Rate limit handling lives in `lib/model.sh`:

```
get_next_available_model(tier, config, rate_limits, fallback, agent)
  │
  ├─ Load models for requested tier from config/models.json
  ├─ For each model in tier:
  │     ├── Check rate_limits file for cooldown expiry
  │     └── Return first available model
  │
  ├─ If fallback enabled and no models available:
  │     └── Try next tier down (high → medium → low)
  │
  └─ Return error if all models exhausted

mark_model_rate_limited(model, cooldown_seconds, rate_limits_file)
  └── Write expiry timestamp to rate_limits file
```

Rate limits are stored in `state/rate-limits.json`:
```json
{
  "anthropic/claude-sonnet-4-20250514": 1707480000,
  "google/gemini-2.5-pro": 1707480120
}
```

Timestamps are Unix epoch seconds. A model is available when `now > expiry`.

## Sandbox Modes

Controlled by `lib/sandbox.sh` and `wrappers/agent-sandbox`:

| Mode | Network | Filesystem | How |
|------|---------|-----------|-----|
| `anthropic` | Restricted | Sandboxed via `srt` | Anthropic sandbox-runtime |
| `docker` | Full | Container isolated | `wrappers/agent-sandbox` runs Docker |
| `claude` | Claude-managed | Claude-managed | Claude Code built-in sandbox |
| `none` | Full | Full | Direct execution on host |

**Docker sandbox (`wrappers/agent-sandbox`):**
- Mounts working directory to `/workspace`
- Mounts API keys via temp env file (`chmod 600`)
- Mounts OpenCode auth (`auth.json:ro`) and config (`:ro`)
- Mounts shared agents (`:ro`)
- Handles git worktree parent repo mounting
- Validates extra mounts against sensitive paths
- Extracts Claude OAuth token from macOS keychain

**Anthropic sandbox:**
- Uses `srt` (sandbox-runtime) with settings from `config/sandbox.json`
- Filesystem allowlist can be extended via `--allow-write`
- Creates patched sandbox config with extra paths when needed

## Completion Detection

```
check_completion(output_file)
  │
  ├─ Scan output for exact marker: <promise>COMPLETE</promise>
  │
  └─ If marker found, check completion mode:
       ├── "promise" → return success immediately
       └── "validate" → spawn validator agent
             ├── Validator reads: original task + state.md
             ├── Validator checks: task completeness, remaining work, quality
             ├── If validator outputs marker → confirmed complete
             └── If not → save feedback to validator-feedback.md
                   └── Next iteration receives feedback in prompt
```

The completion marker text is configurable via `--promise`. The exact match `<promise>{TEXT}</promise>` is required — no fuzzy matching.

## Agent Output Pipeline

```
{ agent-command 2>&1; echo $? > exit_code.tmp }
  │
  ├── tee "$OUTPUT_FILE"    ← Raw output saved to log
  │
  └── display_cc/display_oc ← Formatter (or /dev/null in brief mode)
        │
        └── Reads RALPH_VERBOSE env var for truncation control
```

Formatters parse agent-specific JSON output (Claude stream-json or OpenCode JSON) and render human-readable summaries of tool calls, file edits, and agent reasoning.
