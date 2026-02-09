#!/usr/bin/env bash
# model.sh - Model selection, tiering, and rate limiting
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/model.sh"
#
# Requires: core.sh (for locking and utilities)
#
# Provides:
# - Model tier selection with fallbacks
# - Rate limit tracking and detection
# - Configuration loading

# Ensure strict mode if not already set by parent
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -euo pipefail

# Ensure core.sh is sourced
if ! declare -f acquire_lock &>/dev/null; then
	source "$(dirname "${BASH_SOURCE[0]}")/core.sh"
fi

# ============================================================================
# Model Selection
# ============================================================================

_DISCOVERED_OPENCODE_MODELS=""

# Discover available opencode models dynamically
# Runs `opencode models --verbose`, picks active+toolcall models released within
# 9 months, keeps only the latest per family, filtered by enabled_providers from config.
# Usage: discover_opencode_models [config_file]
# Outputs one model ID per line (e.g. "anthropic/claude-opus-4-6")
discover_opencode_models() {
	if [[ -n "$_DISCOVERED_OPENCODE_MODELS" ]]; then
		echo "$_DISCOVERED_OPENCODE_MODELS"
		return 0
	fi

	local config_file=${1:-""}
	local raw
	raw=$(opencode models --verbose 2>/dev/null) || return 1
	[[ -z "$raw" ]] && return 1

	local cutoff
	cutoff=$(date -v-9m +%Y-%m-%d 2>/dev/null || date -d '9 months ago' +%Y-%m-%d 2>/dev/null) || return 1

	local providers_json="[]"
	if [[ -n "$config_file" ]] && [[ -f "$config_file" ]]; then
		providers_json=$(jq -c '.enabled_providers // []' "$config_file" 2>/dev/null || echo "[]")
	fi

	_DISCOVERED_OPENCODE_MODELS=$(echo "$raw" | sed 's/\x1b\[[0-9;]*m//g' | python3 -c "
import sys, json, re
from collections import defaultdict

content = sys.stdin.read()
cutoff = '$cutoff'
providers = json.loads('$providers_json')
lines = content.split('\n')
models = []
current_id = None
current_json = ''

for line in lines:
    if re.match(r'^[a-zA-Z].*/', line) and not line.strip().startswith('{'):
        if current_id and current_json.strip():
            try:
                obj = json.loads(current_json)
                obj['_pm'] = current_id
                models.append(obj)
            except json.JSONDecodeError:
                pass
        current_id = line.strip()
        current_json = ''
    else:
        current_json += line + '\n'
if current_id and current_json.strip():
    try:
        obj = json.loads(current_json)
        obj['_pm'] = current_id
        models.append(obj)
    except json.JSONDecodeError:
        pass

def matches_provider(pm, providers):
    if not providers:
        return True
    prefix = pm.split('/')[0]
    return prefix in providers

filtered = [m for m in models
    if m.get('status') == 'active'
    and m.get('capabilities', {}).get('toolcall', False)
    and not re.search(r'embed|tts|image|live|audio', m.get('_pm', ''), re.I)
    and m.get('release_date', '') >= cutoff
    and matches_provider(m.get('_pm', ''), providers)]

families = defaultdict(list)
for m in filtered:
    families[m.get('family', 'unknown')].append(m)

result = [max(members, key=lambda x: x.get('release_date', ''))
          for members in families.values()]
result.sort(key=lambda x: x.get('release_date', ''), reverse=True)

for m in result:
    print(m['_pm'])
" 2>/dev/null) || return 1

	[[ -z "$_DISCOVERED_OPENCODE_MODELS" ]] && return 1
	echo "$_DISCOVERED_OPENCODE_MODELS"
}

# Get models for a tier from config (agent-aware)
# Usage: get_models_for_tier "high" "/path/to/config.json" ["opencode"|"claudecode"]
get_models_for_tier() {
	local tier=$1
	local config_file=$2
	local agent=${3:-opencode}

	if [[ "$tier" == "all" && "$agent" == "opencode" ]]; then
		local discovered
		discovered=$(discover_opencode_models "$config_file" 2>/dev/null) || true
		if [[ -n "$discovered" ]]; then
			echo "$discovered"
			return 0
		fi
	fi

	jq -r --arg agent "$agent" --arg tier "$tier" '.agents[$agent].tiers[$tier].models[] // .tiers[$tier].models[] // empty' "$config_file"
}

# Get next available model from a tier (randomized selection with optional fallback)
# Usage: get_next_available_model "high" "/path/to/config.json" "/path/to/rate-limits.json" [tier_fallback] [agent]
# Returns: model name on success, exits with 1 if no models available
get_next_available_model() {
	local tier=$1
	local config_file=$2
	local rate_limits_file=$3
	local tier_fallback=${4:-false}
	local agent=${5:-opencode}

	local models
	models=$(get_models_for_tier "$tier" "$config_file" "$agent" | shuffle_lines)

	while IFS= read -r model; do
		[[ -z "$model" ]] && continue
		is_model_rate_limited "$model" "$rate_limits_file" && continue
		echo "$model"
		return 0
	done <<<"$models"

	# Fallback to other tiers if enabled
	if [[ "$tier_fallback" == "true" ]]; then
		local fallback_tiers=""
		case "$tier" in
		high) fallback_tiers="medium low" ;;
		medium) fallback_tiers="high low" ;;
		low) fallback_tiers="medium high" ;;
		esac
		for fb_tier in $fallback_tiers; do
			models=$(get_models_for_tier "$fb_tier" "$config_file" "$agent" | shuffle_lines)
			while IFS= read -r model; do
				[[ -z "$model" ]] && continue
				is_model_rate_limited "$model" "$rate_limits_file" && continue
				echo "$model"
				return 0
			done <<<"$models"
		done
	fi
	return 1
}

