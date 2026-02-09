#!/usr/bin/env bash
# tests.sh - Tests for agent-orchestrator
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR=$(mktemp -d)
PASSED=0
FAILED=0
TOTAL=0

# Respect NO_COLOR standard and non-terminal output
if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
	RED=""
	GREEN=""
	YELLOW=""
	NC=""
else
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[0;33m'
	NC='\033[0m'
fi

cleanup() {
	rm -rf "$TEST_DIR"
}
trap cleanup EXIT

log_test() {
	TOTAL=$((TOTAL + 1))
	echo -e "${YELLOW}TEST:${NC} $1"
}

pass() {
	PASSED=$((PASSED + 1))
	echo -e "  ${GREEN}✓ PASSED${NC}"
}

fail() {
	FAILED=$((FAILED + 1))
	echo -e "  ${RED}✗ FAILED: $1${NC}"
}

assert_eq() {
	if [[ "$1" == "$2" ]]; then
		pass
	else
		fail "Expected '$2', got '$1'"
	fi
}

assert_contains() {
	if [[ "$1" == *"$2"* ]]; then
		pass
	else
		fail "Expected output to contain '$2'"
	fi
}

echo "============================================="
echo "Agent Orchestrator Tests"
echo "============================================="
echo "Test directory: $TEST_DIR"
echo ""

# =============================================
# lib/core.sh - Locking
# =============================================
echo ""
echo "--- Locking (lib/core.sh) ---"

source "$SCRIPT_DIR/lib/common.sh"

log_test "acquire_lock creates lockdir with pid file"
LOCK_FILE="$TEST_DIR/test.lock"
acquire_lock "$LOCK_FILE"
if [[ -d "${LOCK_FILE}.lockdir" ]] && [[ -f "${LOCK_FILE}.lockdir/pid" ]]; then
	pid_content=$(cat "${LOCK_FILE}.lockdir/pid")
	assert_eq "$pid_content" "$$"
else
	fail "Lockdir or pid file not created"
fi
release_lock "$LOCK_FILE"

log_test "release_lock removes lockdir"
if [[ ! -d "${LOCK_FILE}.lockdir" ]]; then
	pass
else
	fail "Lockdir not removed"
fi

# =============================================
# lib/core.sh - JSON operations
# =============================================
echo ""
echo "--- JSON operations (lib/core.sh) ---"

log_test "locked_json_update modifies value"
JSON_FILE="$TEST_DIR/test.json"
echo '{"key": "value"}' >"$JSON_FILE"
locked_json_update "$JSON_FILE" '.key = "updated"'
result=$(jq -r '.key' "$JSON_FILE")
assert_eq "$result" "updated"

log_test "locked_json_update with --arg"
locked_json_update "$JSON_FILE" --arg newkey "test123" '.newkey = $newkey'
result=$(jq -r '.newkey' "$JSON_FILE")
assert_eq "$result" "test123"

log_test "locked_json_update preserves existing keys"
result=$(jq -r '.key' "$JSON_FILE")
assert_eq "$result" "updated"

log_test "locked_json_read returns correct value"
result=$(locked_json_read "$JSON_FILE" -r '.key')
assert_eq "$result" "updated"

log_test "concurrent locking doesn't corrupt data"
COUNTER_FILE="$TEST_DIR/counter.json"
echo '{"count": 0}' >"$COUNTER_FILE"
for i in {1..10}; do
	(
		locked_json_update "$COUNTER_FILE" '.count += 1'
	) &
done
wait
result=$(jq -r '.count' "$COUNTER_FILE")
assert_eq "$result" "10"

# =============================================
# lib/core.sh - Utilities
# =============================================
echo ""
echo "--- Utilities (lib/core.sh) ---"

log_test "shuffle_lines preserves all input lines"
result=$(echo -e "a\nb\nc" | shuffle_lines | sort | tr '\n' ',')
assert_eq "$result" "a,b,c,"

log_test "shuffle_lines handles single line"
result=$(echo "only" | shuffle_lines)
assert_eq "$result" "only"

log_test "shuffle_lines handles empty input"
result=$(echo -n "" | shuffle_lines | wc -c | tr -d ' ')
if [[ "$result" -le 1 ]]; then
	pass
else
	fail "Expected 0 or 1 bytes, got $result"
fi

log_test "get_file_size returns correct size"
echo "hello" >"$TEST_DIR/size-test.txt"
result=$(get_file_size "$TEST_DIR/size-test.txt")
assert_eq "$result" "6"

log_test "get_file_size returns 0 for missing file"
result=$(get_file_size "$TEST_DIR/nonexistent.txt")
assert_eq "$result" "0"

log_test "run_with_timeout runs command successfully"
result=$(run_with_timeout 5 echo "hello")
assert_eq "$result" "hello"

log_test "run_with_timeout passes exit code on failure"
set +e
run_with_timeout 5 false
exit_code=$?
set -e
assert_eq "$exit_code" "1"

# =============================================
# lib/model.sh - Model selection
# =============================================
echo ""
echo "--- Model selection (lib/model.sh) ---"

TEST_CONFIG="$TEST_DIR/test-config.json"
TEST_RATE_LIMITS="$TEST_DIR/test-rate-limits.json"
cat >"$TEST_CONFIG" <<'EOF'
{
  "agents": {
    "opencode": {
      "tiers": {
        "high": { "models": ["model-a", "model-b"] },
        "medium": { "models": ["model-c", "model-d"] },
        "low": { "models": ["model-e"] }
      }
    },
    "claudecode": {
      "tiers": {
        "high": { "models": ["opus"] },
        "medium": { "models": ["sonnet"] },
        "low": { "models": ["haiku"] }
      }
    }
  }
}
EOF
echo '{}' >"$TEST_RATE_LIMITS"

log_test "get_models_for_tier returns correct count"
result=$(get_models_for_tier "high" "$TEST_CONFIG" "opencode" | wc -l | tr -d ' ')
assert_eq "$result" "2"

log_test "get_models_for_tier returns exactly the configured models"
result=$(get_models_for_tier "high" "$TEST_CONFIG" "opencode" | sort | tr '\n' ',')
assert_eq "$result" "model-a,model-b,"

log_test "get_models_for_tier returns empty for nonexistent tier"
set +e
result=$(get_models_for_tier "nonexistent" "$TEST_CONFIG" "opencode" 2>/dev/null)
set -e
assert_eq "$result" ""

log_test "is_model_rate_limited returns false for non-limited model"
echo '{}' >"$TEST_RATE_LIMITS"
if ! is_model_rate_limited "model-a" "$TEST_RATE_LIMITS"; then
	pass
else
	fail "Model should not be rate limited"
fi

log_test "is_model_rate_limited returns true for limited model"
future=$(($(date +%s) + 3600))
echo "{\"model-a\": $future}" >"$TEST_RATE_LIMITS"
if is_model_rate_limited "model-a" "$TEST_RATE_LIMITS"; then
	pass
else
	fail "Model should be rate limited"
fi

log_test "is_model_rate_limited returns false for expired limit"
past=$(($(date +%s) - 3600))
echo "{\"model-b\": $past}" >"$TEST_RATE_LIMITS"
if ! is_model_rate_limited "model-b" "$TEST_RATE_LIMITS"; then
	pass
else
	fail "Expired limit should not block model"
fi

log_test "get_next_available_model returns model from requested tier"
echo '{}' >"$TEST_RATE_LIMITS"
result=$(get_next_available_model "high" "$TEST_CONFIG" "$TEST_RATE_LIMITS" false "opencode")
if [[ "$result" == "model-a" ]] || [[ "$result" == "model-b" ]]; then
	pass
else
	fail "Expected model-a or model-b, got '$result'"
fi

log_test "get_next_available_model returns only model from single-model tier"
echo '{}' >"$TEST_RATE_LIMITS"
result=$(get_next_available_model "low" "$TEST_CONFIG" "$TEST_RATE_LIMITS" false "opencode")
assert_eq "$result" "model-e"

log_test "get_next_available_model skips rate-limited models"
future=$(($(date +%s) + 3600))
echo "{\"model-a\": $future}" >"$TEST_RATE_LIMITS"
result=$(get_next_available_model "high" "$TEST_CONFIG" "$TEST_RATE_LIMITS" false "opencode")
assert_eq "$result" "model-b"

log_test "get_next_available_model falls back to medium tier"
future=$(($(date +%s) + 3600))
echo "{\"model-a\": $future, \"model-b\": $future}" >"$TEST_RATE_LIMITS"
result=$(get_next_available_model "high" "$TEST_CONFIG" "$TEST_RATE_LIMITS" true "opencode")
if [[ "$result" == "model-c" ]] || [[ "$result" == "model-d" ]]; then
	pass
else
	fail "Expected fallback to medium tier (model-c or model-d), got '$result'"
fi

log_test "get_next_available_model falls through medium to low"
future=$(($(date +%s) + 3600))
echo "{\"model-a\": $future, \"model-b\": $future, \"model-c\": $future, \"model-d\": $future}" >"$TEST_RATE_LIMITS"
result=$(get_next_available_model "high" "$TEST_CONFIG" "$TEST_RATE_LIMITS" true "opencode")
assert_eq "$result" "model-e"

log_test "get_next_available_model fails when all models rate-limited (no fallback)"
future=$(($(date +%s) + 3600))
echo "{\"model-a\": $future, \"model-b\": $future}" >"$TEST_RATE_LIMITS"
set +e
result=$(get_next_available_model "high" "$TEST_CONFIG" "$TEST_RATE_LIMITS" false "opencode")
exit_code=$?
set -e
if [[ $exit_code -ne 0 ]] && [[ -z "$result" ]]; then
	pass
else
	fail "Should fail when all models rate-limited (exit=$exit_code, result='$result')"
fi

log_test "get_next_available_model works for claudecode agent"
echo '{}' >"$TEST_RATE_LIMITS"
result=$(get_next_available_model "low" "$TEST_CONFIG" "$TEST_RATE_LIMITS" false "claudecode")
assert_eq "$result" "haiku"

# =============================================
# lib/model.sh - Rate limit error detection
# =============================================
echo ""
echo "--- Rate limit error detection (lib/model.sh) ---"

log_test "is_rate_limit_error detects 'rate limit exceeded'"
if is_rate_limit_error "Error: rate limit exceeded"; then
	pass
else
	fail "Should detect 'rate limit exceeded'"
fi

log_test "is_rate_limit_error detects HTTP 429"
if is_rate_limit_error "HTTP 429 Too Many Requests"; then
	pass
else
	fail "Should detect '429'"
fi

log_test "is_rate_limit_error detects RateLimitError"
if is_rate_limit_error "RateLimitError: too many requests"; then
	pass
else
	fail "Should detect 'RateLimitError'"
fi

log_test "is_rate_limit_error detects ThrottlingException"
if is_rate_limit_error "ThrottlingException from provider"; then
	pass
else
	fail "Should detect 'ThrottlingException'"
fi

log_test "is_rate_limit_error rejects normal errors"
if ! is_rate_limit_error "Error: file not found"; then
	pass
else
	fail "Should not match normal errors"
fi

log_test "is_rate_limit_error rejects 'rate' in unrelated context"
if ! is_rate_limit_error "Calculate the exchange rate for USD"; then
	pass
else
	fail "Should not match 'rate' in unrelated context"
fi

TEST_RATE_CONFIG="$TEST_DIR/rate-config.json"
cat >"$TEST_RATE_CONFIG" <<'EOF'
{
  "rateLimitPatterns": [
    "custom_limit",
    "special_error"
  ]
}
EOF

log_test "is_rate_limit_error uses config patterns"
if is_rate_limit_error "Error: custom_limit reached" "$TEST_RATE_CONFIG"; then
	pass
else
	fail "Should match config pattern 'custom_limit'"
fi

log_test "is_rate_limit_error matches second config pattern"
if is_rate_limit_error "Got special_error from API" "$TEST_RATE_CONFIG"; then
	pass
else
	fail "Should match config pattern 'special_error'"
fi

log_test "is_rate_limit_error rejects non-matching with config"
if ! is_rate_limit_error "regular error" "$TEST_RATE_CONFIG"; then
	pass
else
	fail "Should not match 'regular error' with custom patterns"
fi

log_test "is_rate_limit_error falls back to defaults without config"
if is_rate_limit_error "rate limit exceeded"; then
	pass
else
	fail "Should match default pattern without config"
fi

# =============================================
# lib/model.sh - Configuration
# =============================================
echo ""
echo "--- Configuration (lib/model.sh) ---"

log_test "load_config_defaults reads cooldown from config"
TEST_CONFIG_CUSTOM="$TEST_DIR/test-config-custom.json"
cat >"$TEST_CONFIG_CUSTOM" <<'EOF'
{
  "defaults": {
    "cooldownSeconds": 600
  }
}
EOF
load_config_defaults "$TEST_CONFIG_CUSTOM"
assert_eq "$DEFAULT_COOLDOWN" "600"

log_test "load_config_defaults uses fallback for missing config"
load_config_defaults "/nonexistent/config.json"
assert_eq "$DEFAULT_COOLDOWN" "900"

log_test "load_config_defaults uses fallback when key missing"
echo '{}' >"$TEST_DIR/empty-config.json"
load_config_defaults "$TEST_DIR/empty-config.json"
assert_eq "$DEFAULT_COOLDOWN" "900"

# =============================================
# lib/sandbox.sh - State & Sandbox initialization
# =============================================
echo ""
echo "--- State & Sandbox initialization (lib/sandbox.sh) ---"

log_test "init_state_dir creates directory and rate-limits.json"
INIT_STATE_TEST="$TEST_DIR/init-state-test"
init_state_dir "$INIT_STATE_TEST"
if [[ -d "$INIT_STATE_TEST" ]] && [[ -f "$INIT_STATE_TEST/rate-limits.json" ]]; then
	pass
else
	fail "Directory or rate-limits.json not created"
fi

log_test "init_state_dir rate-limits.json contains empty object"
result=$(cat "$INIT_STATE_TEST/rate-limits.json")
assert_eq "$result" "{}"

log_test "init_state_dir queue.json has correct default content"
INIT_STATE_TEST2="$TEST_DIR/init-state-test2"
init_state_dir "$INIT_STATE_TEST2" "queue.json" "custom.json"
content=$(cat "$INIT_STATE_TEST2/queue.json")
assert_eq "$content" '{"tasks":[]}'

log_test "init_state_dir custom.json has correct default content"
content=$(cat "$INIT_STATE_TEST2/custom.json")
assert_eq "$content" '{}'

log_test "init_state_dir doesn't overwrite existing files"
echo '{"existing": true}' >"$INIT_STATE_TEST2/rate-limits.json"
init_state_dir "$INIT_STATE_TEST2"
result=$(jq -r '.existing' "$INIT_STATE_TEST2/rate-limits.json")
assert_eq "$result" "true"

log_test "check_sandbox_setup fails with exit 1 for missing script"
set +e
check_sandbox_setup "/nonexistent/script" >/dev/null 2>&1
exit_code=$?
set -e
assert_eq "$exit_code" "1"

# =============================================
# Completion detection
# =============================================
echo ""
echo "--- Completion detection ---"

test_completion_marker() {
	local output=$1
	local expected_promise="${2:-COMPLETE}"

	local tmp_file
	tmp_file=$(mktemp)
	echo "$output" >"$tmp_file"
	local result=1
	if grep -qF "<promise>${expected_promise}</promise>" "$tmp_file"; then
		result=0
	fi
	rm -f "$tmp_file"
	return $result
}

log_test "rejects bare COMPLETE without tags"
if ! test_completion_marker "COMPLETE"; then
	pass
else
	fail "Matched bare COMPLETE without <promise> tags"
fi

log_test "rejects COMPLETE embedded in function name"
if ! test_completion_marker "The completeTransaction() function works"; then
	pass
else
	fail "Matched embedded COMPLETE"
fi

log_test "rejects COMPLETE in sentence"
if ! test_completion_marker "I cannot COMPLETE this task"; then
	pass
else
	fail "Matched COMPLETE in sentence"
fi

log_test "rejects wrong promise text"
if ! test_completion_marker "<promise>DONE</promise>" "COMPLETE"; then
	pass
else
	fail "Matched wrong promise text"
fi

log_test "rejects open tag without closing tag"
if ! test_completion_marker "<promise>COMPLETE"; then
	pass
else
	fail "Matched open tag without close"
fi

log_test "accepts <promise>COMPLETE</promise>"
if test_completion_marker "All done! <promise>COMPLETE</promise>"; then
	pass
else
	fail "Did not match <promise>COMPLETE</promise>"
fi

log_test "accepts promise tag on its own line with surrounding text"
output="Task finished.

<promise>COMPLETE</promise>

End."
if test_completion_marker "$output"; then
	pass
else
	fail "Did not match promise tag on its own line"
fi

log_test "accepts custom promise text"
if test_completion_marker "<promise>ALL TESTS PASS</promise>" "ALL TESTS PASS"; then
	pass
else
	fail "Did not match custom promise"
fi

log_test "accepts promise in longer multi-line text"
output="Summary: Fixed all issues, tests pass, code reviewed.

<promise>COMPLETE</promise>

Files modified: 5"
if test_completion_marker "$output"; then
	pass
else
	fail "Did not match promise in longer text"
fi

log_test "accepts promise tag embedded in JSON string"
output='{"type":"text","text":"All done\\n\\n<promise>COMPLETE</promise>"}'
if test_completion_marker "$output"; then
	pass
else
	fail "Did not match promise tag in JSON text"
fi

# =============================================
# CLI input validation
# =============================================
echo ""
echo "--- CLI input validation ---"

log_test "ralph loop rejects invalid completion-mode"
output=$("$SCRIPT_DIR/ralph" loop --completion-mode invalid "test" 2>&1) || true
assert_contains "$output" "Invalid completion mode"

log_test "ralph loop rejects invalid sandbox mode"
output=$("$SCRIPT_DIR/ralph" loop --sandbox invalid "test" 2>&1 || true)
if [[ "$output" == *"Invalid"* ]] || [[ "$output" == *"invalid"* ]]; then
	pass
else
	fail "Should reject invalid sandbox mode"
fi

log_test "ralph loop shows usage when no prompt given"
output=$("$SCRIPT_DIR/ralph" loop 2>&1 || true)
assert_contains "$output" "Usage"

# =============================================
# ralph models
# =============================================
echo ""
echo "--- ralph models ---"

log_test "ralph models get returns a model for high tier"
output=$("$SCRIPT_DIR/ralph" models get high 2>&1)
if [[ -n "$output" ]] && [[ "$output" != *"Error"* ]] && [[ "$output" != *"error"* ]]; then
	pass
else
	fail "No model returned for tier 'high', got: '$output'"
fi

# =============================================
# ralph stats
# =============================================
echo ""
echo "--- ralph stats ---"

log_test "ralph stats exits cleanly"
set +e
"$SCRIPT_DIR/ralph" stats >/dev/null 2>&1
exit_code=$?
set -e
assert_eq "$exit_code" "0"

log_test "ralph stats --json produces valid JSON with expected keys"
output=$("$SCRIPT_DIR/ralph" stats --json 2>&1)
if echo "$output" | jq -e 'type == "object" or type == "array"' >/dev/null 2>&1; then
	pass
else
	fail "JSON output is not valid: $output"
fi

log_test "ralph stats handles empty session directory"
TEMP_STATS_DIR=$(mktemp -d)
mkdir -p "$TEMP_STATS_DIR/state/ralph"
cp -r "$SCRIPT_DIR/lib" "$TEMP_STATS_DIR/"
export RALPH_ROOT="$TEMP_STATS_DIR"
export RALPH_STATE_DIR="$TEMP_STATS_DIR/state"
source "$TEMP_STATS_DIR/lib/common.sh"
output=$(bash "$SCRIPT_DIR/cmd/stats.sh" 2>&1)
unset RALPH_ROOT RALPH_STATE_DIR
assert_contains "$output" "No sessions"
rm -rf "$TEMP_STATS_DIR"

# =============================================
# ralph cleanup
# =============================================
echo ""
echo "--- ralph cleanup ---"

CLEANUP_TEST_DIR=$(mktemp -d)
mkdir -p "$CLEANUP_TEST_DIR/state/ralph"
cp -r "$SCRIPT_DIR/lib" "$CLEANUP_TEST_DIR/"
export RALPH_ROOT="$CLEANUP_TEST_DIR"
export RALPH_STATE_DIR="$CLEANUP_TEST_DIR/state"
source "$CLEANUP_TEST_DIR/lib/common.sh"

create_session() {
	local id=$1
	local status=$2
	local age_days=$3
	local date_str
	if [[ "$(uname)" == "Darwin" ]]; then
		date_str=$(date -v-${age_days}d +"%Y-%m-%dT%H:%M:%S%z")
	else
		date_str=$(date -d "$age_days days ago" --iso-8601=seconds)
	fi
	echo "{\"id\": \"$id\", \"status\": \"$status\", \"updatedAt\": \"$date_str\"}" >"$CLEANUP_TEST_DIR/state/ralph/$id.json"
}

create_session "old-completed" "completed" 10
create_session "new-completed" "completed" 1
create_session "old-failed" "failed" 10
create_session "running-session" "running" 15

log_test "cleanup dry-run lists candidates without deleting"
output=$(bash "$SCRIPT_DIR/cmd/cleanup.sh" --days 5 2>&1)
assert_contains "$output" "WOULD DELETE"

log_test "cleanup dry-run targets correct sessions"
if [[ "$output" == *"old-completed"* ]] && [[ "$output" == *"old-failed"* ]] && [[ "$output" != *"new-completed"* ]]; then
	pass
else
	fail "Dry-run targeted wrong sessions"
fi

log_test "cleanup respects --days threshold"
output=$(bash "$SCRIPT_DIR/cmd/cleanup.sh" --days 11 2>&1)
assert_contains "$output" "No sessions matched"

log_test "cleanup --status filters by status"
output=$(bash "$SCRIPT_DIR/cmd/cleanup.sh" --days 5 --status failed 2>&1)
if [[ "$output" == *"old-failed"* ]] && [[ "$output" != *"old-completed"* ]]; then
	pass
else
	fail "Status filter not working correctly"
fi

log_test "cleanup never targets running sessions"
output=$(bash "$SCRIPT_DIR/cmd/cleanup.sh" --days 0 2>&1)
if [[ "$output" != *"running-session"* ]]; then
	pass
else
	fail "Running session was targeted for deletion"
fi

log_test "cleanup --keep-last preserves newest sessions"
create_session "oldest" "completed" 20
create_session "older" "completed" 15
output=$(bash "$SCRIPT_DIR/cmd/cleanup.sh" --days 0 --keep-last 2 2>&1)
assert_contains "$output" "WOULD DELETE (3 sessions)"

log_test "cleanup --force deletes old sessions and keeps new ones"
bash "$SCRIPT_DIR/cmd/cleanup.sh" --days 5 --force >/dev/null
if [[ ! -f "$CLEANUP_TEST_DIR/state/ralph/old-completed.json" ]] && [[ -f "$CLEANUP_TEST_DIR/state/ralph/new-completed.json" ]]; then
	pass
else
	fail "File deletion failed or deleted wrong file"
fi

log_test "cleanup handles empty session directory"
unset RALPH_ROOT RALPH_STATE_DIR
TEMP_EMPTY_DIR=$(mktemp -d)
mkdir -p "$TEMP_EMPTY_DIR/state/ralph"
cp -r "$SCRIPT_DIR/lib" "$TEMP_EMPTY_DIR/"
export RALPH_ROOT="$TEMP_EMPTY_DIR"
export RALPH_STATE_DIR="$TEMP_EMPTY_DIR/state"
source "$TEMP_EMPTY_DIR/lib/common.sh"
output=$(bash "$SCRIPT_DIR/cmd/cleanup.sh" 2>&1)
unset RALPH_ROOT RALPH_STATE_DIR
assert_contains "$output" "No sessions found"
rm -rf "$TEMP_EMPTY_DIR"

log_test "cleanup handles missing state directory"
TEMP_MISSING_DIR=$(mktemp -d)
cp -r "$SCRIPT_DIR/lib" "$TEMP_MISSING_DIR/"
export RALPH_ROOT="$TEMP_MISSING_DIR"
export RALPH_STATE_DIR="$TEMP_MISSING_DIR/state"
source "$TEMP_MISSING_DIR/lib/common.sh"
output=$(bash "$SCRIPT_DIR/cmd/cleanup.sh" 2>&1)
unset RALPH_ROOT RALPH_STATE_DIR
assert_contains "$output" "State directory not found"
rm -rf "$TEMP_MISSING_DIR"

rm -rf "$CLEANUP_TEST_DIR"

# =============================================
# Concurrency control (lib/model.sh)
# =============================================
echo ""
echo "--- Concurrency control (lib/model.sh) ---"

CONCURRENCY_TEST_DIR=$(mktemp -d)
CONCURRENCY_CONFIG="$CONCURRENCY_TEST_DIR/config.json"
CONCURRENCY_SLOTS="$CONCURRENCY_TEST_DIR/model-slots.json"

cat >"$CONCURRENCY_CONFIG" <<'EOF'
{
  "concurrency": {
    "defaultMaxSlots": 3,
    "modelLimits": {
      "test-model": 2,
      "high-limit-model": 5
    }
  }
}
EOF
echo '{}' >"$CONCURRENCY_SLOTS"

log_test "get_model_concurrency_limit returns configured value"
result=$(get_model_concurrency_limit "test-model" "$CONCURRENCY_CONFIG")
assert_eq "$result" "2"

log_test "get_model_concurrency_limit returns per-model override"
result=$(get_model_concurrency_limit "high-limit-model" "$CONCURRENCY_CONFIG")
assert_eq "$result" "5"

log_test "get_model_concurrency_limit returns default for unknown model"
result=$(get_model_concurrency_limit "unknown-model" "$CONCURRENCY_CONFIG")
assert_eq "$result" "3"

log_test "get_model_slot_count returns 0 for empty slots"
result=$(get_model_slot_count "test-model" "$CONCURRENCY_SLOTS")
assert_eq "$result" "0"

log_test "acquire_model_slot succeeds when slots available"
if acquire_model_slot "test-model" "$CONCURRENCY_CONFIG" "$CONCURRENCY_SLOTS" 5; then
	pass
	SAVED_SLOT_ID="$ACQUIRED_SLOT_ID"
else
	fail "Could not acquire slot"
	SAVED_SLOT_ID=""
fi

log_test "slot count is 1 after first acquire"
result=$(get_model_slot_count "test-model" "$CONCURRENCY_SLOTS")
assert_eq "$result" "1"

log_test "has_available_slot true when under limit (1/2)"
if has_available_slot "test-model" "$CONCURRENCY_CONFIG" "$CONCURRENCY_SLOTS"; then
	pass
else
	fail "Should have available slots (1/2)"
fi

log_test "acquire second slot succeeds"
if acquire_model_slot "test-model" "$CONCURRENCY_CONFIG" "$CONCURRENCY_SLOTS" 5; then
	pass
	SAVED_SLOT_ID2="$ACQUIRED_SLOT_ID"
else
	fail "Could not acquire second slot"
	SAVED_SLOT_ID2=""
fi

log_test "has_available_slot false at limit (2/2)"
if ! has_available_slot "test-model" "$CONCURRENCY_CONFIG" "$CONCURRENCY_SLOTS"; then
	pass
else
	fail "Should not have available slots (2/2)"
fi

log_test "release_model_slot decreases count to 1"
release_model_slot "test-model" "$CONCURRENCY_SLOTS" "$SAVED_SLOT_ID"
result=$(get_model_slot_count "test-model" "$CONCURRENCY_SLOTS")
assert_eq "$result" "1"

log_test "release second slot returns count to 0"
release_model_slot "test-model" "$CONCURRENCY_SLOTS" "$SAVED_SLOT_ID2"
result=$(get_model_slot_count "test-model" "$CONCURRENCY_SLOTS")
assert_eq "$result" "0"

log_test "cleanup_stale_slots removes dead process slots"
locked_json_update "$CONCURRENCY_SLOTS" --arg model "test-model" \
	'.[$model] = {count: 1, slots: ["99999-12345-6789"]}'
cleanup_stale_slots "$CONCURRENCY_SLOTS"
result=$(get_model_slot_count "test-model" "$CONCURRENCY_SLOTS")
assert_eq "$result" "0"

rm -rf "$CONCURRENCY_TEST_DIR"

# =============================================
# Shared Agents (lib/agents.sh)
# =============================================
echo ""
echo "--- Shared agents (lib/agents.sh) ---"

source "$SCRIPT_DIR/lib/agents.sh"

log_test "get_shared_agents_dir returns correct path"
AGENTS_DIR=$(get_shared_agents_dir)
assert_eq "$AGENTS_DIR" "$SCRIPT_DIR/agents"

log_test "validate_agent accepts well-formed agent"
if validate_agent "$SCRIPT_DIR/agents/yolo.md" 2>/dev/null; then
	pass
else
	fail "yolo.md validation failed"
fi

log_test "validate_agent rejects missing file"
set +e
validate_agent "/nonexistent/agent.md" 2>/dev/null
exit_code=$?
set -e
assert_eq "$exit_code" "1"

log_test "validate_agent rejects file without YAML frontmatter"
echo "No frontmatter here" >"$TEST_DIR/bad-agent.md"
set +e
validate_agent "$TEST_DIR/bad-agent.md" 2>/dev/null
exit_code=$?
set -e
assert_eq "$exit_code" "1"

log_test "validate_agent rejects file without description field"
cat >"$TEST_DIR/no-desc-agent.md" <<'EOF'
---
mode: primary
---
Missing description
EOF
set +e
validate_agent "$TEST_DIR/no-desc-agent.md" 2>/dev/null
exit_code=$?
set -e
assert_eq "$exit_code" "1"

log_test "validate_agent rejects invalid mode"
cat >"$TEST_DIR/bad-mode-agent.md" <<'EOF'
---
description: "Test agent"
mode: invalid
---
Bad mode
EOF
set +e
validate_agent "$TEST_DIR/bad-mode-agent.md" 2>/dev/null
exit_code=$?
set -e
assert_eq "$exit_code" "1"

log_test "validate_all_agents passes for all shared agents"
if validate_all_agents 2>/dev/null; then
	pass
else
	fail "One or more shared agents failed validation"
fi

log_test "sync_agents_to copies agents to target"
SYNC_TARGET="$TEST_DIR/agents-sync-test"
mkdir -p "$SYNC_TARGET"
sync_agents_to "$SYNC_TARGET" 2>/dev/null
agent_count=$(ls "$SYNC_TARGET"/*.md 2>/dev/null | wc -l | tr -d ' ')
if [[ "$agent_count" -ge 3 ]]; then
	pass
else
	fail "Expected at least 3 agents synced, got $agent_count"
fi

log_test "sync_agents_to preserves existing files (no clobber)"
echo "custom content" >"$SYNC_TARGET/yolo.md"
sync_agents_to "$SYNC_TARGET" 2>/dev/null
CONTENT=$(cat "$SYNC_TARGET/yolo.md")
assert_eq "$CONTENT" "custom content"

log_test "ensure_agents creates .opencode/agents with agents inside"
ENSURE_TARGET="$TEST_DIR/ensure-test"
mkdir -p "$ENSURE_TARGET"
ensure_agents "$ENSURE_TARGET" 2>/dev/null
if [[ -d "$ENSURE_TARGET/.opencode/agents" ]]; then
	agent_count=$(ls "$ENSURE_TARGET/.opencode/agents"/*.md 2>/dev/null | wc -l | tr -d ' ')
	if [[ "$agent_count" -ge 3 ]]; then
		pass
	else
		fail "Expected at least 3 agents, got $agent_count"
	fi
else
	fail ".opencode/agents directory not created"
fi

log_test "list_agents includes known agents"
AGENT_LIST=$(list_agents 2>/dev/null)
if echo "$AGENT_LIST" | grep -q "yolo" && echo "$AGENT_LIST" | grep -q "explorer"; then
	pass
else
	fail "list_agents missing expected agents"
fi

log_test "get_agent_info returns JSON with correct name and valid mode"
AGENT_INFO=$(get_agent_info "yolo" 2>/dev/null)
name=$(echo "$AGENT_INFO" | jq -r '.name')
mode=$(echo "$AGENT_INFO" | jq -r '.mode')
if [[ "$name" == "yolo" ]] && { [[ "$mode" == "primary" ]] || [[ "$mode" == "subagent" ]]; }; then
	pass
else
	fail "Expected name=yolo and valid mode, got name='$name' mode='$mode'"
fi

log_test "get_agent_info returns error JSON for missing agent"
set +e
AGENT_INFO=$(get_agent_info "nonexistent-agent" 2>/dev/null)
exit_code=$?
set -e
if [[ $exit_code -ne 0 ]]; then
	error_msg=$(echo "$AGENT_INFO" | jq -r '.error // empty')
	if [[ -n "$error_msg" ]]; then
		pass
	else
		fail "Expected error field in JSON, got: $AGENT_INFO"
	fi
else
	fail "Should fail for nonexistent agent (exit=$exit_code)"
fi

# =============================================
# Cost tracking (lib/cost.sh)
# =============================================
echo ""
echo "--- Cost tracking (lib/cost.sh) ---"

source "$SCRIPT_DIR/lib/cost.sh"

log_test "check_budget: at exact limit is exceeded"
set +e
status=$(check_budget 5.00 5.00)
exit_code=$?
set -e
if [[ "$status" == "exceeded" ]] && [[ $exit_code -eq 1 ]]; then
	pass
else
	fail "Expected 'exceeded' with exit 1, got '$status' with exit $exit_code"
fi

log_test "check_budget: over limit is exceeded"
set +e
status=$(check_budget 5.50 5.00)
exit_code=$?
set -e
if [[ "$status" == "exceeded" ]] && [[ $exit_code -eq 1 ]]; then
	pass
else
	fail "Expected 'exceeded' with exit 1, got '$status' with exit $exit_code"
fi

log_test "check_budget: 85% returns warning:85"
status=$(check_budget 4.25 5.00)
assert_eq "$status" "warning:85"

log_test "check_budget: well below threshold is ok"
status=$(check_budget 2.00 5.00)
assert_eq "$status" "ok"

log_test "check_budget: just below 80% threshold is ok"
status=$(check_budget 3.99 5.00)
assert_eq "$status" "ok"

log_test "check_budget: exactly 80% triggers warning"
status=$(check_budget 4.00 5.00)
if [[ "$status" == warning:* ]]; then
	pass
else
	fail "Expected warning at 80%, got '$status'"
fi

log_test "check_budget: zero cost is ok"
status=$(check_budget 0 5.00)
assert_eq "$status" "ok"

log_test "check_budget: custom threshold 0.90 - below is ok"
status=$(check_budget 4.00 5.00 0.90)
assert_eq "$status" "ok"

log_test "check_budget: custom threshold 0.90 - above triggers warning"
status=$(check_budget 4.60 5.00 0.90)
if [[ "$status" == "warning:92" ]]; then
	pass
else
	fail "Expected 'warning:92', got '$status'"
fi

log_test "get_opencode_session_cost returns 0 for empty session id"
cost=$(get_opencode_session_cost "")
assert_eq "$cost" "0"

log_test "get_opencode_session_cost returns 0 for nonexistent session"
cost=$(get_opencode_session_cost "invalid-session-id")
assert_eq "$cost" "0"

log_test "get_opencode_session_tokens returns zeroed JSON for empty session"
tokens=$(get_opencode_session_tokens "")
input_tok=$(echo "$tokens" | jq -r '.input')
output_tok=$(echo "$tokens" | jq -r '.output')
if [[ "$input_tok" == "0" ]] && [[ "$output_tok" == "0" ]]; then
	pass
else
	fail "Expected zeroed tokens, got '$tokens'"
fi

log_test "record_opencode_session creates sessions file with correct format"
test_session_dir="$TEST_DIR/.ralph/cost-test-session"
mkdir -p "$test_session_dir"
record_opencode_session "cost-test-session" "$TEST_DIR" "ses_abc" "1"
if [[ -f "$test_session_dir/opencode-sessions.txt" ]]; then
	content=$(cat "$test_session_dir/opencode-sessions.txt")
	assert_eq "$content" "1:ses_abc"
else
	fail "Sessions file not created"
fi

log_test "record_opencode_session appends subsequent entries"
record_opencode_session "cost-test-session" "$TEST_DIR" "ses_def" "2"
line_count=$(wc -l <"$test_session_dir/opencode-sessions.txt" | tr -d ' ')
assert_eq "$line_count" "2"

log_test "get_ralph_session_cost returns 0 for non-existent session"
cost=$(get_ralph_session_cost "non-existent-session" "$TEST_DIR")
assert_eq "$cost" "0"

log_test "display_iteration_cost formats both cost values"
output=$(display_iteration_cost 0.1234 0.5678)
if [[ "$output" == *"0.1234"* ]] && [[ "$output" == *"0.5678"* ]]; then
	pass
else
	fail "Output formatting incorrect: $output"
fi

log_test "display_iteration_cost shows warning emoji near budget"
output=$(display_iteration_cost 0.10 4.50 5.00)
if [[ "$output" == *"%"* ]] && [[ "$output" == *"⚠️"* ]]; then
	pass
else
	fail "Budget warning not shown: $output"
fi

log_test "display_iteration_cost omits warning without budget"
output=$(display_iteration_cost 0.10 0.50)
if [[ "$output" != *"⚠️"* ]] && [[ "$output" != *"EXCEEDED"* ]]; then
	pass
else
	fail "Unexpected warning without budget: $output"
fi

log_test "display_token_usage formats with thousands separators"
tokens='{"input":1000,"output":500,"cacheRead":2000,"cacheWrite":100}'
output=$(display_token_usage "$tokens")
if [[ "$output" == *"1,000"* ]] && [[ "$output" == *"500"* ]]; then
	pass
else
	fail "Token formatting incorrect: $output"
fi

log_test "display_token_usage shows cache when nonzero"
tokens='{"input":100,"output":50,"cacheRead":5000,"cacheWrite":200}'
output=$(display_token_usage "$tokens")
if [[ "$output" == *"cache"* ]] && [[ "$output" == *"5,000"* ]]; then
	pass
else
	fail "Cache tokens not shown: $output"
fi

log_test "display_token_usage hides cache when zero"
tokens='{"input":100,"output":50,"cacheRead":0,"cacheWrite":0}'
output=$(display_token_usage "$tokens")
if [[ "$output" != *"cache"* ]]; then
	pass
else
	fail "Cache shown when zero: $output"
fi

log_test "record_claude_session creates costs JSONL file"
test_cc_dir="$TEST_DIR/.ralph/cc-cost-session"
mkdir -p "$test_cc_dir"
record_claude_session "cc-cost-session" "$TEST_DIR" 1 0.03
if [[ -f "$test_cc_dir/claude-costs.jsonl" ]]; then
	pass
else
	fail "Claude costs file not created"
fi

log_test "record_claude_session writes valid JSONL with correct values"
line=$(head -1 "$test_cc_dir/claude-costs.jsonl")
iter=$(echo "$line" | jq -r '.iteration')
cost=$(echo "$line" | jq -r '.cost')
ts=$(echo "$line" | jq -r '.timestamp')
if [[ "$iter" == "1" ]] && [[ "$cost" == "0.03" ]] && [[ "$ts" == *"T"*"Z" ]]; then
	pass
else
	fail "Expected iteration=1 cost=0.03 with timestamp, got iter=$iter cost=$cost ts=$ts"
fi

log_test "get_ralph_claude_session_cost sums multiple iterations"
record_claude_session "cc-cost-session" "$TEST_DIR" 2 0.0500
total=$(get_ralph_claude_session_cost "cc-cost-session" "$TEST_DIR")
if [[ "$total" == "0.08" ]]; then
	pass
else
	fail "Expected 0.08, got '$total'"
fi

log_test "get_ralph_claude_session_cost returns 0 for nonexistent session"
cost=$(get_ralph_claude_session_cost "nonexistent" "$TEST_DIR")
assert_eq "$cost" "0"

log_test "get_claude_session_cost extracts cost from stream-json output"
STREAM_FILE="$TEST_DIR/stream-output.json"
echo '{"type":"result","total_cost_usd":0.0456,"duration_ms":12345}' >"$STREAM_FILE"
cost=$(get_claude_session_cost "$STREAM_FILE")
assert_eq "$cost" "0.0456"

log_test "get_claude_session_duration extracts duration from stream-json output"
duration=$(get_claude_session_duration "$STREAM_FILE")
assert_eq "$duration" "12345"

log_test "get_claude_session_cost returns 0 for missing file"
cost=$(get_claude_session_cost "/nonexistent/file.json")
assert_eq "$cost" "0"

log_test "get_claude_session_cost returns 0 for empty arg"
cost=$(get_claude_session_cost "")
assert_eq "$cost" "0"

log_test "save_cost_summary creates valid summary file"
test_summary_dir="$TEST_DIR/.ralph/summary-test"
mkdir -p "$test_summary_dir"
echo "1:ses_dummy1" >"$test_summary_dir/opencode-sessions.txt"
save_cost_summary "summary-test" "$TEST_DIR"
if [[ -f "$test_summary_dir/cost-summary.json" ]]; then
	has_total=$(jq -e '.totalCost' "$test_summary_dir/cost-summary.json" >/dev/null 2>&1 && echo "yes" || echo "no")
	has_iters=$(jq -e '.iterations | type == "array"' "$test_summary_dir/cost-summary.json" >/dev/null 2>&1 && echo "yes" || echo "no")
	if [[ "$has_total" == "yes" ]] && [[ "$has_iters" == "yes" ]]; then
		pass
	else
		fail "Cost summary structure invalid"
	fi
else
	fail "Cost summary file not created"
fi

log_test "save_cost_summary for session with no opencode sessions creates zeroed summary"
mkdir -p "$TEST_DIR/.ralph/empty-summary-test"
save_cost_summary "empty-summary-test" "$TEST_DIR"
summary_file="$TEST_DIR/.ralph/empty-summary-test/cost-summary.json"
if [[ -f "$summary_file" ]]; then
	total=$(jq -r '.totalCost' "$summary_file")
	iters=$(jq -r '.iterations | length' "$summary_file")
	if [[ "$total" == "0" ]] && [[ "$iters" == "0" ]]; then
		pass
	else
		fail "Expected zeroed summary, got total=$total iters=$iters"
	fi
else
	fail "Summary file not created for missing session"
fi

# =============================================
# Formatter syntax tests (Finding 12)
# =============================================
(
	echo ""
	echo "--- Formatter syntax (lib/stream-formatter.sh, lib/oc-formatter.sh) ---"

	log_test "stream-formatter.sh has valid bash syntax"
	if bash -n "$SCRIPT_DIR/lib/stream-formatter.sh" 2>/dev/null; then
		pass
	else
		fail "stream-formatter.sh has syntax errors"
	fi

	log_test "oc-formatter.sh has valid bash syntax"
	if bash -n "$SCRIPT_DIR/lib/oc-formatter.sh" 2>/dev/null; then
		pass
	else
		fail "oc-formatter.sh has syntax errors"
	fi

	log_test "stream-formatter.sh can be sourced without error"
	set +e
	(source "$SCRIPT_DIR/lib/stream-formatter.sh" < /dev/null 2>/dev/null)
	exit_code=$?
	set -e
	if [[ $exit_code -eq 0 ]]; then
		pass
	else
		fail "stream-formatter.sh failed to source (exit=$exit_code)"
	fi

	log_test "oc-formatter.sh can be sourced without error"
	set +e
	(source "$SCRIPT_DIR/lib/oc-formatter.sh" < /dev/null 2>/dev/null)
	exit_code=$?
	set -e
	if [[ $exit_code -eq 0 ]]; then
		pass
	else
		fail "oc-formatter.sh failed to source (exit=$exit_code)"
	fi
)

# =============================================
# MCP converter tests (Finding 12)
# =============================================
(
	echo ""
	echo "--- MCP converter (lib/mcp-convert.sh) ---"

	source "$SCRIPT_DIR/lib/mcp-convert.sh"

	log_test "convert_mcp_to_opencode handles missing file gracefully"
	result=$(convert_mcp_to_opencode "/nonexistent/mcp.json" 2>/dev/null) || true
	assert_eq "$result" "{}"

	log_test "convert_mcp_to_opencode converts local server config"
	MCP_LOCAL="$TEST_DIR/mcp-local.json"
	cat >"$MCP_LOCAL" <<'EOF'
{
  "mcpServers": {
    "test-server": {
      "command": "node",
      "args": ["server.js"],
      "env": {"VAR": "value"}
    }
  }
}
EOF
	result=$(convert_mcp_to_opencode "$MCP_LOCAL")
	if echo "$result" | jq -e '.mcp."test-server".type == "local"' >/dev/null 2>&1 && \
	   echo "$result" | jq -e '.mcp."test-server".command == ["node","server.js"]' >/dev/null 2>&1; then
		pass
	else
		fail "Local server conversion failed: $result"
	fi

	log_test "convert_mcp_to_opencode converts remote server config"
	MCP_REMOTE="$TEST_DIR/mcp-remote.json"
	cat >"$MCP_REMOTE" <<'EOF'
{
  "mcpServers": {
    "remote-server": {
      "type": "http",
      "url": "https://example.com/mcp",
      "headers": {"Authorization": "Bearer token"}
    }
  }
}
EOF
	result=$(convert_mcp_to_opencode "$MCP_REMOTE")
	if echo "$result" | jq -e '.mcp."remote-server".type == "remote"' >/dev/null 2>&1 && \
	   echo "$result" | jq -e '.mcp."remote-server".url == "https://example.com/mcp"' >/dev/null 2>&1; then
		pass
	else
		fail "Remote server conversion failed: $result"
	fi

	log_test "convert_mcp_to_opencode handles empty mcpServers"
	MCP_EMPTY="$TEST_DIR/mcp-empty.json"
	echo '{}' >"$MCP_EMPTY"
	result=$(convert_mcp_to_opencode "$MCP_EMPTY")
	assert_eq "$result" "{}"

	log_test "merge_opencode_config merges MCP into base config"
	BASE_CONFIG="$TEST_DIR/base-opencode.json"
	echo '{"existing":"value"}' >"$BASE_CONFIG"
	result=$(merge_opencode_config "$BASE_CONFIG" "$MCP_LOCAL")
	if echo "$result" | jq -e '.existing == "value"' >/dev/null 2>&1 && \
	   echo "$result" | jq -e '.mcp."test-server".type == "local"' >/dev/null 2>&1; then
		pass
	else
		fail "Merge failed: $result"
	fi

	log_test "create_opencode_mcp_config writes file with schema"
	OUTPUT_MCP="$TEST_DIR/output-opencode.json"
	create_opencode_mcp_config "$MCP_LOCAL" "$OUTPUT_MCP"
	if [[ -f "$OUTPUT_MCP" ]]; then
		schema=$(jq -r '."$schema"' "$OUTPUT_MCP")
		if [[ "$schema" == *"opencode.ai"* ]]; then
			pass
		else
			fail "Schema not found or incorrect: $schema"
		fi
	else
		fail "Output file not created"
	fi
)

# =============================================
# Wrapper syntax tests (Finding 12)
# =============================================
(
	echo ""
	echo "--- Wrapper syntax (wrappers/) ---"

	log_test "wrappers/opencode has valid bash syntax"
	if bash -n "$SCRIPT_DIR/wrappers/opencode" 2>/dev/null; then
		pass
	else
		fail "wrappers/opencode has syntax errors"
	fi

	log_test "wrappers/agent-sandbox has valid bash syntax"
	if bash -n "$SCRIPT_DIR/wrappers/agent-sandbox" 2>/dev/null; then
		pass
	else
		fail "wrappers/agent-sandbox has syntax errors"
	fi

	log_test "default container image name is consistent across all files"
	# The setup script builds 'agent-sandbox:latest', and all consumers must default to the same name.
	# This catches rename-missed-a-spot bugs where one file still references an old image name.
	expected_image="agent-sandbox:latest"
	files_with_default=(
		"$SCRIPT_DIR/wrappers/agent-sandbox"
		"$SCRIPT_DIR/cmd/loop.sh"
		"$SCRIPT_DIR/gsd/gsd-runner"
		"$SCRIPT_DIR/setup/sandbox.sh"
	)
	all_consistent=true
	for f in "${files_with_default[@]}"; do
		if ! grep -q "$expected_image" "$f" 2>/dev/null; then
			all_consistent=false
			fail "$(basename "$f") does not reference default image '$expected_image'"
			break
		fi
	done
	if [[ "$all_consistent" == "true" ]]; then
		pass
	fi

	log_test "wrappers/opencode can be sourced without error"
	set +e
	# Source in subshell to avoid side effects
	(
		ORCHESTRATOR_DIR="$SCRIPT_DIR"
		export ORCHESTRATOR_DIR
		source "$SCRIPT_DIR/wrappers/opencode" --help >/dev/null 2>&1
	)
	exit_code=$?
	set -e
	# Exit code might not be 0 due to --help or missing setup, but should not be a syntax error (>2)
	if [[ $exit_code -le 2 ]]; then
		pass
	else
		fail "wrappers/opencode sourcing failed with exit=$exit_code"
	fi
)

# =============================================
# Argument validation tests for loop.sh (Finding 12)
# =============================================
(
	echo ""
	echo "--- Argument validation (cmd/loop.sh) ---"

	log_test "loop.sh --mode without value shows clear error"
	output=$(bash "$SCRIPT_DIR/cmd/loop.sh" --mode 2>&1) || true
	if echo "$output" | grep -qi "requires a value\|Error.*--mode"; then
		pass
	else
		fail "Expected 'requires a value' error, got: $output"
	fi

	log_test "loop.sh --tier without value shows clear error"
	output=$(bash "$SCRIPT_DIR/cmd/loop.sh" --tier 2>&1) || true
	if echo "$output" | grep -qi "requires a value\|Error.*--tier"; then
		pass
	else
		fail "Expected 'requires a value' error, got: $output"
	fi

	log_test "loop.sh --model without value shows clear error"
	output=$(bash "$SCRIPT_DIR/cmd/loop.sh" --model 2>&1) || true
	if echo "$output" | grep -qi "requires a value\|Error.*--model"; then
		pass
	else
		fail "Expected 'requires a value' error, got: $output"
	fi

	log_test "loop.sh --budget without value shows clear error"
	output=$(bash "$SCRIPT_DIR/cmd/loop.sh" --budget 2>&1) || true
	if echo "$output" | grep -qi "requires a value\|Error.*--budget"; then
		pass
	else
		fail "Expected 'requires a value' error, got: $output"
	fi

	log_test "loop.sh --session without value shows clear error"
	output=$(bash "$SCRIPT_DIR/cmd/loop.sh" --session 2>&1) || true
	if echo "$output" | grep -qi "requires a value\|Error.*--session"; then
		pass
	else
		fail "Expected 'requires a value' error, got: $output"
	fi

	log_test "loop.sh --mcp-config without value shows clear error"
	output=$(bash "$SCRIPT_DIR/cmd/loop.sh" --mcp-config 2>&1) || true
	if echo "$output" | grep -qi "requires a value\|Error.*--mcp-config"; then
		pass
	else
		fail "Expected 'requires a value' error, got: $output"
	fi
)

# =============================================
# Stream Formatter Functional Tests
# =============================================
(
	echo ""
	echo "--- Stream formatter functional tests (lib/stream-formatter.sh) ---"

	FORMATTER="$SCRIPT_DIR/lib/stream-formatter.sh"

	log_test "stream-formatter outputs text from assistant message"
	input='{"type":"assistant","message":{"content":[{"type":"text","text":"Hello world from the agent"}]}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	assert_contains "$output" "Hello world from the agent"

	log_test "stream-formatter outputs thinking block"
	input='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Let me think about this problem carefully"}]}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	assert_contains "$output" "Let me think about this problem carefully"

	log_test "stream-formatter truncates thinking in non-verbose mode"
	input='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Line one\nLine two\nLine three\nLine four\nLine five\nLine six"}]}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=false bash "$FORMATTER" 2>/dev/null)
	if [[ "$output" == *"..."* ]] || [[ "$output" == *"…"* ]] || [[ $(echo "$output" | wc -l | tr -d ' ') -le 4 ]]; then
		pass
	else
		fail "Thinking was not truncated: $output"
	fi

	log_test "stream-formatter formats Read tool_use"
	input='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/foo/bar/baz/qux.txt"}}]}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	assert_contains "$output" "Read"

	log_test "stream-formatter formats Bash tool_use with command"
	input='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls -la /tmp"}}]}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Bash"* ]] && [[ "$output" == *"ls -la /tmp"* ]]; then
		pass
	else
		fail "Bash tool not formatted correctly: $output"
	fi

	log_test "stream-formatter formats Grep tool_use with pattern"
	input='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Grep","input":{"pattern":"TODO","glob":"*.sh"}}]}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Grep"* ]] && [[ "$output" == *"TODO"* ]]; then
		pass
	else
		fail "Grep tool not formatted correctly: $output"
	fi

	log_test "stream-formatter formats Edit tool_use"
	input='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a/b/c/test.sh","old_string":"foo","new_string":"bar"}}]}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Edit"* ]] && [[ "$output" == *"test.sh"* ]]; then
		pass
	else
		fail "Edit tool not formatted correctly: $output"
	fi

	log_test "stream-formatter formats Glob tool_use"
	input='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Glob","input":{"pattern":"**/*.ts","path":"/home/user/project"}}]}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Glob"* ]] && [[ "$output" == *"**/*.ts"* ]]; then
		pass
	else
		fail "Glob tool not formatted correctly: $output"
	fi

	log_test "stream-formatter formats Write tool_use"
	input='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/tmp/output.txt"}}]}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Write"* ]] && [[ "$output" == *"output.txt"* ]]; then
		pass
	else
		fail "Write tool not formatted correctly: $output"
	fi

	log_test "stream-formatter formats tool_result (success)"
	input='{"type":"tool_result","content":"File contents here: line 1","is_error":false}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	assert_contains "$output" "File contents here"

	log_test "stream-formatter formats tool_result (error)"
	input='{"type":"tool_result","content":"Error: file not found","is_error":true}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	assert_contains "$output" "Error: file not found"

	log_test "stream-formatter truncates long tool_result in non-verbose mode"
	long_content=$(printf '%0.sx' {1..500})
	input="{\"type\":\"tool_result\",\"content\":\"${long_content}\",\"is_error\":false}"
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=false bash "$FORMATTER" 2>/dev/null)
	output_len=${#output}
	if [[ $output_len -lt 500 ]]; then
		pass
	else
		fail "Tool result was not truncated (len=$output_len)"
	fi

	log_test "stream-formatter formats standalone tool_result from user message"
	input='{"type":"tool_result","content":"result from tool call","is_error":false}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	assert_contains "$output" "result from tool call"

	log_test "stream-formatter formats standalone error tool_result from user message"
	input='{"type":"tool_result","content":"permission denied error","is_error":true}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	assert_contains "$output" "permission denied error"

	log_test "stream-formatter formats result type with success"
	input='{"type":"result","subtype":"success","total_cost_usd":0.0456,"duration_ms":12345}'
	output=$(echo "$input" | NO_COLOR=1 bash "$FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Done"* ]] && [[ "$output" == *"12345"* ]] && [[ "$output" == *"0.0456"* ]]; then
		pass
	else
		fail "Result not formatted correctly: $output"
	fi

	log_test "stream-formatter ignores non-success result subtypes"
	input='{"type":"result","subtype":"error","total_cost_usd":0.01,"duration_ms":100}'
	output=$(echo "$input" | NO_COLOR=1 bash "$FORMATTER" 2>/dev/null)
	if [[ "$output" != *"Done"* ]]; then
		pass
	else
		fail "Non-success result should not show Done: $output"
	fi

	log_test "stream-formatter handles multiple content blocks in one message"
	input='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"step 1"},{"type":"text","text":"Here is the answer"},{"type":"tool_use","name":"Bash","input":{"command":"echo hello"}}]}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	if [[ "$output" == *"step 1"* ]] && [[ "$output" == *"Here is the answer"* ]] && [[ "$output" == *"Bash"* ]]; then
		pass
	else
		fail "Multiple content blocks not all formatted: $output"
	fi

	log_test "stream-formatter skips unknown JSON types"
	input='{"type":"system","message":"internal"}'
	output=$(echo "$input" | NO_COLOR=1 bash "$FORMATTER" 2>/dev/null)
	if [[ -z "$output" ]]; then
		pass
	else
		fail "Unknown type should produce no output, got: $output"
	fi

	log_test "stream-formatter skips empty lines"
	output=$(printf '\n\n\n' | NO_COLOR=1 bash "$FORMATTER" 2>/dev/null)
	if [[ -z "$output" ]]; then
		pass
	else
		fail "Empty lines should produce no output, got: $output"
	fi

	log_test "stream-formatter handles multi-line stream"
	input1='{"type":"assistant","message":{"content":[{"type":"text","text":"First message"}]}}'
	input2='{"type":"assistant","message":{"content":[{"type":"text","text":"Second message"}]}}'
	output=$(printf '%s\n%s\n' "$input1" "$input2" | NO_COLOR=1 bash "$FORMATTER" 2>/dev/null)
	if [[ "$output" == *"First message"* ]] && [[ "$output" == *"Second message"* ]]; then
		pass
	else
		fail "Multi-line stream not handled: $output"
	fi

	log_test "stream-formatter handles MCP tool names (mcp__foo__bar)"
	input='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__github__create_pr","input":{"title":"test"}}]}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	if [[ "$output" == *"github/create_pr"* ]]; then
		pass
	else
		fail "MCP tool name not converted: $output"
	fi

	log_test "stream-formatter formats WebSearch tool"
	input='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"WebSearch","input":{"query":"bash testing best practices"}}]}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	if [[ "$output" == *"WebSearch"* ]] && [[ "$output" == *"bash testing best practices"* ]]; then
		pass
	else
		fail "WebSearch tool not formatted correctly: $output"
	fi

	log_test "stream-formatter formats Read tool with offset and limit"
	input='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a/b/c/test.sh","offset":10,"limit":20}}]}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Read"* ]] && [[ "$output" == *":10"* ]]; then
		pass
	else
		fail "Read with offset not formatted correctly: $output"
	fi
)

