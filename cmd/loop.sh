#!/usr/bin/env bash
# loop.sh - Iterative AI agent loop with multi-sandbox support
# Invoked via: ralph loop [OPTIONS] [PROMPT]
#
# Features:
# - Unique session IDs (e.g., swift-fox-runs) for concurrent execution
# - Struggle detection (repeated errors, no progress, short iterations)
# - File change tracking via git status
# - Iteration history and summaries
# - Mid-loop context injection
# - Model tier selection with fallbacks
# - Mission Control Protocol for better agent behavior
# - Multi-sandbox support: anthropic (default), docker, none
# - Rate limit tracking

# Source additional libraries
source "$RALPH_ROOT/lib/agents.sh"
source "$RALPH_ROOT/lib/cost.sh"

CONFIG="$RALPH_CONFIG"
SANDBOX_CONFIG="$RALPH_SANDBOX_CONFIG"
SANDBOX_SCRIPT="$RALPH_ROOT/wrappers/agent-sandbox"
RATE_LIMITS="$RALPH_STATE_DIR/rate-limits.json"

# ============================================================================
# Sandbox Configuration
# ============================================================================

require_sandbox_config() {
    if [[ ! -f "$SANDBOX_CONFIG" ]]; then
        echo "Error: Sandbox config not found: $SANDBOX_CONFIG" >&2
        echo "Copy config/sandbox.json to get started." >&2
        exit 1
    fi
}

# Create a patched sandbox config with extra allowed write paths
create_patched_sandbox_config() {
    local extra_paths=("$@")

    if [[ ${#extra_paths[@]} -eq 0 ]]; then
        echo "$SANDBOX_CONFIG"
        return
    fi

    local temp_config
    temp_config=$(mktemp -t "sandbox-config-XXXXXX.json")

    local expanded_paths=()
    for path in "${extra_paths[@]}"; do
        expanded_paths+=("${path/#\~/$HOME}")
    done

    if ! jq --args '.filesystem.allowWrite += $ARGS.positional' "$SANDBOX_CONFIG" -- "${expanded_paths[@]}" > "$temp_config" 2>/dev/null; then
        rm -f "$temp_config"
        echo "Warning: Failed to create custom sandbox config, using default" >&2
        echo "$SANDBOX_CONFIG"
        return 1
    fi
    echo "$temp_config"
}

check_srt_available() {
    command -v srt &>/dev/null
}

get_effective_sandbox() {
    local requested="$1"
    local agent="${2:-opencode}"

    case "$requested" in
        none)
            echo "none"
            ;;
        docker)
            if ! run_with_timeout 5 docker info &>/dev/null; then
                echo "Warning: Docker not available, falling back to 'none'" >&2
                echo "none"
            else
                echo "docker"
            fi
            ;;
        anthropic)
            # For claudecode, 'anthropic' means use Claude's built-in sandbox
            if [[ "$agent" == "claudecode" ]]; then
                echo "claude"
            elif ! check_srt_available; then
                echo "Warning: srt (sandbox-runtime) not found, falling back to 'none'" >&2
                echo "Hint: Install with: npm install -g @anthropic-ai/sandbox-runtime" >&2
                echo "none"
            else
                echo "anthropic"
            fi
            ;;
        auto)
            # For claudecode, auto means use Claude's built-in sandbox
            if [[ "$agent" == "claudecode" ]]; then
                echo "claude"
            elif check_srt_available; then
                echo "anthropic"
            elif run_with_timeout 5 docker info &>/dev/null; then
                echo "docker"
            else
                echo "none"
            fi
            ;;
        *)
            echo "Error: Invalid sandbox mode '$requested'. Use: none, docker, anthropic, or auto" >&2
            exit 1
            ;;
    esac
}

# Load defaults from config
load_config_defaults "$CONFIG"

# Word lists for session names
ADJECTIVES=(quick lazy happy angry brave calm swift gentle fierce quiet bold shy wild free kind)
NOUNS=(fox wolf bear hawk owl deer fish crow dove lion frog duck swan moth crab)
VERBS=(runs leaps soars dives hunts rests waits grows flies swims jumps walks hides seeks roams)

generate_session_id() {
    # Entropy: 15 adjectives * 15 nouns * 16 verbs * 65536 hex = ~236M combinations
    # Sufficient for single-user workstation use; consider uuidgen for high-concurrency CI
    local adj=${ADJECTIVES[$RANDOM % ${#ADJECTIVES[@]}]}
    local noun=${NOUNS[$RANDOM % ${#NOUNS[@]}]}
    local verb=${VERBS[$RANDOM % ${#VERBS[@]}]}
    local hex
    hex=$(printf '%04x' $((RANDOM % 65536)))
    echo "${adj}-${noun}-${verb}-${hex}"
}

# Show brief help if no arguments (full usage() defined below)
if [[ $# -eq 0 ]]; then
    cat <<EOF
Usage: ralph loop [OPTIONS] [PROMPT]

Iterative agent loop with multi-sandbox support, struggle detection, and history tracking.
Each task gets a unique session (e.g., swift-fox-runs) allowing multiple concurrent loops.

Run 'ralph loop --help' for full options.
EOF
    exit 0
fi

# Defaults
MODE="loop"
TIER="$DEFAULT_TIER"
MAX_ITERATIONS=50
MIN_ITERATIONS=1
WORKING_DIR="$(pwd)"
PROMPT=""
PROMPT_FILE=""
MODEL_OVERRIDE=""
SANDBOX_MODE="auto"
COMPLETION_PROMISE="COMPLETE"
SESSION_ID=""
SHOW_STATUS=false
LIST_SESSIONS=false
TIER_FALLBACK=true
STALL_TIMEOUT=600
AGENT="opencode"
COOLDOWN="$DEFAULT_COOLDOWN"
RESET_AFTER=5
EXTRA_ALLOW_WRITE=()
TEMP_SANDBOX_CONFIG=""
BUDGET_LIMIT=""
COMPLETION_MODE="promise"
BUILD_CONTAINER=""
CONTAINER_IMAGE="agent-sandbox:latest"
MCP_CONFIG=""
VERBOSE=false
OUTPUT_MODE="normal"

usage() {
    cat <<EOF
Usage: ralph loop [OPTIONS] [PROMPT]
       ao [OPTIONS] [PROMPT]

Unified agent orchestration with multiple execution modes.

Modes (--mode, -m):
  loop    Iterative loop until completion marker (default)
  gsd     GSD (Get Shit Done) structured workflow

Options:
  --mode, -m MODE       Execution mode: loop, gsd (default: loop)
  --file FILE           Read prompt from file
  --agent AGENT         Agent: oc (opencode) or cc (claudecode) (default: oc)
  --tier TIER           Model tier: high, medium, low (default: high)
  --model MODEL         Specific model to use (overrides --tier)
  --dir DIR             Working directory
  --session ID          Resume specific session (e.g., swift-fox-runs)
  --list                List all sessions in working directory
  --min N               Minimum iterations before completion allowed (default: 1)
  --max N               Maximum iterations (default: 50, 0=infinite)
  --reset N             Reset agent state every N iterations (default: 5, 0=disable)
  --stall N             Seconds without output before stalled (default: 600)
  --promise TEXT        Completion marker text (default: COMPLETE)
  --completion-mode M   Completion mode: promise, validate (default: promise)
                        promise: requires only the marker (default, deterministic)
                        validate: marker + launches validator agent to verify completion
  --sandbox MODE        Sandbox mode: auto, none, docker, anthropic (default: auto)
  --allow-write PATH    Add path to allowed write list (can repeat)
  --budget AMOUNT       Set budget limit in dollars (e.g., --budget 5.00)
  --build-container [PATH]  Build project-specific container from Dockerfile
                        Uses Dockerfile at PATH, or searches for:
                        Dockerfile.ralph, .ralph/Dockerfile, Dockerfile
  --mcp-config PATH     Load MCP servers from JSON config file
                        For Claude Code: passed via --mcp-config flag
                        For OpenCode: mounted to ~/.config/opencode/mcp.json
  --add-context TEXT    Add context for next iteration (requires --session)
  --status              Show loop status and history
  --output MODE         Output mode: normal, brief, verbose (default: normal)
                        normal: formatted agent output + iteration summaries
                        brief: suppress agent output, show only summaries
                        verbose: full output, no truncation
  --verbose, -v         Shorthand for --output verbose
  -h, --help            Show this help

GSD Commands (use with -m gsd):
  new                 Start new project
  map                 Analyze existing codebase
  discuss [N]         Capture implementation decisions
  plan [N]            Research + plan + verify
  execute <N>         Execute tasks in parallel
  verify [N]          User acceptance testing
  quick [desc]        Execute ad-hoc task
  debug [desc]        Systematic debugging
  progress            Show current status
  help                Show all GSD commands

Examples:
  # Loop mode (default)
  ao "Fix all lint errors" --max 10
  ao --file ./task.md --tier medium
  ao "Add tests" --sandbox docker

  # GSD mode
  ao -m gsd new
  ao -m gsd plan 1 --sandbox docker
  ao -m gsd execute 1 --tier medium --agent cc

  # Session management
  ao --list
  ao --status --session swift-fox-runs
  ao --session swift-fox-runs
EOF
}

# Parse arguments
ADD_CONTEXT=""
SESSION_PROVIDED=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode|-m) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; MODE="$2"; shift 2 ;;
        --file) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; PROMPT_FILE="$2"; shift 2 ;;
        --agent) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; AGENT="$2"; shift 2 ;;
        --tier) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; TIER="$2"; shift 2 ;;
        --model) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; MODEL_OVERRIDE="$2"; shift 2 ;;
        --dir) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; WORKING_DIR="$2"; shift 2 ;;
        --session) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; SESSION_ID="$2"; SESSION_PROVIDED=true; shift 2 ;;
        --list) LIST_SESSIONS=true; shift ;;
        --min|--min-iterations) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; MIN_ITERATIONS="$2"; shift 2 ;;
        --max|--max-iterations) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; MAX_ITERATIONS="$2"; shift 2 ;;
        --stall|--stall-timeout) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; STALL_TIMEOUT="$2"; shift 2 ;;
        --reset|--reset-after) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; RESET_AFTER="$2"; shift 2 ;;
        --promise|--completion-promise) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; COMPLETION_PROMISE="$2"; shift 2 ;;
        --completion-mode) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; COMPLETION_MODE="$2"; shift 2 ;;
        --sandbox) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; SANDBOX_MODE="$2"; shift 2 ;;
        --allow-write) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; EXTRA_ALLOW_WRITE+=("$2"); shift 2 ;;
        --budget) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; BUDGET_LIMIT="$2"; shift 2 ;;
        --build-container)
            # Check if next arg is a path or another flag
            if [[ -n "${2:-}" ]] && [[ ! "$2" =~ ^- ]]; then
                BUILD_CONTAINER="$2"
                shift 2
            else
                BUILD_CONTAINER="auto"
                shift
            fi
            ;;
        --mcp-config)
            [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }
            MCP_CONFIG="$2"
            if [[ ! -f "$MCP_CONFIG" ]]; then
                echo "Error: MCP config file not found: $MCP_CONFIG" >&2
                exit 1
            fi
            # Convert to absolute path
            MCP_CONFIG="$(cd "$(dirname "$MCP_CONFIG")" && pwd)/$(basename "$MCP_CONFIG")"
            shift 2
            ;;
        --add-context) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; ADD_CONTEXT="$2"; shift 2 ;;
        --status) SHOW_STATUS=true; shift ;;
        --output) [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 1; }; OUTPUT_MODE="$2"; shift 2 ;;
        --verbose|-v) VERBOSE=true; OUTPUT_MODE="verbose"; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Error: Unknown option: $1" >&2; exit 1 ;;
        *) PROMPT="$1"; shift ;;
    esac