# ============================================================================
# Rate Limiting
# ============================================================================

# Check if model is rate-limited
# Usage: is_model_rate_limited "model-name" "/path/to/rate-limits.json"
is_model_rate_limited() {
	local model=$1
	local rate_limits_file=$2
	local now
	now=$(date +%s)
	local until
	until=$(jq -r --arg model "$model" '.[$model] // 0' "$rate_limits_file")
	[[ $until -gt $now ]]
}

# Mark model as rate-limited (thread-safe with file locking)
# Usage: mark_model_rate_limited "model-name" 900 "/path/to/rate-limits.json"
mark_model_rate_limited() {
	local model=$1
	local cooldown=$2
	local rate_limits_file=$3
	local until=$(($(date +%s) + cooldown))

	locked_json_update "$rate_limits_file" --arg model "$model" --argjson until "$until" '.[$model] = $until'

	echo "Warning: Model $model rate-limited until $(format_time_display $until)"
}

# Check for rate limit error in output
# Usage: is_rate_limit_error "$output" [config_file]
# Only checks last 50 lines to avoid false positives from file contents
is_rate_limit_error() {
	local output=$1
	local config_file=${2:-""}

	# Only check last 50 lines - rate limit errors appear at the end, not in file contents
	local tail_output
	tail_output=$(echo "$output" | tail -50)

	# Try to load patterns from config if provided and file exists
	local patterns=""
	if [[ -n "$config_file" ]] && [[ -f "$config_file" ]]; then
		# Build regex from config patterns (join with |)
		patterns=$(jq -r '.rateLimitPatterns // [] | join("|")' "$config_file" 2>/dev/null || echo "")
	fi

	# Fallback to hardcoded patterns if config not available
	# Note: Be very specific to avoid false positives from code content
	if [[ -z "$patterns" ]]; then
		patterns='rate.?limit.*(error|exceeded|hit|reached)|error.*(rate.?limit|status.*429)|status.?code.*429|HTTP[/ ]429|429 Too Many Requests|quota.*(exceeded|exhausted)|ResourceExhausted|RateLimitError|ThrottlingException'
	fi

	echo "$tail_output" | grep -qiE "$patterns"
}