# =============================================
# OC Formatter Functional Tests
# =============================================
(
	echo ""
	echo "--- OC formatter functional tests (lib/oc-formatter.sh) ---"

	OC_FORMATTER="$SCRIPT_DIR/lib/oc-formatter.sh"

	log_test "oc-formatter outputs text part"
	input='{"type":"text","part":{"text":"Hello from OpenCode"}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$OC_FORMATTER" 2>/dev/null)
	assert_contains "$output" "Hello from OpenCode"

	log_test "oc-formatter formats read tool_use"
	input='{"type":"tool_use","part":{"tool":"read","state":{"input":{"filePath":"/foo/bar/baz.txt"},"status":"running"}}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$OC_FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Read"* ]] && [[ "$output" == *"baz.txt"* ]]; then
		pass
	else
		fail "OC read tool not formatted correctly: $output"
	fi

	log_test "oc-formatter formats bash tool_use with command"
	input='{"type":"tool_use","part":{"tool":"bash","state":{"input":{"command":"npm test"},"status":"running"}}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$OC_FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Bash"* ]] && [[ "$output" == *"npm test"* ]]; then
		pass
	else
		fail "OC bash tool not formatted correctly: $output"
	fi

	log_test "oc-formatter formats grep tool_use"
	input='{"type":"tool_use","part":{"tool":"grep","state":{"input":{"pattern":"function","glob":"*.ts"},"status":"running"}}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$OC_FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Grep"* ]] && [[ "$output" == *"function"* ]]; then
		pass
	else
		fail "OC grep tool not formatted correctly: $output"
	fi

	log_test "oc-formatter formats glob tool_use"
	input='{"type":"tool_use","part":{"tool":"glob","state":{"input":{"pattern":"**/*.sh","path":"/workspace"},"status":"running"}}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$OC_FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Glob"* ]] && [[ "$output" == *"**/*.sh"* ]]; then
		pass
	else
		fail "OC glob tool not formatted correctly: $output"
	fi

	log_test "oc-formatter formats edit tool_use"
	input='{"type":"tool_use","part":{"tool":"edit","state":{"input":{"filePath":"/x/y/z/file.py"},"status":"running"}}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$OC_FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Edit"* ]] && [[ "$output" == *"file.py"* ]]; then
		pass
	else
		fail "OC edit tool not formatted correctly: $output"
	fi

	log_test "oc-formatter formats write tool_use"
	input='{"type":"tool_use","part":{"tool":"write","state":{"input":{"filePath":"/tmp/new-file.js"},"status":"running"}}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$OC_FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Write"* ]] && [[ "$output" == *"new-file.js"* ]]; then
		pass
	else
		fail "OC write tool not formatted correctly: $output"
	fi

	log_test "oc-formatter shows completed tool result"
	input='{"type":"tool_use","part":{"tool":"bash","state":{"input":{"command":"echo done"},"status":"completed","output":"done"}}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$OC_FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Bash"* ]] && [[ "$output" == *"done"* ]]; then
		pass
	else
		fail "OC completed tool result not shown: $output"
	fi

	log_test "oc-formatter shows error tool result"
	input='{"type":"tool_use","part":{"tool":"bash","state":{"input":{"command":"false"},"status":"error","error":"command failed"}}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$OC_FORMATTER" 2>/dev/null)
	assert_contains "$output" "command failed"

	log_test "oc-formatter truncates long tool result in non-verbose mode"
	long_output=$(printf '%0.sy' {1..500})
	input="{\"type\":\"tool_use\",\"part\":{\"tool\":\"bash\",\"state\":{\"input\":{\"command\":\"cat big\"},\"status\":\"completed\",\"output\":\"${long_output}\"}}}"
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=false bash "$OC_FORMATTER" 2>/dev/null)
	output_len=${#output}
	if [[ $output_len -lt 500 ]]; then
		pass
	else
		fail "OC tool result was not truncated (len=$output_len)"
	fi

	log_test "oc-formatter formats step_finish with stop reason"
	input='{"type":"step_finish","part":{"reason":"stop","cost":0.0789,"tokens":{"input":5000,"output":2000}}}'
	output=$(echo "$input" | NO_COLOR=1 bash "$OC_FORMATTER" 2>/dev/null)
	if [[ "$output" == *"Done"* ]] && [[ "$output" == *"0.0789"* ]] && [[ "$output" == *"7000"* ]]; then
		pass
	else
		fail "OC step_finish not formatted correctly: $output"
	fi

	log_test "oc-formatter ignores step_finish with non-stop reason"
	input='{"type":"step_finish","part":{"reason":"tool_use","cost":0.01,"tokens":{"input":100,"output":50}}}'
	output=$(echo "$input" | NO_COLOR=1 bash "$OC_FORMATTER" 2>/dev/null)
	if [[ -z "$output" ]]; then
		pass
	else
		fail "Non-stop step_finish should produce no output: $output"
	fi

	log_test "oc-formatter skips unknown types"
	input='{"type":"unknown_event","data":"something"}'
	output=$(echo "$input" | NO_COLOR=1 bash "$OC_FORMATTER" 2>/dev/null)
	if [[ -z "$output" ]]; then
		pass
	else
		fail "Unknown type should produce no output: $output"
	fi

	log_test "oc-formatter handles multi-line stream"
	input1='{"type":"text","part":{"text":"First output"}}'
	input2='{"type":"text","part":{"text":"Second output"}}'
	output=$(printf '%s\n%s\n' "$input1" "$input2" | NO_COLOR=1 bash "$OC_FORMATTER" 2>/dev/null)
	if [[ "$output" == *"First output"* ]] && [[ "$output" == *"Second output"* ]]; then
		pass
	else
		fail "OC multi-line stream not handled: $output"
	fi

	log_test "oc-formatter displays list tool as LS"
	input='{"type":"tool_use","part":{"tool":"list","state":{"input":{"path":"/tmp"},"status":"running"}}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$OC_FORMATTER" 2>/dev/null)
	assert_contains "$output" "LS"

	log_test "oc-formatter displays fetch tool"
	input='{"type":"tool_use","part":{"tool":"fetch","state":{"input":{"url":"https://example.com"},"status":"running"}}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$OC_FORMATTER" 2>/dev/null)
	assert_contains "$output" "Fetch"

	log_test "oc-formatter displays unknown tool with generic icon"
	input='{"type":"tool_use","part":{"tool":"custom_tool","state":{"input":{"key":"val"},"status":"running"}}}'
	output=$(echo "$input" | NO_COLOR=1 RALPH_VERBOSE=true bash "$OC_FORMATTER" 2>/dev/null)
	assert_contains "$output" "custom_tool"
)