done

# Validate session ID (prevent path traversal)
if [[ -n "$SESSION_ID" ]] && [[ ! "$SESSION_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Invalid session ID '$SESSION_ID'. Only alphanumeric, hyphens, and underscores allowed." >&2
    exit 1
fi

# Validate numeric arguments
for _numvar in MIN_ITERATIONS MAX_ITERATIONS STALL_TIMEOUT RESET_AFTER; do
    _numval="${!_numvar}"
    if [[ -n "$_numval" ]] && [[ ! "$_numval" =~ ^[0-9]+$ ]]; then
        echo "Error: --${_numvar,,} must be a number, got '$_numval'" >&2
        exit 1
    fi
done
if [[ -n "$BUDGET_LIMIT" ]] && [[ ! "$BUDGET_LIMIT" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    echo "Error: --budget must be a number, got '$BUDGET_LIMIT'" >&2
    exit 1
fi

# Validate mode and route to appropriate handler
case "$MODE" in
    loop)
        # Continue with ralph loop (this file)
        ;;
    gsd)
        # Route to gsd-runner with common flags
        GSD_ARGS=()
        [[ -n "$TIER" ]] && GSD_ARGS+=(--tier "$TIER")
        [[ -n "$MODEL_OVERRIDE" ]] && GSD_ARGS+=(--model "$MODEL_OVERRIDE")
        [[ "$SANDBOX_MODE" == "docker" ]] && GSD_ARGS+=(--sandbox)
        [[ -n "$WORKING_DIR" && "$WORKING_DIR" != "$(pwd)" ]] && GSD_ARGS+=(--dir "$WORKING_DIR")
        [[ "$AGENT" != "opencode" ]] && GSD_ARGS+=(--agent "$AGENT")
        [[ -n "$MCP_CONFIG" ]] && GSD_ARGS+=(--mcp-config "$MCP_CONFIG")
        [[ -n "$BUILD_CONTAINER" ]] && GSD_ARGS+=(--build-container "$BUILD_CONTAINER")
        if [[ ${#EXTRA_ALLOW_WRITE[@]} -gt 0 ]]; then
            for path in "${EXTRA_ALLOW_WRITE[@]}"; do
                GSD_ARGS+=(--allow-write "$path")
            done
        fi

        # Get prompt from file if specified
        if [[ -n "$PROMPT_FILE" ]]; then
            PROMPT="$(cat "$PROMPT_FILE")"
        fi

        if [[ -z "$PROMPT" ]]; then
            echo "Error: No GSD command provided" >&2
            echo ""
            echo "Usage: ao -m gsd <command> [args]"
            echo ""
            echo "Commands:"
            echo "  new                 Start new project (/gsd:new-project)"
            echo "  map                 Analyze codebase (/gsd:map-codebase)"
            echo "  discuss [N]         Capture decisions (/gsd:discuss-phase)"
            echo "  plan [N]            Research + plan (/gsd:plan-phase)"
            echo "  execute <N>         Execute tasks (/gsd:execute-phase)"
            echo "  verify [N]          User acceptance (/gsd:verify-work)"
            echo "  quick [desc]        Ad-hoc task (/gsd:quick)"
            echo "  debug [desc]        Systematic debug (/gsd:debug)"
            echo "  progress            Show status (/gsd:progress)"
            echo "  help                Show all commands (/gsd:help)"
            echo ""
            echo "Examples:"
            echo "  ao -m gsd new"
            echo "  ao -m gsd plan 1 --sandbox docker"
            echo "  ao -m gsd execute 1 --tier medium"
            exit 1
        fi

        # Translate short commands to /gsd: format
        # Split PROMPT into command and remaining args
        GSD_CMD="${PROMPT%% *}"
        GSD_REST="${PROMPT#* }"
        [[ "$GSD_REST" == "$PROMPT" ]] && GSD_REST=""

        case "$GSD_CMD" in
            new)        GSD_PROMPT="/gsd:new-project $GSD_REST" ;;
            map)        GSD_PROMPT="/gsd:map-codebase $GSD_REST" ;;
            discuss)    GSD_PROMPT="/gsd:discuss-phase $GSD_REST" ;;
            plan)       GSD_PROMPT="/gsd:plan-phase $GSD_REST" ;;
            execute)    GSD_PROMPT="/gsd:execute-phase $GSD_REST" ;;
            verify)     GSD_PROMPT="/gsd:verify-work $GSD_REST" ;;
            quick)      GSD_PROMPT="/gsd:quick $GSD_REST" ;;
            debug)      GSD_PROMPT="/gsd:debug $GSD_REST" ;;
            progress)   GSD_PROMPT="/gsd:progress $GSD_REST" ;;
            pause)      GSD_PROMPT="/gsd:pause-work $GSD_REST" ;;
            resume)     GSD_PROMPT="/gsd:resume-work $GSD_REST" ;;
            help)       GSD_PROMPT="/gsd:help $GSD_REST" ;;
            /gsd:*)     GSD_PROMPT="$PROMPT" ;;  # Already in /gsd: format
            *)
                echo "Error: Unknown GSD command '$GSD_CMD'" >&2
                echo "Run 'ao -m gsd' to see available commands"
                exit 1
                ;;
        esac

        exec "$RALPH_ROOT/gsd/gsd-runner" "${GSD_ARGS[@]}" "$GSD_PROMPT"
        ;;
    *)
        echo "Error: Invalid mode '$MODE'. Must be 'loop' or 'gsd'" >&2
        exit 1
        ;;