# ============================================================================
# Configuration
# ============================================================================

# Load default configuration values from config.json
# Usage: load_config_defaults "/path/to/config.json"
# Sets global variables: DEFAULT_TIER, DEFAULT_COOLDOWN
load_config_defaults() {
	local config_file=$1

	if [[ -f "$config_file" ]]; then
		DEFAULT_TIER="default"
		DEFAULT_COOLDOWN=$(jq -r '.defaults.cooldownSeconds // 900' "$config_file")
	else
		DEFAULT_TIER="default"
		DEFAULT_COOLDOWN=900
	fi
}

# ============================================================================
# Concurrency Control (for parallel agent spawns like GSD)
# ============================================================================

# Get max concurrent slots for a model
# Usage: get_model_concurrency_limit "model-name" "/path/to/config.json"
# Returns: max concurrent slots (defaults to 3)
get_model_concurrency_limit() {
	local model=$1
	local config_file=$2
	local default_limit=3

	if [[ -f "$config_file" ]]; then
		local limit
		limit=$(jq -r --arg model "$model" --argjson default "$default_limit" '.concurrency.modelLimits[$model] // .concurrency.defaultMaxSlots // $default' "$config_file")
		echo "$limit"
	else
		echo "$default_limit"
	fi
}

# Get current slot count for a model
# Usage: get_model_slot_count "model-name" "/path/to/model-slots.json"
# Returns: current number of slots in use
get_model_slot_count() {
	local model=$1
	local slots_file=$2

	if [[ ! -f "$slots_file" ]]; then
		echo "0"
		return
	fi

	local count
	count=$(jq -r --arg model "$model" '.[$model].count // 0' "$slots_file")
	echo "$count"
}

# Acquire a model slot (blocks until available or timeout)
# Usage: acquire_model_slot "model-name" "/path/to/config.json" "/path/to/model-slots.json" [timeout_secs]
# Returns: 0 on success, 1 on timeout
# Creates a unique slot ID stored in ACQUIRED_SLOT_ID variable
acquire_model_slot() {
	local model=$1
	local config_file=$2
	local slots_file=$3
	local timeout_secs=${4:-300}  # Default 5 minute timeout

	local max_slots
	max_slots=$(get_model_concurrency_limit "$model" "$config_file")

	local slot_id
	slot_id="$$-$(date +%s)-$RANDOM"

	local start_time
	start_time=$(date +%s)

	# Add retry counter as safety net alongside time-based timeout
	# This guards against clock issues (NTP jumps, system time changes)
	local max_retries=10000
	local retry_count=0
	local lock_failures=0

	while true; do
		# Check retry counter (guards against clock issues)
		retry_count=$((retry_count + 1))
		if [[ $retry_count -ge $max_retries ]]; then
			echo "Max retries ($max_retries) reached waiting for model slot: $model" >&2
			return 1
		fi

		# Check timeout
		local now
		now=$(date +%s)
		local elapsed=$((now - start_time))
		if [[ $elapsed -ge $timeout_secs ]]; then
			echo "Timeout waiting for model slot: $model" >&2
			return 1
		fi

		# Try to acquire slot (fail fast on persistent lock issues)
		if ! acquire_lock "$slots_file"; then
			lock_failures=$((lock_failures + 1))
			if [[ $lock_failures -ge 20 ]]; then
				echo "Error: $lock_failures consecutive lock failures for $slots_file, giving up" >&2
				return 1
			fi
			if [[ $((lock_failures % 5)) -eq 0 ]]; then
				echo "Warning: $lock_failures lock acquisition failures for $slots_file" >&2
			fi
			sleep 0.$(($RANDOM % 50 + 10))
			continue
		fi
		lock_failures=0

		# Initialize slots file if needed
		if [[ ! -f "$slots_file" ]] || [[ ! -s "$slots_file" ]]; then
			echo '{}' > "$slots_file"
		fi

		local current_count
		current_count=$(jq -r --arg model "$model" '.[$model].count // 0' "$slots_file")

		if [[ $current_count -lt $max_slots ]]; then
			# Acquire the slot
			local tmp_file
			tmp_file=$(mktemp)
			jq --arg model "$model" --arg slot_id "$slot_id" \
				'.[$model].count = ((.[$model].count // 0) + 1) | .[$model].slots += [$slot_id]' \
				"$slots_file" > "$tmp_file"
			mv "$tmp_file" "$slots_file"
			release_lock "$slots_file"

			# Export slot ID for later release
			ACQUIRED_SLOT_ID="$slot_id"
			return 0
		fi

		release_lock "$slots_file"

		# Wait before retry (with jitter)
		sleep 0.$(($RANDOM % 50 + 10))
	done
}