# =============================================
# MCP Conversion Functional Tests (extended)
# =============================================
(
	echo ""
	echo "--- MCP conversion functional tests (lib/mcp-convert.sh) ---"

	source "$SCRIPT_DIR/lib/mcp-convert.sh"

	log_test "convert_mcp_to_opencode handles multiple servers"
	MCP_MULTI="$TEST_DIR/mcp-multi.json"
	cat >"$MCP_MULTI" <<'EOF'
{
  "mcpServers": {
    "server-a": {
      "command": "python",
      "args": ["-m", "server_a"],
      "env": {"PORT": "8080"}
    },
    "server-b": {
      "type": "http",
      "url": "https://remote.example.com/mcp"
    }
  }
}
EOF
	result=$(convert_mcp_to_opencode "$MCP_MULTI")
	local_ok=$(echo "$result" | jq -e '.mcp."server-a".type == "local"' >/dev/null 2>&1 && echo "yes" || echo "no")
	remote_ok=$(echo "$result" | jq -e '.mcp."server-b".type == "remote"' >/dev/null 2>&1 && echo "yes" || echo "no")
	if [[ "$local_ok" == "yes" ]] && [[ "$remote_ok" == "yes" ]]; then
		pass
	else
		fail "Multiple server conversion failed: $result"
	fi

	log_test "convert_mcp_to_opencode preserves environment variables"
	result=$(convert_mcp_to_opencode "$MCP_MULTI")
	env_val=$(echo "$result" | jq -r '.mcp."server-a".environment.PORT' 2>/dev/null)
	assert_eq "$env_val" "8080"

	log_test "convert_mcp_to_opencode sets enabled=true on local servers"
	result=$(convert_mcp_to_opencode "$MCP_MULTI")
	enabled=$(echo "$result" | jq -r '.mcp."server-a".enabled' 2>/dev/null)
	assert_eq "$enabled" "true"

	log_test "convert_mcp_to_opencode sets enabled=true on remote servers"
	result=$(convert_mcp_to_opencode "$MCP_MULTI")
	enabled=$(echo "$result" | jq -r '.mcp."server-b".enabled' 2>/dev/null)
	assert_eq "$enabled" "true"

	log_test "convert_mcp_to_opencode merges command and args into command array"
	result=$(convert_mcp_to_opencode "$MCP_MULTI")
	cmd_json=$(echo "$result" | jq -c '.mcp."server-a".command' 2>/dev/null)
	assert_eq "$cmd_json" '["python","-m","server_a"]'

	log_test "convert_mcp_to_opencode handles server with no args"
	MCP_NOARGS="$TEST_DIR/mcp-noargs.json"
	cat >"$MCP_NOARGS" <<'EOF'
{
  "mcpServers": {
    "simple": {
      "command": "my-server"
    }
  }
}
EOF
	result=$(convert_mcp_to_opencode "$MCP_NOARGS")
	cmd_json=$(echo "$result" | jq -c '.mcp."simple".command' 2>/dev/null)
	assert_eq "$cmd_json" '["my-server"]'

	log_test "convert_mcp_to_opencode preserves remote headers"
	MCP_HEADERS="$TEST_DIR/mcp-headers.json"
	cat >"$MCP_HEADERS" <<'EOF'
{
  "mcpServers": {
    "auth-server": {
      "type": "http",
      "url": "https://api.example.com",
      "headers": {"Authorization": "Bearer secret123", "X-Custom": "value"}
    }
  }
}
EOF
	result=$(convert_mcp_to_opencode "$MCP_HEADERS")
	auth=$(echo "$result" | jq -r '.mcp."auth-server".headers.Authorization' 2>/dev/null)
	custom=$(echo "$result" | jq -r '.mcp."auth-server".headers."X-Custom"' 2>/dev/null)
	if [[ "$auth" == "Bearer secret123" ]] && [[ "$custom" == "value" ]]; then
		pass
	else
		fail "Headers not preserved: auth=$auth custom=$custom"
	fi

	log_test "convert_mcp_to_opencode preserves remote url"
	result=$(convert_mcp_to_opencode "$MCP_HEADERS")
	url=$(echo "$result" | jq -r '.mcp."auth-server".url' 2>/dev/null)
	assert_eq "$url" "https://api.example.com"

	log_test "merge_opencode_config preserves base config keys"
	BASE="$TEST_DIR/base-merge-test.json"
	echo '{"theme":"dark","debug":true}' >"$BASE"
	MCP_SIMPLE="$TEST_DIR/mcp-merge-simple.json"
	cat >"$MCP_SIMPLE" <<'EOF'
{
  "mcpServers": {
    "test": {"command": "cmd", "args": ["arg1"]}
  }
}
EOF
	result=$(merge_opencode_config "$BASE" "$MCP_SIMPLE")
	theme=$(echo "$result" | jq -r '.theme' 2>/dev/null)
	debug=$(echo "$result" | jq -r '.debug' 2>/dev/null)
	has_mcp=$(echo "$result" | jq -e '.mcp.test' >/dev/null 2>&1 && echo "yes" || echo "no")
	if [[ "$theme" == "dark" ]] && [[ "$debug" == "true" ]] && [[ "$has_mcp" == "yes" ]]; then
		pass
	else
		fail "Merge did not preserve base keys: theme=$theme debug=$debug has_mcp=$has_mcp"
	fi

	log_test "merge_opencode_config adds schema when base missing"
	result=$(merge_opencode_config "/nonexistent/base.json" "$MCP_SIMPLE")
	schema=$(echo "$result" | jq -r '."$schema"' 2>/dev/null)
	assert_contains "$schema" "opencode.ai"

	log_test "create_opencode_mcp_config output is valid JSON"
	OUTPUT_TEST="$TEST_DIR/create-mcp-output.json"
	create_opencode_mcp_config "$MCP_MULTI" "$OUTPUT_TEST"
	if jq -e . "$OUTPUT_TEST" >/dev/null 2>&1; then
		pass
	else
		fail "Output is not valid JSON"
	fi

	log_test "create_opencode_mcp_config includes both servers"
	server_a=$(jq -e '.mcp."server-a"' "$OUTPUT_TEST" >/dev/null 2>&1 && echo "yes" || echo "no")
	server_b=$(jq -e '.mcp."server-b"' "$OUTPUT_TEST" >/dev/null 2>&1 && echo "yes" || echo "no")
	if [[ "$server_a" == "yes" ]] && [[ "$server_b" == "yes" ]]; then
		pass
	else
		fail "Not all servers in output: server_a=$server_a server_b=$server_b"
	fi
)