esac

# Normalize agent shorthand
case "$AGENT" in
    oc|opencode) AGENT="opencode" ;;
    cc|claudecode) AGENT="claudecode" ;;
    *)
        echo "Error: Invalid agent '$AGENT'. Must be 'oc' (opencode) or 'cc' (claudecode)" >&2
        exit 1
        ;;
esac

# Validate min/max iterations
if [[ $MAX_ITERATIONS -ne 0 ]] && [[ $MIN_ITERATIONS -gt $MAX_ITERATIONS ]]; then
    echo "Error: --min ($MIN_ITERATIONS) cannot exceed --max ($MAX_ITERATIONS)" >&2
    exit 1
fi

# Validate completion mode
if [[ "$COMPLETION_MODE" != "promise" && "$COMPLETION_MODE" != "validate" ]]; then
    echo "Error: Invalid completion mode '$COMPLETION_MODE'. Must be 'promise' or 'validate'" >&2
    exit 1
fi

if [[ "$OUTPUT_MODE" != "normal" && "$OUTPUT_MODE" != "brief" && "$OUTPUT_MODE" != "verbose" ]]; then
    echo "Error: Invalid output mode '$OUTPUT_MODE'. Must be 'normal', 'brief', or 'verbose'" >&2
    exit 1
fi
if [[ "$OUTPUT_MODE" == "verbose" ]]; then
    VERBOSE=true
fi

# Initialize directories
init_state_dir "$RALPH_STATE_DIR"

# Base ralph directory
RALPH_BASE="$WORKING_DIR/.ralph"