# Release a model slot
# Usage: release_model_slot "model-name" "/path/to/model-slots.json" [slot_id]
# If slot_id not provided, uses ACQUIRED_SLOT_ID
release_model_slot() {
	local model=$1
	local slots_file=$2
	# Use ${ACQUIRED_SLOT_ID:-} to safely handle unset variable under set -u
	local slot_id=${3:-${ACQUIRED_SLOT_ID:-}}

	if [[ -z "$slot_id" ]]; then
		echo "Warning: No slot ID to release for model $model" >&2
		return 1
	fi

	if [[ ! -f "$slots_file" ]]; then
		return 0
	fi

	locked_json_update "$slots_file" --arg model "$model" --arg slot_id "$slot_id" \
		'.[$model].count = ([(.[$model].count // 1) - 1, 0] | max) | .[$model].slots = ((.[$model].slots // []) | map(select(. != $slot_id)))'

	# Clear the global slot ID
	unset ACQUIRED_SLOT_ID
}

# Check if model has available slots (non-blocking)
# Usage: has_available_slot "model-name" "/path/to/config.json" "/path/to/model-slots.json"
# Returns: 0 if slot available, 1 if at capacity
has_available_slot() {
	local model=$1
	local config_file=$2
	local slots_file=$3

	local max_slots
	max_slots=$(get_model_concurrency_limit "$model" "$config_file")

	local current_count
	current_count=$(get_model_slot_count "$model" "$slots_file")

	[[ $current_count -lt $max_slots ]]
}

# Clean up stale slots (slots from dead processes)
# Usage: cleanup_stale_slots "/path/to/model-slots.json"
# Removes slots whose process ID no longer exists
cleanup_stale_slots() {
	local slots_file=$1

	if [[ ! -f "$slots_file" ]]; then
		return 0
	fi

	acquire_lock "$slots_file" || return 1

	# Collect alive PIDs from all slots
	local alive_pids=""
	local all_slot_ids
	all_slot_ids=$(jq -r '[.[].slots // [] | .[]] | .[]' "$slots_file" 2>/dev/null)
	while IFS= read -r slot_id; do
		[[ -z "$slot_id" ]] && continue
		local pid
		pid=$(echo "$slot_id" | cut -d'-' -f1)
		if kill -0 "$pid" 2>/dev/null; then
			alive_pids+="${slot_id}\n"
		fi
	done <<< "$all_slot_ids"

	# Single jq pass to filter all models at once
	local alive_json
	alive_json=$(printf '%b' "$alive_pids" | jq -Rs '[split("\n") | .[] | select(length > 0)]' 2>/dev/null || echo '[]')

	jq --argjson alive "$alive_json" '
		to_entries | map({
			key: .key,
			value: {
				slots: ([.value.slots // [] | .[] | select(. as $s | $alive | index($s))]),
				count: ([.value.slots // [] | .[] | select(. as $s | $alive | index($s))] | length)
			}
		}) | from_entries
	' "$slots_file" > "${slots_file}.tmp" && mv "${slots_file}.tmp" "$slots_file"

	release_lock "$slots_file"
}