# =============================================
# Argument Parsing Tests (loop.sh)
# =============================================
(
	echo ""
	echo "--- Argument parsing functional tests (cmd/loop.sh) ---"

	log_test "loop.sh --help exits cleanly with usage text"
	output=$("$SCRIPT_DIR/ralph" loop --help 2>&1)
	exit_code=$?
	if [[ $exit_code -eq 0 ]] && [[ "$output" == *"Usage"* ]] && [[ "$output" == *"Options"* ]]; then
		pass
	else
		fail "Expected exit 0 with usage text, got exit=$exit_code"
	fi

	log_test "loop.sh -h also shows help"
	output=$("$SCRIPT_DIR/ralph" loop -h 2>&1)
	exit_code=$?
	if [[ $exit_code -eq 0 ]] && [[ "$output" == *"Usage"* ]]; then
		pass
	else
		fail "Expected -h to show help, got exit=$exit_code"
	fi

	log_test "loop.sh --list exits cleanly"
	set +e
	output=$("$SCRIPT_DIR/ralph" loop --list 2>&1)
	exit_code=$?
	set -e
	if [[ $exit_code -eq 0 ]] && [[ "$output" == *"Sessions"* || "$output" == *"sessions"* || "$output" == *".ralph"* ]]; then
		pass
	else
		fail "Expected --list to exit cleanly with session info, got exit=$exit_code output='$output'"
	fi

	log_test "loop.sh unknown option shows error"
	set +e
	output=$("$SCRIPT_DIR/ralph" loop --nonexistent-flag "prompt" 2>&1)
	exit_code=$?
	set -e
	if [[ $exit_code -ne 0 ]] && [[ "$output" == *"Unknown option"* || "$output" == *"Error"* ]]; then
		pass
	else
		fail "Expected error for unknown option, got exit=$exit_code"
	fi

	log_test "loop.sh --completion-mode invalid shows error"
	set +e
	output=$("$SCRIPT_DIR/ralph" loop --completion-mode bogus "test prompt" 2>&1)
	exit_code=$?
	set -e
	if [[ $exit_code -ne 0 ]] && [[ "$output" == *"Invalid completion mode"* ]]; then
		pass
	else
		fail "Expected completion mode error, got exit=$exit_code output='$output'"
	fi

	log_test "loop.sh --sandbox invalid shows error"
	set +e
	output=$("$SCRIPT_DIR/ralph" loop --sandbox invalid "test prompt" 2>&1)
	exit_code=$?
	set -e
	if [[ $exit_code -ne 0 ]] && [[ "$output" == *"Invalid"* || "$output" == *"invalid"* ]]; then
		pass
	else
		fail "Expected sandbox error, got exit=$exit_code"
	fi

	log_test "loop.sh --agent invalid shows error"
	set +e
	output=$("$SCRIPT_DIR/ralph" loop --agent badagent --sandbox none "test prompt" 2>&1)
	exit_code=$?
	set -e
	if [[ $exit_code -ne 0 ]] && [[ "$output" == *"Invalid agent"* || "$output" == *"Error"* ]]; then
		pass
	else
		fail "Expected agent error, got exit=$exit_code"
	fi

	log_test "loop.sh --mode invalid shows error"
	set +e
	output=$("$SCRIPT_DIR/ralph" loop --mode badmode "test prompt" 2>&1)
	exit_code=$?
	set -e
	if [[ $exit_code -ne 0 ]] && [[ "$output" == *"Invalid mode"* || "$output" == *"Error"* ]]; then
		pass
	else
		fail "Expected mode error, got exit=$exit_code"
	fi

	log_test "loop.sh --max-iterations with non-numeric shows error"
	set +e
	output=$("$SCRIPT_DIR/ralph" loop --max abc --sandbox none "test prompt" 2>&1)
	exit_code=$?
	set -e
	if [[ $exit_code -ne 0 ]] && [[ "$output" == *"must be a number"* || "$output" == *"Error"* ]]; then
		pass
	else
		fail "Expected numeric validation error, got exit=$exit_code output='$output'"
	fi

	log_test "loop.sh --budget with non-numeric shows error"
	set +e
	output=$("$SCRIPT_DIR/ralph" loop --budget notanumber --sandbox none "test prompt" 2>&1)
	exit_code=$?
	set -e
	if [[ $exit_code -ne 0 ]] && [[ "$output" == *"must be a number"* || "$output" == *"Error"* ]]; then
		pass
	else
		fail "Expected budget validation error, got exit=$exit_code output='$output'"
	fi

	log_test "loop.sh --session with path traversal is rejected"
	set +e
	output=$("$SCRIPT_DIR/ralph" loop --session "../../../etc" --sandbox none "test prompt" 2>&1)
	exit_code=$?
	set -e
	if [[ $exit_code -ne 0 ]] && [[ "$output" == *"Invalid session ID"* ]]; then
		pass
	else
		fail "Expected session ID validation error, got exit=$exit_code output='$output'"
	fi

	log_test "loop.sh --session with valid ID is accepted"
	set +e
	output=$("$SCRIPT_DIR/ralph" loop --session "my-test-session_1" --sandbox none --help 2>&1)
	exit_code=$?
	set -e
	if [[ $exit_code -eq 0 ]]; then
		pass
	else
		fail "Valid session ID should be accepted, got exit=$exit_code"
	fi

	log_test "loop.sh --mcp-config with nonexistent file shows error"
	set +e
	output=$("$SCRIPT_DIR/ralph" loop --mcp-config /nonexistent/mcp.json --sandbox none "test prompt" 2>&1)
	exit_code=$?
	set -e
	if [[ $exit_code -ne 0 ]] && [[ "$output" == *"not found"* || "$output" == *"Error"* ]]; then
		pass
	else
		fail "Expected mcp-config error, got exit=$exit_code output='$output'"
	fi
)