# List all sessions in RALPH_BASE and print summary table
list_sessions() {
    if [[ -d "$RALPH_BASE" ]]; then
        local found=false
        for session_dir in "$RALPH_BASE"/*/; do
            [[ -d "$session_dir" ]] || continue
            local session_name
            session_name=$(basename "$session_dir")
            local state_file="$session_dir/loop-state.json"

            if [[ -f "$state_file" ]]; then
                found=true
                local active iteration max_iter started status
                active=$(jq -r '.active // false' "$state_file")
                iteration=$(jq -r '.iteration // 0' "$state_file")
                max_iter=$(jq -r '.maxIterations // 0' "$state_file")
                started=$(jq -r '.startedAt // "unknown"' "$state_file")

                if [[ "$active" == "true" ]]; then
                    status="ACTIVE"
                else
                    status="done"
                fi

                printf "  %-25s %s  (%d/%d)  %s\n" "$session_name" "$status" "$iteration" "$max_iter" "$started"
            fi
        done

        if [[ "$found" == "false" ]]; then
            echo "  No sessions found"
        fi
    else
        echo "  No .ralph directory exists yet"
    fi
}

# Handle --list
if [[ "$LIST_SESSIONS" == "true" ]]; then
    echo ""
    echo "Ralph Sessions"
    echo "=============="
    echo ""
    echo "Directory: $RALPH_BASE"
    echo ""
    list_sessions
    echo ""
    exit 0
fi

# Session paths
if [[ -z "$SESSION_ID" ]]; then
    SESSION_ID=$(generate_session_id)
fi
# Validate session ID regardless of source (defense in depth)
if [[ ! "$SESSION_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Invalid session ID '$SESSION_ID'. Only alphanumeric, hyphens, and underscores allowed." >&2
    exit 1
fi
RALPH_DIR="$RALPH_BASE/$SESSION_ID"
STATE_FILE="$RALPH_DIR/loop-state.json"
HISTORY_FILE="$RALPH_DIR/history.json"
CONTEXT_FILE="$RALPH_DIR/context.md"

# Handle --add-context
if [[ -n "$ADD_CONTEXT" ]]; then
    if [[ ! -d "$RALPH_DIR" ]]; then
        echo "Error: Session '$SESSION_ID' not found" >&2
        echo "Use --list to see available sessions" >&2
        exit 1
    fi
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf '\n## Context added at %s\n%s\n' "$timestamp" "$ADD_CONTEXT" >> "$CONTEXT_FILE"
    echo "Context added for session: $SESSION_ID"
    echo "   File: $CONTEXT_FILE"
    exit 0
fi

# Handle --status
if [[ "$SHOW_STATUS" == "true" ]]; then
    if [[ "$SESSION_PROVIDED" == "false" ]]; then
        echo ""
        echo "Ralph Sessions Status"
        echo "====================="
        echo ""
        echo "Directory: $RALPH_BASE"
        echo ""
        list_sessions
        echo ""
        echo "Use --status --session <name> for detailed session info"
        echo ""
        exit 0
    fi

    echo ""
    echo "Ralph Loop Status"
    echo "================="
    echo ""
    echo "Session: $SESSION_ID"
    echo ""

    if [[ -f "$STATE_FILE" ]]; then
        iteration=$(jq -r '.iteration // 0' "$STATE_FILE")
        max_iter=$(jq -r '.maxIterations // 0' "$STATE_FILE")
        started=$(jq -r '.startedAt // "unknown"' "$STATE_FILE")
        model=$(jq -r '.model // "unknown"' "$STATE_FILE")
        active=$(jq -r '.active // false' "$STATE_FILE")

        if [[ "$active" == "true" ]]; then
            echo "ACTIVE LOOP"
        else
            echo "Loop inactive"
        fi
        echo "   Iteration:  $iteration / $max_iter"
        echo "   Started:    $started"
        echo "   Model:      $model"
    else
        echo "No session found: $SESSION_ID"
        echo ""
        echo "Use --list to see available sessions"
        exit 1
    fi

    if [[ -f "$HISTORY_FILE" ]]; then
        echo ""
        echo "HISTORY"
        total_time=$(jq -r '.totalDurationMs // 0' "$HISTORY_FILE")
        total_secs=$((total_time / 1000))
        echo "   Total time: ${total_secs}s"

        echo ""
        echo "   Recent iterations:"
        jq -r '.iterations[-5:][] | "   \(if .completionDetected then "OK" elif .exitCode != 0 then "ERR" else "..." end) #\(.iteration): \(.durationMs/1000 | floor)s | files: \(.filesModified | length)"' "$HISTORY_FILE" 2>/dev/null || echo "   (no history)"

        no_progress=$(jq -r '.struggleIndicators.noProgressIterations // 0' "$HISTORY_FILE")
        short_iters=$(jq -r '.struggleIndicators.shortIterations // 0' "$HISTORY_FILE")

        if [[ $no_progress -ge 3 ]] || [[ $short_iters -ge 3 ]]; then
            echo ""
            echo "STRUGGLE INDICATORS:"
            [[ $no_progress -ge 3 ]] && echo "   - No file changes in $no_progress iterations"
            [[ $short_iters -ge 3 ]] && echo "   - $short_iters very short iterations (<30s)"
            echo "   Tip: Use: ralph loop --add-context \"your hint\" --session $SESSION_ID"
        fi
    fi

    if [[ -f "$CONTEXT_FILE" ]]; then
        echo ""
        echo "PENDING CONTEXT:"
        sed 's/^/   /' "$CONTEXT_FILE"
    fi

    cost_summary_file="$RALPH_DIR/cost-summary.json"
    if [[ -f "$cost_summary_file" ]]; then
        echo ""
        echo "COST"
        total_cost=$(jq -r '.totalCost // 0' "$cost_summary_file")
        num_iterations=$(jq -r '.iterations | length' "$cost_summary_file")
        printf "   Total: \$%.4f across %d iterations\n" "$total_cost" "$num_iterations"

        echo "   Recent iterations:"
        jq -r '.iterations[-5:][] | "   #\(.iteration): $\(.cost | tonumber | . * 10000 | round / 10000)"' "$cost_summary_file" 2>/dev/null || echo "   (no data)"
    fi

    echo ""
    exit 0
fi

# Validate prompt
if [[ -z "$PROMPT_FILE" ]] && [[ -z "$PROMPT" ]]; then
    echo "Error: No prompt provided" >&2
    usage
    exit 1
fi

get_prompt_content() {
    if [[ -n "$PROMPT_FILE" ]] && [[ -f "$PROMPT_FILE" ]]; then
        cat "$PROMPT_FILE"
    else
        echo "$PROMPT"
    fi
}

get_available_model() {
    local tier=$1
    get_next_available_model "$tier" "$CONFIG" "$RATE_LIMITS" "$TIER_FALLBACK" "$AGENT"
}

tier_to_claude_model() {
    local tier=${1:-$TIER}
    case "$tier" in
        high)   echo "opus" ;;
        medium) echo "sonnet" ;;
        low)    echo "haiku" ;;
        *)      echo "sonnet" ;;
    esac
}

mark_rate_limited() {
    local model=$1
    mark_model_rate_limited "$model" "$COOLDOWN" "$RATE_LIMITS"
}

capture_file_snapshot() {
    local snapshot_file="$1"
    git -C "$WORKING_DIR" status --porcelain 2>/dev/null > "$snapshot_file" || touch "$snapshot_file"
}

get_modified_files() {
    local before="$1" after="$2"
    # comm requires sorted input; git status --porcelain output is not sorted
    comm -13 <(sort "$before") <(sort "$after")
}

load_context() {
    if [[ -f "$CONTEXT_FILE" ]]; then
        cat "$CONTEXT_FILE"
    fi
}

clear_context() {
    rm -f "$CONTEXT_FILE"
}

build_mission_prompt() {
    local iteration=$1
    local base_prompt
    base_prompt=$(get_prompt_content)

    local context
    context=$(load_context)
    local context_section=""
    if [[ -n "$context" ]]; then
        context_section="
## Additional Context (added by user mid-loop)

$context

---"
    fi

    # Load one-shot validator feedback (cleared after reading)
    local validator_feedback=""
    local validator_file="$RALPH_DIR/validator-feedback.md"
    if [[ -f "$validator_file" ]]; then
        validator_feedback=$(cat "$validator_file")
        rm -f "$validator_file"
    fi

    local validator_section=""
    if [[ -n "$validator_feedback" ]]; then
        validator_section="
## ⚠️ Previous Validation Failed

$validator_feedback

**You must address these issues before claiming completion again.**

---"
    fi

    local marker="<promise>$COMPLETION_PROMISE</promise>"

    cat <<EOF
# Ralph Loop - Iteration $iteration / $MAX_ITERATIONS

You are in an iterative development loop. Work on the task until genuinely complete.
$context_section$validator_section

## Your Task

$base_prompt

## Instructions

1. **Read current state** - Check what's been done in previous iterations
2. **Update todo list** - Use TodoWrite to track progress
3. **Make progress** - Work on remaining tasks
4. **Verify** - Run tests/checks if applicable
5. **Signal completion** - When TRULY done, output exactly: $marker

## Critical Rules

- ONLY output $marker when task is genuinely complete
- Do NOT lie or output false promises to exit the loop
- If stuck, try a different approach
- Check your work before claiming completion
- The loop continues until you succeed

## State File (track progress here)

Create/update .ralph/$SESSION_ID/state.md with:
- [ ] Remaining tasks
- [x] Completed tasks
- Discoveries and learnings
- Blockers encountered

Now work on the task. Good luck!
EOF
}

init_state() {
    local model=$1
    mkdir -p "$RALPH_DIR/logs"
    if ! jq -n \
        --arg model "$model" \
        --argjson maxIterations "$MAX_ITERATIONS" \
        --argjson minIterations "$MIN_ITERATIONS" \
        --arg completionPromise "$COMPLETION_PROMISE" \
        --arg startedAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{active: true, iteration: 1, model: $model, maxIterations: $maxIterations,
          minIterations: $minIterations, completionPromise: $completionPromise,
          startedAt: $startedAt}' > "$STATE_FILE"; then
        echo "Error: Failed to initialize state file" >&2
        return 1
    fi

    if ! jq -n '{iterations: [], totalDurationMs: 0, struggleIndicators: {repeatedErrors: {}, noProgressIterations: 0, shortIterations: 0}}' > "$HISTORY_FILE"; then
        echo "Error: Failed to initialize history file" >&2
        return 1
    fi
}

update_state() {
    local iteration=$1
    locked_json_update "$STATE_FILE" --argjson iter "$iteration" '.iteration = $iter'
}

clear_state() {
    locked_json_update "$STATE_FILE" '.active = false'
    rm -f "$RALPH_DIR/validator-feedback.md" 2>/dev/null
}

record_iteration() {
    local iteration=$1 duration_ms=$2 exit_code=$3 completion_detected=$4
    local files_modified=$5

    local files_json="[]"
    if [[ -n "$files_modified" ]]; then
        files_json=$(echo "$files_modified" | tr ',' '\n' | jq -R . | jq -s .)
    fi

    locked_json_update "$HISTORY_FILE" \
       --argjson iter "$iteration" \
       --argjson duration "$duration_ms" \
       --argjson exit "$exit_code" \
       --argjson complete "$completion_detected" \
       --argjson files "$files_json" \
       '.iterations += [{iteration: $iter, durationMs: $duration, exitCode: $exit, completionDetected: $complete, filesModified: $files}] | .totalDurationMs += $duration'
}

update_struggle_indicators() {
    local files_changed=$1 duration_ms=$2

    # Combine both updates into a single locked_json_update to reduce lock contention
    # and filesystem operations (previously required 2 lock cycles = ~14 forks)
    locked_json_update "$HISTORY_FILE" \
        --argjson fc "$files_changed" \
        --argjson dur "$duration_ms" \
        'if $fc == 0 then .struggleIndicators.noProgressIterations += 1 else .struggleIndicators.noProgressIterations = 0 end |
         if $dur < 30000 then .struggleIndicators.shortIterations += 1 else .struggleIndicators.shortIterations = 0 end'
}

check_struggle() {
    local no_progress short_iters
    no_progress=$(jq -r '.struggleIndicators.noProgressIterations // 0' "$HISTORY_FILE")
    short_iters=$(jq -r '.struggleIndicators.shortIterations // 0' "$HISTORY_FILE")

    if [[ $no_progress -ge 3 ]] || [[ $short_iters -ge 3 ]]; then
        echo ""
        echo "Potential struggle detected:"
        [[ $no_progress -ge 3 ]] && echo "   - No file changes in $no_progress iterations"
        [[ $short_iters -ge 3 ]] && echo "   - $short_iters very short iterations"
        echo "   Tip: Use 'ralph loop --add-context \"hint\" --session $SESSION_ID'"
    fi
}

check_completion_marker() {
    local output_file=$1
    grep -qF "<promise>${COMPLETION_PROMISE}</promise>" "$output_file"
}

run_validation_agent() {
    local original_prompt=$1
    local impl_output=$2
    local state_file="$RALPH_DIR/state.md"

    local state_content=""
    if [[ -f "$state_file" ]]; then
        state_content=$(cat "$state_file")
    fi

    local validation_prompt
    validation_prompt=$(cat <<EOF
# Completion Validation Request

You are a **validator agent**. Your job is to verify whether the implementation agent has FULLY completed the requested task.

## Original Task Given to Implementation Agent

$original_prompt

## Implementation Agent's State File

\`\`\`markdown
$state_content
\`\`\`

## Your Validation Criteria

1. **Task Completeness**: Does the work satisfy ALL requirements in the original task?
2. **No Remaining Work**: Are there any unchecked items [ ] in the state file that should be done?
3. **Quality Check**: Based on the state file, does the work appear complete and functional?

## Your Response

- If the task is **FULLY COMPLETE**: Output exactly \`<promise>$COMPLETION_PROMISE</promise>\`
- If the task is **NOT COMPLETE**: Explain what remains to be done (do NOT output the promise tag)

Be strict. Only confirm completion if you are confident the entire task was satisfied.
EOF
)

    echo "   Running validation agent..." >&2

    local validator_output
    local validator_exit_code

    if [[ "$AGENT" == "claudecode" ]]; then
        local claude_model
        claude_model=$(tier_to_claude_model)
        validator_output=$(claude -p --model "$claude_model" "$validation_prompt" < /dev/null 2>&1) || true
        validator_exit_code=$?
    else
        local validator_model
        validator_model=$(get_available_model "$TIER")
        if [[ -z "$validator_model" ]]; then
            echo "   Warning: No models available for validation, skipping validation check" >&2
            # Return success to avoid false negatives when models are rate-limited
            return 0
        fi
        validator_output=$(opencode run --model "$validator_model" --agent yolo "$validation_prompt" < /dev/null 2>&1) || true
        validator_exit_code=$?
    fi

    if echo "$validator_output" | grep -qF "<promise>${COMPLETION_PROMISE}</promise>"; then
        echo "   Validator confirmed: COMPLETE" >&2
        return 0
    else
        echo "   Validator says: NOT COMPLETE" >&2

        # Extract the validator's feedback (skip any JSON/metadata, get the explanation)
        local feedback
        feedback=$(echo "$validator_output" | grep -v "^{" | grep -v "^}" | grep -v "^\[" | tail -20)

        if [[ -n "$feedback" ]]; then
            echo "   Feedback: $(echo "$feedback" | head -3)" >&2

            # Save feedback to one-shot file (cleared after next iteration reads it)
            cat > "$RALPH_DIR/validator-feedback.md" <<EOF
## Validator Feedback

The validation agent reviewed your work and found it **incomplete**. Address the following:

$feedback
EOF
            echo "   (Feedback saved for next iteration)" >&2
        fi
        return 1
    fi
}

check_completion() {
    local output_file=$1

    if ! check_completion_marker "$output_file"; then
        return 1
    fi

    case "$COMPLETION_MODE" in
        promise)
            return 0
            ;;
        validate)
            local original_prompt
            original_prompt=$(get_prompt_content)
            run_validation_agent "$original_prompt" ""
            ;;
        *)
            return 0
            ;;
    esac
}

format_duration() {
    local ms=$1
    local secs=$((ms / 1000))
    local mins=$((secs / 60))
    secs=$((secs % 60))
    if [[ $mins -gt 0 ]]; then
        echo "${mins}m ${secs}s"
    else
        echo "${secs}s"
    fi
}

# Cleanup on interrupt
CMD_PID=""
OUTPUT_FILE=""
SNAPSHOT_BEFORE=""
SNAPSHOT_AFTER=""
EFFECTIVE_SANDBOX=""

cleanup() {
    echo ""
    echo "Interrupted - cleaning up..."

    if [[ -n "$CMD_PID" ]] && kill -0 "$CMD_PID" 2>/dev/null; then
        echo "Killing agent process ($CMD_PID)..."
        kill "$CMD_PID" 2>/dev/null
        wait "$CMD_PID" 2>/dev/null || true
    fi

    if [[ "$EFFECTIVE_SANDBOX" == "docker" ]]; then
        echo "Stopping sandbox containers..."
        docker ps -q --filter "ancestor=$CONTAINER_IMAGE" 2>/dev/null | xargs -r docker kill 2>/dev/null || true
    fi

    [[ -n "$SNAPSHOT_BEFORE" ]] && rm -f "$SNAPSHOT_BEFORE"
    [[ -n "$SNAPSHOT_AFTER" ]] && rm -f "$SNAPSHOT_AFTER"
    [[ -n "$TEMP_SANDBOX_CONFIG" ]] && rm -f "$TEMP_SANDBOX_CONFIG"
    [[ -n "${OPENCODE_MCP_CONFIG_FILE:-}" ]] && rm -f "$OPENCODE_MCP_CONFIG_FILE"
    rm -f "$RALPH_DIR/validator-feedback.md" 2>/dev/null
    rm -f "$RALPH_DIR/agent_exit_code.tmp" 2>/dev/null

    clear_state

    # Restore original directory if we changed it
    popd > /dev/null 2>&1 || true

    exit 130
}
trap cleanup INT TERM

# Build project-specific container if requested
if [[ -n "$BUILD_CONTAINER" ]]; then
    DOCKERFILE_PATH=""

    if [[ "$BUILD_CONTAINER" == "auto" ]]; then
        # Auto-detect Dockerfile in order of preference
        for candidate in "$WORKING_DIR/Dockerfile.ralph" "$WORKING_DIR/.ralph/Dockerfile" "$WORKING_DIR/Dockerfile"; do
            if [[ -f "$candidate" ]]; then
                DOCKERFILE_PATH="$candidate"
                break
            fi
        done
        if [[ -z "$DOCKERFILE_PATH" ]]; then
            echo "Error: --build-container specified but no Dockerfile found" >&2
            echo "Searched: Dockerfile.ralph, .ralph/Dockerfile, Dockerfile" >&2
            exit 1
        fi
    else
        DOCKERFILE_PATH="$BUILD_CONTAINER"
        if [[ ! -f "$DOCKERFILE_PATH" ]]; then
            echo "Error: Dockerfile not found: $DOCKERFILE_PATH" >&2
            exit 1
        fi
    fi

    # Generate project-specific image name from directory
    PROJECT_NAME=$(basename "$WORKING_DIR" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-')
    CONTAINER_IMAGE="agent-sandbox-${PROJECT_NAME}:latest"

    echo "Building project container: $CONTAINER_IMAGE"
    echo "Dockerfile: $DOCKERFILE_PATH"

    # Check if Dockerfile extends agent-sandbox, if not create a wrapper
    if grep -q "^FROM agent-sandbox" "$DOCKERFILE_PATH"; then
        # Dockerfile already extends agent-sandbox, build directly
        docker build -f "$DOCKERFILE_PATH" -t "$CONTAINER_IMAGE" "$WORKING_DIR" || {
            echo "Error: Container build failed"
            exit 1
        }
    else
        # Create a temporary Dockerfile that extends agent-sandbox then applies project Dockerfile
        TEMP_DOCKERFILE=$(mktemp)
        cat > "$TEMP_DOCKERFILE" <<DOCKERFILE_EOF
FROM agent-sandbox:latest

# Apply project Dockerfile commands
$(grep -v "^FROM " "$DOCKERFILE_PATH" | grep -v "^#" || true)
DOCKERFILE_EOF

        docker build -f "$TEMP_DOCKERFILE" -t "$CONTAINER_IMAGE" "$WORKING_DIR" || {
            rm -f "$TEMP_DOCKERFILE"
            echo "Error: Container build failed"
            exit 1
        }
        rm -f "$TEMP_DOCKERFILE"
    fi

    echo "Container built: $CONTAINER_IMAGE"
    echo ""
fi

# Determine effective sandbox mode
EFFECTIVE_SANDBOX=$(get_effective_sandbox "$SANDBOX_MODE" "$AGENT")

# Setup sandbox
case "$EFFECTIVE_SANDBOX" in
    docker)
        check_sandbox_setup "$SANDBOX_SCRIPT" || exit 1
        echo "Sandbox: Docker (agent-sandbox)"
        if [[ ${#EXTRA_ALLOW_WRITE[@]} -gt 0 ]]; then
            echo "Extra mounts: ${EXTRA_ALLOW_WRITE[*]}"
        fi
        ;;
    anthropic)
        require_sandbox_config
        if [[ ${#EXTRA_ALLOW_WRITE[@]} -gt 0 ]]; then
            TEMP_SANDBOX_CONFIG=$(create_patched_sandbox_config "${EXTRA_ALLOW_WRITE[@]}")
            ACTIVE_SANDBOX_CONFIG="$TEMP_SANDBOX_CONFIG"
            echo "Sandbox: Anthropic sandbox-runtime (srt)"
            echo "Config:  $SANDBOX_CONFIG (patched)"
            echo "Extra allowWrite: ${EXTRA_ALLOW_WRITE[*]}"
        else
            ACTIVE_SANDBOX_CONFIG="$SANDBOX_CONFIG"
            echo "Sandbox: Anthropic sandbox-runtime (srt)"
            echo "Config:  $SANDBOX_CONFIG"
        fi
        ;;
    none)
        echo "Sandbox: disabled (full system access)"
        ;;
    claude)
        echo "Sandbox: Claude Code built-in"
        ;;
esac

# Check for existing session state (atomic check-and-set via lock)
# Hold lock through entire check-and-set to prevent TOCTOU race
RESUMING=false
if [[ -f "$STATE_FILE" ]]; then
    acquire_lock "$STATE_FILE" || { echo "Error: Could not acquire session lock" >&2; exit 1; }
    active=$(jq -r '.active // false' "$STATE_FILE")
    if [[ "$active" == "true" ]]; then
        release_lock "$STATE_FILE"
        echo "Error: Session '$SESSION_ID' is already active" >&2
        echo "Use --status --session $SESSION_ID to check" >&2
        echo "Or delete $STATE_FILE to reset" >&2
        exit 1
    fi
    # Set active=true while still holding the lock to prevent race condition
    jq '.active = true' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    release_lock "$STATE_FILE"
    RESUMING=true
fi

# Get model
if [[ -n "$MODEL_OVERRIDE" ]]; then
    MODEL="$MODEL_OVERRIDE"
    echo "Session: $SESSION_ID"
    echo "Agent:   $AGENT"
    echo "Model:   $MODEL (explicit)"
elif [[ "$AGENT" == "claudecode" ]]; then
    MODEL=$(tier_to_claude_model)
    echo "Session: $SESSION_ID"
    echo "Agent:   $AGENT"
    echo "Model:   $MODEL ($TIER tier)"
else
    MODEL=$(get_available_model "$TIER") || { echo "Error: No models available"; exit 1; }
    echo "Session: $SESSION_ID"
    echo "Agent:   $AGENT"
    echo "Model:   $MODEL ($TIER tier)"
fi

# Initialize or resume
if [[ "$RESUMING" == "true" ]]; then
    echo "Resuming existing session..."
    # active=true was already set atomically in the check-and-set block above
else
    init_state "$MODEL"
fi

# Change to working directory using pushd to allow restoration on exit
# This is needed because agent processes expect to run in the working directory
pushd "$WORKING_DIR" > /dev/null || { echo "Error: Cannot change to $WORKING_DIR" >&2; exit 1; }

ensure_agents "$WORKING_DIR" >/dev/null 2>&1

echo ""
echo "Ralph Loop"
echo "=========="
echo ""
echo "Session:    $SESSION_ID"
echo "Task:       $(get_prompt_content | head -c 50)..."
echo "Completion: <promise>$COMPLETION_PROMISE</promise>"
if [[ $MAX_ITERATIONS -eq 0 ]]; then
    echo "Iterations: min=$MIN_ITERATIONS, max=infinite"
else
    echo "Iterations: min=$MIN_ITERATIONS, max=$MAX_ITERATIONS"
fi
if [[ $RESET_AFTER -gt 0 ]]; then
    echo "State reset: every $RESET_AFTER iterations"
fi
case "$EFFECTIVE_SANDBOX" in
    docker)    echo "Sandbox:    Docker (agent-sandbox)" ;;
    anthropic) echo "Sandbox:    Anthropic (srt) - network/fs restricted" ;;
    claude)    echo "Sandbox:    Claude Code built-in" ;;
    none)      echo "Sandbox:    none (full system access)" ;;
esac
echo ""

# Pre-flight check - ensure .claude directory exists (never touch .git - it's a file in worktrees)
if [[ "$EFFECTIVE_SANDBOX" != "none" ]]; then
    if [[ ! -d "$WORKING_DIR/.claude" ]]; then
        mkdir -p "$WORKING_DIR/.claude"
    fi
fi

echo "Starting loop... (Ctrl+C to stop)"
echo "=================================="

# Main loop
iteration=1
log_seq=1
consecutive_quick_failures=0
# Absolute maximum for infinite mode to prevent runaway execution
ABSOLUTE_MAX_ITERATIONS=1000
while [[ $MAX_ITERATIONS -eq 0 ]] || [[ $iteration -le $MAX_ITERATIONS ]]; do
    echo ""
    if [[ $MAX_ITERATIONS -eq 0 ]]; then
        echo "Iteration $iteration (infinite mode)"
        # Warn periodically about unbounded execution
        if (( iteration % 10 == 0 )); then
            echo "Warning: Session has run $iteration iterations with no max limit set" >&2
        fi
        # Hard limit for infinite mode to prevent runaway execution
        if [[ $iteration -ge $ABSOLUTE_MAX_ITERATIONS ]]; then
            echo "Error: Absolute maximum of $ABSOLUTE_MAX_ITERATIONS iterations reached in infinite mode" >&2
            echo "This safety limit prevents runaway execution. Use --max to set explicit limit." >&2
            clear_state
            exit 1
        fi
    else
        echo "Iteration $iteration / $MAX_ITERATIONS"
    fi
    echo "----------------------------------"

    if [[ $RESET_AFTER -gt 0 ]] && [[ $iteration -gt 1 ]] && [[ $((iteration % RESET_AFTER)) -eq 1 ]]; then
        echo "Resetting agent state (--reset-after $RESET_AFTER)"
        # Delete agent's state file (tasks, discoveries, blockers)
        rm -f "$RALPH_DIR/state.md"
        # Reset history (struggle indicators, iteration timings)
        jq -n '{iterations: [], totalDurationMs: 0, struggleIndicators: {repeatedErrors: {}, noProgressIterations: 0, shortIterations: 0}}' > "$HISTORY_FILE"
    fi

    SNAPSHOT_BEFORE=$(mktemp)
    capture_file_snapshot "$SNAPSHOT_BEFORE"

    full_prompt=$(build_mission_prompt "$iteration")

    start_time=$(date +%s)
    OUTPUT_FILE="$RALPH_DIR/logs/iteration-${log_seq}.log"

    STALLED=false

    # Build command as array for safe expansion
    BASE_CMD=()
    if [[ "$AGENT" == "claudecode" ]]; then
        claude_model="$MODEL"
        if [[ -z "$MODEL_OVERRIDE" ]]; then
            claude_model=$(tier_to_claude_model)
        fi
        BASE_CMD=(claude -p --verbose --output-format stream-json --model "$claude_model")
        if [[ "$EFFECTIVE_SANDBOX" == "none" ]] || [[ "$EFFECTIVE_SANDBOX" == "docker" ]]; then
            BASE_CMD+=(--dangerously-skip-permissions)
        fi
        if [[ -n "$MCP_CONFIG" ]]; then
            if [[ "$EFFECTIVE_SANDBOX" == "docker" ]]; then
                BASE_CMD+=(--mcp-config /workspace/.mcp.json)
            else
                BASE_CMD+=(--mcp-config "$MCP_CONFIG")
            fi
        fi
    else
        BASE_CMD=(opencode run --model "$MODEL" --agent yolo --format json)
    fi

    # Handle MCP config for OpenCode (convert from Claude format)
    OPENCODE_MCP_CONFIG_FILE=""
    if [[ "$AGENT" == "opencode" ]] && [[ -n "$MCP_CONFIG" ]]; then
        source "$RALPH_ROOT/lib/mcp-convert.sh"
        OPENCODE_MCP_CONFIG_FILE=$(mktemp -t "opencode-mcp-XXXXXX.json")
        chmod 600 "$OPENCODE_MCP_CONFIG_FILE"
        create_opencode_mcp_config "$MCP_CONFIG" "$OPENCODE_MCP_CONFIG_FILE"
        echo "Converted MCP config for OpenCode: $OPENCODE_MCP_CONFIG_FILE"
    fi

    # Formatters for consistent output display
    STREAM_FORMATTER="$RALPH_ROOT/lib/stream-formatter.sh"
    OC_FORMATTER="$RALPH_ROOT/lib/oc-formatter.sh"

    # Display filters: route to formatter or suppress in brief mode
    if [[ "$OUTPUT_MODE" == "brief" ]]; then
        display_cc() { cat > /dev/null; }
        display_oc() { cat > /dev/null; }
    else
        display_cc() { "$STREAM_FORMATTER"; }
        display_oc() { "$OC_FORMATTER"; }
    fi

    # Export verbose flag for formatters
    export RALPH_VERBOSE="$VERBOSE"

    # Build docker extra args as arrays
    DOCKER_EXTRA_ARGS=()
    if [[ ${#EXTRA_ALLOW_WRITE[@]} -gt 0 ]]; then
        for path in "${EXTRA_ALLOW_WRITE[@]}"; do
            expanded_path="${path/#\~/$HOME}"
            DOCKER_EXTRA_ARGS+=(--extra-mount "$expanded_path")
        done
    fi
    if [[ -n "$MCP_CONFIG" ]]; then
        DOCKER_EXTRA_ARGS+=(--mcp-config "$MCP_CONFIG")
    fi
    if [[ -n "$OPENCODE_MCP_CONFIG_FILE" ]] && [[ -f "$OPENCODE_MCP_CONFIG_FILE" ]]; then
        DOCKER_EXTRA_ARGS+=(--opencode-mcp-config "$OPENCODE_MCP_CONFIG_FILE")
    fi

    # Use a temp file to capture the agent's actual exit code
    AGENT_EXIT_CODE_FILE="$RALPH_DIR/agent_exit_code.tmp"

    # For OpenCode with Anthropic sandbox: write prompt to file so srt -c can read it
    # without shell quoting issues (OpenCode needs the prompt as a CLI arg, not stdin)
    ITER_PROMPT_FILE=""
    if [[ "$AGENT" == "opencode" ]] && [[ "$EFFECTIVE_SANDBOX" == "anthropic" ]]; then
        ITER_PROMPT_FILE="$RALPH_DIR/prompt-iter-${iteration}.txt"
        printf '%s' "$full_prompt" > "$ITER_PROMPT_FILE"
    fi

    case "$EFFECTIVE_SANDBOX" in
        docker)
            if [[ "$AGENT" == "claudecode" ]]; then
                { "$SANDBOX_SCRIPT" --dir "$WORKING_DIR" --image "$CONTAINER_IMAGE" ${DOCKER_EXTRA_ARGS[@]+"${DOCKER_EXTRA_ARGS[@]}"} "${BASE_CMD[@]}" "$full_prompt" < /dev/null 2>&1; echo $? > "$AGENT_EXIT_CODE_FILE"; } | tee "$OUTPUT_FILE" | display_cc &
            else
                { "$SANDBOX_SCRIPT" --dir "$WORKING_DIR" --image "$CONTAINER_IMAGE" ${DOCKER_EXTRA_ARGS[@]+"${DOCKER_EXTRA_ARGS[@]}"} "${BASE_CMD[@]}" "$full_prompt" < /dev/null 2>&1; echo $? > "$AGENT_EXIT_CODE_FILE"; } | tee "$OUTPUT_FILE" | display_oc &
            fi
            ;;
        anthropic)
            if [[ "$AGENT" == "claudecode" ]]; then
                { echo "$full_prompt" | srt --settings "$ACTIVE_SANDBOX_CONFIG" -- "${BASE_CMD[@]}" 2>&1; echo $? > "$AGENT_EXIT_CODE_FILE"; } | tee "$OUTPUT_FILE" | display_cc &
            else
                # Use srt -c to read prompt from file, avoiding shell quoting issues
                { srt --settings "$ACTIVE_SANDBOX_CONFIG" -c "${BASE_CMD[*]} \"\$(cat '$ITER_PROMPT_FILE')\"" < /dev/null 2>&1; echo $? > "$AGENT_EXIT_CODE_FILE"; } | tee "$OUTPUT_FILE" | display_oc &
            fi
            ;;
        claude|none)
            if [[ "$AGENT" == "claudecode" ]]; then
                { echo "$full_prompt" | "${BASE_CMD[@]}" 2>&1; echo $? > "$AGENT_EXIT_CODE_FILE"; } | tee "$OUTPUT_FILE" | display_cc &
            else
                { "${BASE_CMD[@]}" "$full_prompt" < /dev/null 2>&1; echo $? > "$AGENT_EXIT_CODE_FILE"; } | tee "$OUTPUT_FILE" | display_oc &
            fi
            ;;
    esac
    CMD_PID=$!

    last_size=0
    stall_start=$(date +%s)

    while kill -0 $CMD_PID 2>/dev/null; do
        sleep 5

        current_size=$(get_file_size "$OUTPUT_FILE")
        now=$(date +%s)

        if [[ "$current_size" != "$last_size" ]]; then
            last_size=$current_size
            stall_start=$now
        else
            stall_duration=$((now - stall_start))
            if [[ $stall_duration -ge $STALL_TIMEOUT ]]; then
                echo ""
                echo "Agent stalled (no output for ${STALL_TIMEOUT}s) - killing process"
                # Kill the entire pipeline process tree to prevent wait from hanging.
                # CMD_PID is the formatter (last in pipeline), but the subshell running
                # srt/agent and tee are siblings that must also die. Walk the full
                # descendant tree of this script's children (only the pipeline is backgrounded).
                pids_to_kill=""
                _queue=$(pgrep -P $$ 2>/dev/null || true)
                while [[ -n "$_queue" ]]; do
                    _next_queue=""
                    for pid in $_queue; do
                        pids_to_kill="$pids_to_kill $pid"
                        _children=$(pgrep -P "$pid" 2>/dev/null || true)
                        [[ -n "$_children" ]] && _next_queue="$_next_queue $_children"
                    done
                    _queue="$_next_queue"
                done
                if [[ -n "$pids_to_kill" ]]; then
                    kill $pids_to_kill 2>/dev/null || true
                fi
                if [[ "$EFFECTIVE_SANDBOX" == "docker" ]]; then
                    docker ps -q --filter "ancestor=$CONTAINER_IMAGE" 2>/dev/null | xargs -r docker kill 2>/dev/null || true
                fi
                wait $CMD_PID 2>/dev/null || true
                STALLED=true
                break
            fi
        fi
    done

    if [[ "$STALLED" == "false" ]]; then
        # Use || true instead of set +e/set -e to avoid creating error-swallowing gaps
        wait $CMD_PID || true
        # Read the agent's actual exit code from temp file
        if [[ -f "$AGENT_EXIT_CODE_FILE" ]]; then
            exit_code=$(cat "$AGENT_EXIT_CODE_FILE")
            rm -f "$AGENT_EXIT_CODE_FILE"
        else
            # Fallback: no exit code file means we couldn't capture it
            exit_code=1
        fi
    else
        exit_code=124
        rm -f "$AGENT_EXIT_CODE_FILE" 2>/dev/null
    fi
    CMD_PID=""

    end_time=$(date +%s)
    duration_ms=$(( (end_time - start_time) * 1000 ))

    SNAPSHOT_AFTER=$(mktemp)
    capture_file_snapshot "$SNAPSHOT_AFTER"

    modified_files=$(get_modified_files "$SNAPSHOT_BEFORE" "$SNAPSHOT_AFTER" | tr '\n' ',' | sed 's/,$//')
    if [[ -z "$modified_files" ]]; then
        files_count=0
    else
        files_count=$(echo "$modified_files" | tr ',' '\n' | grep -c . 2>/dev/null || echo 0)
    fi
    rm -f "$SNAPSHOT_BEFORE" "$SNAPSHOT_AFTER"
    SNAPSHOT_BEFORE=""
    SNAPSHOT_AFTER=""

    completion_detected=false
    validation_rejected=false
    if check_completion "$OUTPUT_FILE"; then
        completion_detected=true
    elif [[ -f "$RALPH_DIR/validator-feedback.md" ]]; then
        validation_rejected=true
    fi

    record_iteration "$iteration" "$duration_ms" "$exit_code" "$completion_detected" "$modified_files"
    update_struggle_indicators "$files_count" "$duration_ms"

    ITERATION_COST=0
    TOTAL_COST=0
    BUDGET_EXCEEDED=false
    if [[ "$AGENT" == "opencode" ]]; then
        OPENCODE_SESSION=$(get_latest_opencode_session)

        if [[ -n "$OPENCODE_SESSION" ]]; then
            record_opencode_session "$SESSION_ID" "$WORKING_DIR" "$OPENCODE_SESSION" "$iteration"
            ITERATION_COST=$(get_opencode_session_cost "$OPENCODE_SESSION")
            TOTAL_COST=$(get_ralph_session_cost "$SESSION_ID" "$WORKING_DIR")
        fi
    elif [[ "$AGENT" == "claudecode" ]] && [[ -f "$OUTPUT_FILE" ]]; then
        ITERATION_COST=$(get_claude_session_cost "$OUTPUT_FILE")
        record_claude_session "$SESSION_ID" "$WORKING_DIR" "$iteration" "$ITERATION_COST"
        TOTAL_COST=$(get_ralph_claude_session_cost "$SESSION_ID" "$WORKING_DIR")
    fi

    if [[ -n "$BUDGET_LIMIT" ]] && [[ "$TOTAL_COST" != "0" ]]; then
        BUDGET_STATUS=$(check_budget "$TOTAL_COST" "$BUDGET_LIMIT")
        if [[ "$BUDGET_STATUS" == "exceeded" ]]; then
            BUDGET_EXCEEDED=true
        fi
    fi

    echo ""
    echo "Iteration Summary"
    echo "-----------------"
    echo "Duration:   $(format_duration $duration_ms)"
    echo "Exit code:  $exit_code"
    echo "Files:      $files_count modified"
    if [[ $files_count -gt 0 ]] && [[ $files_count -le 10 ]] && [[ -n "$modified_files" ]]; then
        echo "$modified_files" | tr ',' '\n' | while IFS= read -r f; do
            [[ -n "$f" ]] && echo "              $f"
        done
    fi
    [[ "$STALLED" == "true" ]] && echo "Status:     STALLED (no output for ${STALL_TIMEOUT}s)"

    if [[ "$completion_detected" == "true" ]]; then
        echo "Completion: detected (mode=$COMPLETION_MODE)"
    elif [[ "$validation_rejected" == "true" ]]; then
        echo "Completion: marker found, but validator rejected"
    else
        echo "Completion: not detected"
    fi

    if [[ "$AGENT" == "opencode" ]] && [[ -n "${OPENCODE_SESSION:-}" ]]; then
        TOKENS_JSON=$(get_opencode_session_tokens "$OPENCODE_SESSION")
        display_token_usage "$TOKENS_JSON"
        display_iteration_cost "$ITERATION_COST" "$TOTAL_COST" "$BUDGET_LIMIT"
    elif [[ "$AGENT" == "claudecode" ]] && [[ "$ITERATION_COST" != "0" ]]; then
        display_iteration_cost "$ITERATION_COST" "$TOTAL_COST" "$BUDGET_LIMIT"
    fi

    if [[ "$BUDGET_EXCEEDED" == "true" ]]; then
        display_budget_exceeded "$TOTAL_COST" "$BUDGET_LIMIT"
        echo "Session stopped due to budget limit"

        if [[ "$AGENT" == "opencode" ]]; then
            save_cost_summary "$SESSION_ID" "$WORKING_DIR"
        fi
        record_to_ledger "$SESSION_ID" "$PROMPT" "$TOTAL_COST" "$WORKING_DIR" "$MODEL"

        clear_state
        clear_context
        exit 1
    fi

    if [[ "$completion_detected" == "true" ]]; then
        if [[ $iteration -lt $MIN_ITERATIONS ]]; then
            echo ""
            echo "Completion detected, but min iterations ($MIN_ITERATIONS) not reached"
            echo "   Continuing..."
        else
            echo ""
            echo "Task completed in $iteration iteration(s)!"
            total_time=$(jq -r '.totalDurationMs // 0' "$HISTORY_FILE")
            echo "Total time: $(format_duration "$total_time")"

            if [[ "$TOTAL_COST" != "0" ]]; then
                printf "Total cost: \$%.4f" "$TOTAL_COST"
                if [[ -n "$BUDGET_LIMIT" ]]; then
                    printf " (budget: \$%.2f)" "$BUDGET_LIMIT"
                fi
                echo ""
            fi

            echo "Session:    $SESSION_ID"

            if [[ $files_count -gt 0 ]] && [[ -n "$modified_files" ]]; then
                echo ""
                echo "Files modified (final iteration):"
                echo "$modified_files" | tr ',' '\n' | while IFS= read -r f; do
                    [[ -n "$f" ]] && echo "  $f"
                done
            fi

            if [[ "$AGENT" == "opencode" ]]; then
                save_cost_summary "$SESSION_ID" "$WORKING_DIR"
            fi
            if [[ "$TOTAL_COST" != "0" ]]; then
                record_to_ledger "$SESSION_ID" "$PROMPT" "$TOTAL_COST" "$WORKING_DIR" "$MODEL"
            fi

            clear_state
            clear_context
            exit 0
        fi
    fi

    if [[ "$STALLED" == "true" ]]; then
        echo "Marking model as temporarily unavailable..."
        mark_rate_limited "$MODEL"
        NEW_MODEL=$(get_available_model "$TIER") || { echo "Error: No models available"; clear_state; exit 1; }
        if [[ "$NEW_MODEL" != "$MODEL" ]]; then
            MODEL="$NEW_MODEL"
            echo "Switched to: $MODEL"
        else
            echo "No alternative model available, will retry with same model next iteration"
        fi
        continue
    fi

    # Skip rate limit check if agent completed successfully or validation rejected
    # Stderr noise from the agent process (2>&1) can contain rate limit keywords
    # that trigger false positives when the iteration actually succeeded
    output_tail=$(tail -50 "$OUTPUT_FILE" 2>/dev/null || echo "")
    output_size=$(wc -c < "$OUTPUT_FILE" 2>/dev/null || echo "0")
    output_size="${output_size// /}"  # macOS wc pads with spaces
    OUTPUT_FILE=""

    skip_increment=false
    if [[ "$completion_detected" != "true" ]] && [[ "$validation_rejected" != "true" ]]; then
        if is_rate_limit_error "$output_tail" "$CONFIG"; then
            echo "Rate limit detected, marking model and retrying..."
            mark_rate_limited "$MODEL"
            MODEL=$(get_available_model "$TIER") || { echo "Error: No models available"; clear_state; exit 1; }
            echo "Switched to: $MODEL"
            skip_increment=true
        elif [[ $output_size -lt 50 ]] && [[ $duration_ms -lt 30000 ]]; then
            echo "Agent produced no output (possible rate limit or crash)"
            mark_model_rate_limited "$MODEL" 120 "$RATE_LIMITS"
            NEW_MODEL=$(get_available_model "$TIER") || true
            if [[ -n "${NEW_MODEL:-}" ]] && [[ "$NEW_MODEL" != "$MODEL" ]]; then
                MODEL="$NEW_MODEL"
                echo "Switched to: $MODEL"
            else
                echo "No alternative model available, will retry after backoff"
            fi
            skip_increment=true
        fi
    fi

    check_struggle

    if [[ -f "$CONTEXT_FILE" ]]; then
        echo "Context consumed"
        clear_context
    fi

    ((log_seq++))
    if [[ "$skip_increment" != "true" ]]; then
        ((iteration++))
        update_state "$iteration"
    fi

    # Exponential backoff on consecutive quick failures (< 30s with no completion)
    if [[ "$completion_detected" != "true" ]] && [[ $duration_ms -lt 30000 ]]; then
        consecutive_quick_failures=$((consecutive_quick_failures + 1))
        backoff=$((2 ** consecutive_quick_failures))
        if [[ $backoff -gt 60 ]]; then backoff=60; fi
        echo "Quick failure (${duration_ms}ms), backing off ${backoff}s..."
        sleep $backoff
    else
        consecutive_quick_failures=0
        sleep 2
    fi
done

echo ""
echo "Max iterations ($MAX_ITERATIONS) reached"
total_time=$(jq -r '.totalDurationMs // 0' "$HISTORY_FILE")
echo "Total time: $(format_duration "$total_time")"

FINAL_TOTAL_COST=0
if [[ "$AGENT" == "opencode" ]]; then
    FINAL_TOTAL_COST=$(get_ralph_session_cost "$SESSION_ID" "$WORKING_DIR")
    save_cost_summary "$SESSION_ID" "$WORKING_DIR"
elif [[ "$AGENT" == "claudecode" ]]; then
    FINAL_TOTAL_COST=$(get_ralph_claude_session_cost "$SESSION_ID" "$WORKING_DIR")
fi

if [[ "$FINAL_TOTAL_COST" != "0" ]]; then
    printf "Total cost: \$%.4f" "$FINAL_TOTAL_COST"
    if [[ -n "$BUDGET_LIMIT" ]]; then
        printf " (budget: \$%.2f)" "$BUDGET_LIMIT"
    fi
    echo ""

    record_to_ledger "$SESSION_ID" "$PROMPT" "$FINAL_TOTAL_COST" "$WORKING_DIR" "$MODEL"
fi

clear_state
exit 1