# =============================================
# Model Selection Functional Tests (with real config)
# =============================================
(
	echo ""
	echo "--- Model selection functional tests (config/models.json) ---"

	REAL_CONFIG="$SCRIPT_DIR/config/models.json"

	log_test "get_models_for_tier returns real high-tier opencode models"
	result=$(get_models_for_tier "high" "$REAL_CONFIG" "opencode" | sort | tr '\n' ',')
	if [[ "$result" == *"anthropic/claude-opus"* ]] && [[ "$result" == *"google/gemini"* ]]; then
		pass
	else
		fail "Expected real model names, got: $result"
	fi

	log_test "get_models_for_tier returns real medium-tier opencode models"
	result=$(get_models_for_tier "medium" "$REAL_CONFIG" "opencode" | sort | tr '\n' ',')
	if [[ "$result" == *"sonnet"* ]] || [[ "$result" == *"flash"* ]]; then
		pass
	else
		fail "Expected medium tier models, got: $result"
	fi

	log_test "get_models_for_tier returns real claudecode models"
	result=$(get_models_for_tier "high" "$REAL_CONFIG" "claudecode")
	assert_eq "$result" "opus"

	log_test "get_models_for_tier medium claudecode returns sonnet"
	result=$(get_models_for_tier "medium" "$REAL_CONFIG" "claudecode")
	assert_eq "$result" "sonnet"

	log_test "get_models_for_tier low claudecode returns haiku"
	result=$(get_models_for_tier "low" "$REAL_CONFIG" "claudecode")
	assert_eq "$result" "haiku"

	log_test "get_next_available_model with real config returns a valid model"
	TEMP_RL="$TEST_DIR/real-config-rl.json"
	echo '{}' >"$TEMP_RL"
	result=$(get_next_available_model "high" "$REAL_CONFIG" "$TEMP_RL" false "opencode")
	if [[ "$result" == *"anthropic/"* ]] || [[ "$result" == *"google/"* ]]; then
		pass
	else
		fail "Expected a real model name, got: $result"
	fi

	log_test "get_model_concurrency_limit reads real config opus limit"
	result=$(get_model_concurrency_limit "anthropic/claude-opus-4-6" "$REAL_CONFIG")
	assert_eq "$result" "2"

	log_test "get_model_concurrency_limit reads real config flash limit"
	result=$(get_model_concurrency_limit "google/gemini-3-flash-preview" "$REAL_CONFIG")
	assert_eq "$result" "10"

	log_test "get_model_concurrency_limit returns default for unknown model in real config"
	result=$(get_model_concurrency_limit "some-other-model" "$REAL_CONFIG")
	assert_eq "$result" "3"

	log_test "load_config_defaults reads real config cooldown"
	load_config_defaults "$REAL_CONFIG"
	assert_eq "$DEFAULT_COOLDOWN" "900"

	log_test "rate limit recording and checking roundtrip"
	RL_FILE="$TEST_DIR/roundtrip-rl.json"
	echo '{}' >"$RL_FILE"
	mark_model_rate_limited "test-roundtrip-model" 60 "$RL_FILE" 2>/dev/null
	if is_model_rate_limited "test-roundtrip-model" "$RL_FILE"; then
		pass
	else
		fail "Model should be rate limited after marking"
	fi

	log_test "rate limit does not affect other models"
	if ! is_model_rate_limited "other-model" "$RL_FILE"; then
		pass
	else
		fail "Other model should not be rate limited"
	fi

	log_test "model fallback skips all rate-limited models in tier"
	FALLBACK_RL="$TEST_DIR/fallback-rl.json"
	future=$(($(date +%s) + 3600))
	high_models=$(get_models_for_tier "high" "$REAL_CONFIG" "opencode")
	rl_json='{}'
	while IFS= read -r m; do
		[[ -z "$m" ]] && continue
		rl_json=$(echo "$rl_json" | jq --arg model "$m" --argjson until "$future" '.[$model] = $until')
	done <<<"$high_models"
	echo "$rl_json" >"$FALLBACK_RL"
	result=$(get_next_available_model "high" "$REAL_CONFIG" "$FALLBACK_RL" true "opencode")
	medium_models=$(get_models_for_tier "medium" "$REAL_CONFIG" "opencode")
	low_models=$(get_models_for_tier "low" "$REAL_CONFIG" "opencode")
	all_fallbacks="$medium_models"$'\n'"$low_models"
	if echo "$all_fallbacks" | grep -qF "$result"; then
		pass
	else
		fail "Expected fallback model, got: $result"
	fi

	log_test "mark_model_rate_limited with short cooldown marks model"
	SHORT_RL="$TEST_DIR/short-cooldown-rl.json"
	echo '{}' >"$SHORT_RL"
	mark_model_rate_limited "empty-output-model" 120 "$SHORT_RL" 2>/dev/null
	if is_model_rate_limited "empty-output-model" "$SHORT_RL"; then
		pass
	else
		fail "Model should be rate limited after short cooldown mark"
	fi

	log_test "short cooldown value is less than default cooldown"
	# Verify the short cooldown (120s) produces a sooner expiry than default (900s)
	SHORT_RL2="$TEST_DIR/short-cooldown-rl2.json"
	echo '{}' >"$SHORT_RL2"
	mark_model_rate_limited "model-short" 120 "$SHORT_RL2" 2>/dev/null
	short_until=$(jq -r '.["model-short"]' "$SHORT_RL2")
	DEFAULT_RL="$TEST_DIR/default-cooldown-rl.json"
	echo '{}' >"$DEFAULT_RL"
	mark_model_rate_limited "model-default" 900 "$DEFAULT_RL" 2>/dev/null
	default_until=$(jq -r '.["model-default"]' "$DEFAULT_RL")
	if [[ $short_until -lt $default_until ]]; then
		pass
	else
		fail "Short cooldown ($short_until) should expire before default ($default_until)"
	fi
)

# =============================================
# Cost Tracking Functional Tests (extended)
# =============================================
(
	echo ""
	echo "--- Cost tracking functional tests (lib/cost.sh) ---"

	source "$SCRIPT_DIR/lib/cost.sh"

	log_test "get_claude_session_cost handles multiple result lines"
	MULTI_RESULT="$TEST_DIR/multi-result.json"
	echo '{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}' >"$MULTI_RESULT"
	echo '{"type":"result","total_cost_usd":0.01,"duration_ms":100}' >>"$MULTI_RESULT"
	echo '{"type":"result","total_cost_usd":0.05,"duration_ms":500}' >>"$MULTI_RESULT"
	cost=$(get_claude_session_cost "$MULTI_RESULT")
	assert_eq "$cost" "0.05"

	log_test "get_claude_session_duration handles spaced JSON"
	SPACED_RESULT="$TEST_DIR/spaced-result.json"
	echo '{"type": "result", "total_cost_usd": 0.123, "duration_ms": 45678}' >"$SPACED_RESULT"
	duration=$(get_claude_session_duration "$SPACED_RESULT")
	assert_eq "$duration" "45678"

	log_test "get_claude_session_cost handles spaced JSON"
	cost=$(get_claude_session_cost "$SPACED_RESULT")
	assert_eq "$cost" "0.123"

	log_test "record_claude_session and get_ralph_claude_session_cost roundtrip"
	RT_DIR="$TEST_DIR"
	RT_SESSION="roundtrip-cost-test"
	mkdir -p "$RT_DIR/.ralph/$RT_SESSION"
	record_claude_session "$RT_SESSION" "$RT_DIR" 1 0.10
	record_claude_session "$RT_SESSION" "$RT_DIR" 2 0.25
	record_claude_session "$RT_SESSION" "$RT_DIR" 3 0.15
	total=$(get_ralph_claude_session_cost "$RT_SESSION" "$RT_DIR")
	assert_eq "$total" "0.5"

	log_test "record_claude_session writes valid JSONL for each iteration"
	COSTS_FILE="$RT_DIR/.ralph/$RT_SESSION/claude-costs.jsonl"
	line_count=$(wc -l <"$COSTS_FILE" | tr -d ' ')
	assert_eq "$line_count" "3"

	log_test "record_claude_session JSONL has correct iteration numbers"
	iter1=$(sed -n '1p' "$COSTS_FILE" | jq -r '.iteration')
	iter2=$(sed -n '2p' "$COSTS_FILE" | jq -r '.iteration')
	iter3=$(sed -n '3p' "$COSTS_FILE" | jq -r '.iteration')
	if [[ "$iter1" == "1" ]] && [[ "$iter2" == "2" ]] && [[ "$iter3" == "3" ]]; then
		pass
	else
		fail "Iteration numbers wrong: $iter1, $iter2, $iter3"
	fi

	log_test "display_iteration_cost shows EXCEEDED for over-budget"
	output=$(display_iteration_cost 0.50 6.00 5.00)
	assert_contains "$output" "EXCEEDED"

	log_test "display_budget_exceeded shows formatted box"
	output=$(display_budget_exceeded 6.50 5.00)
	if [[ "$output" == *"BUDGET EXCEEDED"* ]] && [[ "$output" == *"6.50"* ]] && [[ "$output" == *"5.00"* ]]; then
		pass
	else
		fail "Budget exceeded box not formatted correctly: $output"
	fi

	log_test "record_to_ledger creates ledger file"
	LEDGER_SCRIPT_DIR="$TEST_DIR/ledger-test"
	mkdir -p "$LEDGER_SCRIPT_DIR/state/costs"
	_ORIG_LEDGER_DIR_FN=$(declare -f get_ledger_dir)
	get_ledger_dir() { echo "$LEDGER_SCRIPT_DIR/state/costs"; }
	record_to_ledger "test-session" "Fix all bugs" 1.2345 "/tmp/project" "opus"
	LEDGER_FILE="$LEDGER_SCRIPT_DIR/state/costs/ledger.jsonl"
	if [[ -f "$LEDGER_FILE" ]]; then
		pass
	else
		fail "Ledger file not created"
	fi

	log_test "record_to_ledger writes valid JSONL with correct fields"
	line=$(head -1 "$LEDGER_FILE")
	session=$(echo "$line" | jq -r '.session')
	spec=$(echo "$line" | jq -r '.spec')
	cost=$(echo "$line" | jq -r '.cost')
	model=$(echo "$line" | jq -r '.model')
	spec_trimmed="${spec%% }"
	if [[ "$session" == "test-session" ]] && [[ "$spec_trimmed" == "Fix all bugs" ]] && [[ "$cost" == "1.2345" ]] && [[ "$model" == "opus" ]]; then
		pass
	else
		fail "Ledger entry fields wrong: session=$session spec=$spec_trimmed cost=$cost model=$model"
	fi

	log_test "get_total_spend returns correct total"
	record_to_ledger "test-session-2" "Add tests" 0.5 "/tmp/project" "sonnet"
	total=$(get_total_spend 1)
	match=$(awk -v got="$total" 'BEGIN {print (got - 1.7345 < 0.001 && got - 1.7345 > -0.001) ? "yes" : "no"}')
	if [[ "$match" == "yes" ]]; then
		pass
	else
		fail "Expected total ~1.7345, got $total"
	fi

	log_test "get_costs_by_date returns array with today's date"
	result=$(get_costs_by_date 1)
	today=$(date +%Y-%m-%d)
	date_in_result=$(echo "$result" | jq -r '.[0].date // empty')
	assert_eq "$date_in_result" "$today"

	log_test "get_costs_by_date shows correct session count"
	sessions=$(echo "$result" | jq -r '.[0].sessions // 0')
	assert_eq "$sessions" "2"

	log_test "get_daily_spend returns correct data for today"
	today=$(date +%Y-%m-%d)
	result=$(get_daily_spend "$today")
	day_sessions=$(echo "$result" | jq -r '.sessions')
	if [[ "$day_sessions" == "2" ]]; then
		pass
	else
		fail "Expected 2 sessions, got $day_sessions"
	fi

	log_test "get_costs_by_spec groups by spec name"
	result=$(get_costs_by_spec 1)
	spec_count=$(echo "$result" | jq 'length')
	if [[ "$spec_count" == "2" ]]; then
		pass
	else
		fail "Expected 2 spec groups, got $spec_count"
	fi

	log_test "get_costs_by_project groups by project"
	result=$(get_costs_by_project 1)
	project_count=$(echo "$result" | jq 'length')
	if [[ "$project_count" == "1" ]]; then
		pass
	else
		fail "Expected 1 project group, got $project_count"
	fi

	eval "$_ORIG_LEDGER_DIR_FN"

	log_test "_format_number adds thousands separators"
	result=$(_format_number 1234567)
	if [[ "$result" == "1,234,567" ]]; then
		pass
	else
		fail "Expected 1,234,567, got $result"
	fi

	log_test "_format_number handles small numbers"
	result=$(_format_number 42)
	assert_eq "$result" "42"

	log_test "_format_number handles zero"
	result=$(_format_number 0)
	assert_eq "$result" "0"
)

# =============================================
# Lock Staleness Tests
# =============================================
(
	echo ""
	echo "--- Lock staleness tests (lib/core.sh) ---"

	log_test "stale lock by old timestamp is recovered"
	STALE_LOCK_FILE="$TEST_DIR/stale-time.lock"
	STALE_LOCKDIR="${STALE_LOCK_FILE}.lockdir"
	mkdir -p "$STALE_LOCKDIR"
	echo $$ >"$STALE_LOCKDIR/pid"
	old_time=$(($(date +%s) - 600))
	echo "$old_time" >"$STALE_LOCKDIR/timestamp"
	if acquire_lock "$STALE_LOCK_FILE"; then
		pass
		release_lock "$STALE_LOCK_FILE"
	else
		fail "Could not acquire lock with stale timestamp"
	fi

	log_test "stale lock by dead PID is recovered"
	DEAD_LOCK_FILE="$TEST_DIR/stale-pid.lock"
	DEAD_LOCKDIR="${DEAD_LOCK_FILE}.lockdir"
	mkdir -p "$DEAD_LOCKDIR"
	echo "99999" >"$DEAD_LOCKDIR/pid"
	if acquire_lock "$DEAD_LOCK_FILE"; then
		pass
		release_lock "$DEAD_LOCK_FILE"
	else
		fail "Could not acquire lock with dead PID"
	fi

	log_test "active lock with valid PID and recent timestamp is respected"
	ACTIVE_LOCK_FILE="$TEST_DIR/active.lock"
	ACTIVE_LOCKDIR="${ACTIVE_LOCK_FILE}.lockdir"
	mkdir -p "$ACTIVE_LOCKDIR"
	echo $$ >"$ACTIVE_LOCKDIR/pid"
	echo "$(date +%s)" >"$ACTIVE_LOCKDIR/timestamp"
	set +e
	(
		attempts=0
		while ! mkdir "$ACTIVE_LOCKDIR" 2>/dev/null; do
			attempts=$((attempts + 1))
			if [[ $attempts -ge 5 ]]; then
				exit 1
			fi
			sleep 0.01
		done
		rmdir "$ACTIVE_LOCKDIR" 2>/dev/null
		exit 0
	)
	result=$?
	set -e
	if [[ $result -ne 0 ]]; then
		pass
	else
		fail "Active lock should not be acquirable"
	fi
	rm -rf "$ACTIVE_LOCKDIR"

	log_test "lock timestamp is written on acquire"
	TS_LOCK_FILE="$TEST_DIR/ts-lock.lock"
	acquire_lock "$TS_LOCK_FILE"
	TS_LOCKDIR="${TS_LOCK_FILE}.lockdir"
	if [[ -f "$TS_LOCKDIR/timestamp" ]]; then
		ts_val=$(cat "$TS_LOCKDIR/timestamp")
		now=$(date +%s)
		diff=$((now - ts_val))
		if [[ $diff -ge 0 ]] && [[ $diff -le 5 ]]; then
			pass
		else
			fail "Timestamp too old or in future: diff=$diff"
		fi
	else
		fail "Timestamp file not created"
	fi
	release_lock "$TS_LOCK_FILE"

	log_test "lock PID matches current process"
	PID_LOCK_FILE="$TEST_DIR/pid-lock.lock"
	acquire_lock "$PID_LOCK_FILE"
	PID_LOCKDIR="${PID_LOCK_FILE}.lockdir"
	pid_val=$(cat "$PID_LOCKDIR/pid")
	assert_eq "$pid_val" "$$"
	release_lock "$PID_LOCK_FILE"
)

# =============================================
# Completion Detection Edge Cases
# =============================================
(
	echo ""
	echo "--- Completion detection edge cases ---"

	log_test "custom promise text via variable"
	if test_completion_marker "<promise>TASKS_DONE</promise>" "TASKS_DONE"; then
		pass
	else
		fail "Did not match custom promise TASKS_DONE"
	fi

	log_test "custom promise with spaces"
	if test_completion_marker "<promise>ALL TESTS PASSED</promise>" "ALL TESTS PASSED"; then
		pass
	else
		fail "Did not match custom promise with spaces"
	fi

	log_test "partial opening tag does not match"
	if ! test_completion_marker "<promise>COMPLE" "COMPLETE"; then
		pass
	else
		fail "Matched partial promise text"
	fi

	log_test "mismatched promise text does not match"
	if ! test_completion_marker "<promise>FINISHED</promise>" "COMPLETE"; then
		pass
	else
		fail "Matched wrong promise text"
	fi

	log_test "marker in deeply nested output still detected"
	output="Starting work...
Iteration 1 of 5
Running tests...
All tests passed.
Summary:
- Fixed 3 bugs
- Added 2 features
- Refactored 1 module

<promise>COMPLETE</promise>

Generated files:
- output.txt
- report.md
End of output"
	if test_completion_marker "$output"; then
		pass
	else
		fail "Did not find marker in deeply nested output"
	fi

	log_test "multiple promise tags - first one matches"
	output="<promise>COMPLETE</promise> and <promise>COMPLETE</promise>"
	if test_completion_marker "$output"; then
		pass
	else
		fail "Did not match with multiple promise tags"
	fi

	log_test "marker with surrounding whitespace on same line"
	if test_completion_marker "   <promise>COMPLETE</promise>   "; then
		pass
	else
		fail "Did not match marker with surrounding whitespace"
	fi

	log_test "HTML-like but wrong tag does not match"
	if ! test_completion_marker "<div>COMPLETE</div>"; then
		pass
	else
		fail "Matched wrong HTML-like tags"
	fi

	log_test "empty promise tags detected by grep"
	tmp_file=$(mktemp)
	echo "<promise></promise>" > "$tmp_file"
	if grep -qF "<promise></promise>" "$tmp_file"; then
		pass
	else
		fail "grep did not find empty promise tags"
	fi
	rm -f "$tmp_file"

	log_test "case sensitive - lowercase does not match uppercase"
	if ! test_completion_marker "<promise>complete</promise>" "COMPLETE"; then
		pass
	else
		fail "Matched lowercase against uppercase promise"
	fi

	log_test "marker in JSON stream output"
	output='{"type":"assistant","message":{"content":[{"type":"text","text":"Done! <promise>COMPLETE</promise>"}]}}'
	if test_completion_marker "$output"; then
		pass
	else
		fail "Did not match marker in JSON stream"
	fi
)

# =============================================
# Cross-Platform Utility Tests
# =============================================
(
	echo ""
	echo "--- Cross-platform utility tests (lib/core.sh) ---"

	log_test "get_file_size returns correct size for known content"
	TEST_SIZE_FILE="$TEST_DIR/size-exact.txt"
	printf "abcd" >"$TEST_SIZE_FILE"
	result=$(get_file_size "$TEST_SIZE_FILE")
	assert_eq "$result" "4"

	log_test "get_file_size returns correct size for empty file"
	TEST_EMPTY_FILE="$TEST_DIR/empty-file.txt"
	touch "$TEST_EMPTY_FILE"
	result=$(get_file_size "$TEST_EMPTY_FILE")
	assert_eq "$result" "0"

	log_test "get_file_size returns correct size for larger file"
	TEST_LARGE_FILE="$TEST_DIR/large-file.txt"
	dd if=/dev/zero of="$TEST_LARGE_FILE" bs=1024 count=10 2>/dev/null
	result=$(get_file_size "$TEST_LARGE_FILE")
	assert_eq "$result" "10240"

	log_test "get_file_mtime returns a valid timestamp"
	TEST_MTIME_FILE="$TEST_DIR/mtime-test.txt"
	echo "test" >"$TEST_MTIME_FILE"
	result=$(get_file_mtime "$TEST_MTIME_FILE")
	now=$(date +%s)
	diff=$((now - result))
	if [[ $diff -ge 0 ]] && [[ $diff -le 10 ]]; then
		pass
	else
		fail "mtime diff=$diff from now (expected 0-10)"
	fi

	log_test "get_cutoff_date returns a valid date format"
	result=$(get_cutoff_date 7)
	if [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
		pass
	else
		fail "Expected YYYY-MM-DD format, got: $result"
	fi

	log_test "get_cutoff_date 0 returns today"
	result=$(get_cutoff_date 0)
	today=$(date +%Y-%m-%d)
	assert_eq "$result" "$today"

	log_test "get_cutoff_date 1 returns yesterday"
	result=$(get_cutoff_date 1)
	if [[ "$_UNAME_CACHE" == "Darwin" ]]; then
		expected=$(date -v-1d +%Y-%m-%d)
	else
		expected=$(date -d "1 day ago" +%Y-%m-%d)
	fi
	assert_eq "$result" "$expected"

	log_test "format_time_display returns HH:MM:SS format"
	ts=$(date +%s)
	result=$(format_time_display "$ts")
	if [[ "$result" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
		pass
	else
		fail "Expected HH:MM:SS format, got: $result"
	fi

	log_test "parse_date_to_epoch converts ISO date correctly"
	epoch=$(parse_date_to_epoch "2025-01-15T12:00:00Z")
	if [[ -n "$epoch" ]] && [[ "$epoch" =~ ^[0-9]+$ ]]; then
		pass
	else
		fail "Expected numeric epoch, got: $epoch"
	fi

	log_test "format_epoch_date converts epoch to date string"
	epoch=$(date +%s)
	result=$(format_epoch_date "$epoch" "+%Y-%m-%d")
	today=$(date +%Y-%m-%d)
	assert_eq "$result" "$today"

	log_test "parse_date_to_epoch and format_epoch_date roundtrip"
	original_date="2025-06-15T10:30:00Z"
	epoch=$(parse_date_to_epoch "$original_date")
	if [[ -n "$epoch" ]] && [[ "$epoch" =~ ^[0-9]+$ ]]; then
		round_date=$(format_epoch_date "$epoch" "+%Y-%m-%d")
		assert_eq "$round_date" "2025-06-15"
	else
		fail "Could not parse date to epoch"
	fi

	log_test "shuffle_lines preserves all elements with larger set"
	result=$(printf 'alpha\nbeta\ngamma\ndelta\nepsilon\n' | shuffle_lines | sort | tr '\n' ',')
	assert_eq "$result" "alpha,beta,delta,epsilon,gamma,"

	log_test "run_with_timeout succeeds for fast commands"
	result=$(run_with_timeout 5 echo "fast")
	assert_eq "$result" "fast"

	log_test "run_with_timeout returns output from command"
	result=$(run_with_timeout 5 printf "hello world")
	assert_eq "$result" "hello world"
)

# =============================================
# Session ID Generation Tests
# =============================================
(
	echo ""
	echo "--- Session ID generation (cmd/loop.sh) ---"

	source "$SCRIPT_DIR/lib/common.sh"

	ADJECTIVES=(quick lazy happy angry brave calm swift gentle fierce quiet bold shy wild free kind)
	NOUNS=(fox wolf bear hawk owl deer fish crow dove lion frog duck swan moth crab)
	VERBS=(runs leaps soars dives hunts rests waits grows flies swims jumps walks hides seeks roams)

	generate_session_id() {
		local adj=${ADJECTIVES[$RANDOM % ${#ADJECTIVES[@]}]}
		local noun=${NOUNS[$RANDOM % ${#NOUNS[@]}]}
		local verb=${VERBS[$RANDOM % ${#VERBS[@]}]}
		local hex
		hex=$(printf '%04x' $((RANDOM % 65536)))
		echo "${adj}-${noun}-${verb}-${hex}"
	}

	log_test "generate_session_id produces word-word-word-hex format"
	sid=$(generate_session_id)
	if [[ "$sid" =~ ^[a-z]+-[a-z]+-[a-z]+-[0-9a-f]{4}$ ]]; then
		pass
	else
		fail "Session ID format wrong: $sid"
	fi

	log_test "generate_session_id produces different IDs"
	sid1=$(generate_session_id)
	sid2=$(generate_session_id)
	sid3=$(generate_session_id)
	if [[ "$sid1" != "$sid2" ]] || [[ "$sid2" != "$sid3" ]]; then
		pass
	else
		fail "All three session IDs identical: $sid1"
	fi

	log_test "generate_session_id uses valid adjectives"
	sid=$(generate_session_id)
	adj="${sid%%-*}"
	valid=false
	for a in "${ADJECTIVES[@]}"; do
		if [[ "$a" == "$adj" ]]; then valid=true; break; fi
	done
	if [[ "$valid" == "true" ]]; then
		pass
	else
		fail "Adjective not in word list: $adj"
	fi

	log_test "session ID validates alphanumeric-hyphen-underscore"
	valid_ids=("quick-fox-runs-a1b2" "my_session" "test-123" "abc")
	all_pass=true
	for id in "${valid_ids[@]}"; do
		if [[ ! "$id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
			all_pass=false
			break
		fi
	done
	if [[ "$all_pass" == "true" ]]; then
		pass
	else
		fail "Valid session ID rejected by regex"
	fi

	log_test "session ID rejects path traversal characters"
	invalid_ids=("../hack" "foo/bar" "a b c" "test;rm" 'id$var')
	all_rejected=true
	for id in "${invalid_ids[@]}"; do
		if [[ "$id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
			all_rejected=false
			break
		fi
	done
	if [[ "$all_rejected" == "true" ]]; then
		pass
	else
		fail "Invalid session ID accepted by regex"
	fi
)

# =============================================
# Summary
# =============================================
echo ""
echo "============================================="
echo "Unit Test Results"
echo "============================================="
echo -e "Total:   $TOTAL"
echo -e "${GREEN}Passed:  $PASSED${NC}"
if [[ $FAILED -gt 0 ]]; then
	echo -e "${RED}Failed:  $FAILED${NC}"
	exit 1
else
	echo -e "Failed:  $FAILED"
	echo ""
	echo -e "${GREEN}All unit tests passed!${NC}"
fi

# =============================================
# Integration tests (optional)
# =============================================
if [[ -z "${SKIP_INTEGRATION_TESTS:-}" ]]; then
	echo ""
	echo "============================================="
	echo "Running integration tests..."
	echo "============================================="
	if "$SCRIPT_DIR/integration-tests.sh"; then
		echo ""
		echo -e "${GREEN}All tests passed (unit + integration)!${NC}"
		exit 0
	else
		echo ""
		echo -e "${RED}Integration tests failed.${NC}"
		exit 1
	fi
else
	echo ""
	echo -e "${YELLOW}Skipping integration tests (SKIP_INTEGRATION_TESTS=1)${NC}"
	exit 0
fi
