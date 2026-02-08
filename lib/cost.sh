#!/usr/bin/env bash
# cost.sh - Cost tracking functions for OpenCode and Claude Code
# shellcheck disable=SC2034  # Variables used by sourcing scripts

# Ensure strict mode if not already set by parent
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -euo pipefail

# Extract cost and tokens from an OpenCode session export
# Args: session_id
# Returns: JSON object with cost and token breakdown
# Always returns exit code 0 to avoid breaking set -e scripts
_get_opencode_session_data() {
	local session_id="$1"

	if [[ -z "$session_id" ]]; then
		echo '{"cost":0,"tokens":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0}}'
		return 0
	fi

	local export_data
	export_data=$(opencode export "$session_id" 2>/dev/null) || true

	if [[ -z "$export_data" ]]; then
		echo '{"cost":0,"tokens":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0}}'
		return 0
	fi

	# Extract both cost and tokens in a single awk pass for efficiency
	# OpenCode's JSON export has invalid control characters, so we use awk instead of jq
	local result
	result=$(echo "$export_data" | awk '
		/\"type\": *\"step-finish\"/ { in_step=1; lines_after=0 }
		in_step { lines_after++ }
		in_step && /\"cost\":/ { match($0, /[0-9.]+/); total_cost += substr($0, RSTART, RLENGTH) }
		in_step && /\"input\":/ { match($0, /[0-9]+/); input += substr($0, RSTART, RLENGTH) }
		in_step && /\"output\":/ { match($0, /[0-9]+/); output += substr($0, RSTART, RLENGTH) }
		in_step && /\"read\":/ { match($0, /[0-9]+/); cache_read += substr($0, RSTART, RLENGTH) }
		in_step && /\"write\":/ { match($0, /[0-9]+/); cache_write += substr($0, RSTART, RLENGTH) }
		in_step && lines_after > 15 { in_step=0 }
		END {
			cost = total_cost+0
			inp = input+0
			out = output+0
			cr = cache_read+0
			cw = cache_write+0
			printf "{\"cost\":%f,\"tokens\":{\"input\":%d,\"output\":%d,\"cacheRead\":%d,\"cacheWrite\":%d}}\n", cost, inp, out, cr, cw
		}
	') || true

	if [[ -n "$result" ]]; then
		echo "$result"
	else
		echo '{"cost":0,"tokens":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0}}'
	fi
}

# Extract cost from an OpenCode session
# Args: session_id
# Returns: cost as decimal (e.g., "0.1234"), or "0" if not found
# Always returns exit code 0 to avoid breaking set -e scripts
get_opencode_session_cost() {
	local session_id="$1"
	local data
	data=$(_get_opencode_session_data "$session_id")
	echo "$data" | jq -r '.cost // 0'
}

# Extract token counts from an OpenCode session
# Args: session_id
# Returns: JSON object with token breakdown
# Always returns exit code 0 to avoid breaking set -e scripts
get_opencode_session_tokens() {
	local session_id="$1"
	local data tokens
	data=$(_get_opencode_session_data "$session_id")
	tokens=$(echo "$data" | jq -c '.tokens // {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}' 2>/dev/null)
	if [[ -n "$tokens" ]]; then
		echo "$tokens"
	else
		echo '{"input":0,"output":0,"cacheRead":0,"cacheWrite":0}'
	fi
}

# ============================================================================
# Claude Code Cost Tracking
# ============================================================================

# Extract cost from Claude Code stream-json output file
# Args: output_file
# Returns: cost as decimal (e.g., "0.0300"), or "0" if not found
get_claude_session_cost() {
	local output_file="$1"

	if [[ -z "$output_file" ]] || [[ ! -f "$output_file" ]]; then
		echo "0"
		return 0
	fi

	local cost
	cost=$(grep -F '"type":"result"' "$output_file" 2>/dev/null \
		| tail -1 \
		| jq -r '.total_cost_usd // 0' 2>/dev/null) || true

	if [[ -z "$cost" ]] || [[ "$cost" == "null" ]]; then
		# Try with space after colon
		cost=$(grep -F '"type": "result"' "$output_file" 2>/dev/null \
			| tail -1 \
			| jq -r '.total_cost_usd // 0' 2>/dev/null) || true
	fi

	echo "${cost:-0}"
}

# Extract duration from Claude Code stream-json output file
# Args: output_file
# Returns: duration in ms, or "0" if not found
get_claude_session_duration() {
	local output_file="$1"

	if [[ -z "$output_file" ]] || [[ ! -f "$output_file" ]]; then
		echo "0"
		return 0
	fi

	local duration
	duration=$(grep -F '"type":"result"' "$output_file" 2>/dev/null \
		| tail -1 \
		| jq -r '.duration_ms // 0' 2>/dev/null) || true

	if [[ -z "$duration" ]] || [[ "$duration" == "null" ]]; then
		duration=$(grep -F '"type": "result"' "$output_file" 2>/dev/null \
			| tail -1 \
			| jq -r '.duration_ms // 0' 2>/dev/null) || true
	fi

	echo "${duration:-0}"
}

# Record a Claude Code iteration cost
# Args: ralph_session working_dir iteration cost
# Thread-safe via file locking to prevent corruption from parallel GSD tasks
record_claude_session() {
	local ralph_session="$1"
	local working_dir="$2"
	local iteration="$3"
	local cost="$4"

	local costs_file="$working_dir/.ralph/$ralph_session/claude-costs.jsonl"
	mkdir -p "$(dirname "$costs_file")"

	local json_line
	json_line=$(jq -n -c \
		--argjson iter "$iteration" \
		--argjson cost "$cost" \
		--arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		'{iteration: $iter, cost: $cost, timestamp: $timestamp}')

	acquire_lock "$costs_file" || return 1
	echo "$json_line" >>"$costs_file"
	release_lock "$costs_file"
}

# Get total cost for a Claude Code ralph-loop session
# Args: ralph_session working_dir
# Returns: total cost as decimal
get_ralph_claude_session_cost() {
	local ralph_session="$1"
	local working_dir="$2"

	local costs_file="$working_dir/.ralph/$ralph_session/claude-costs.jsonl"

	if [[ ! -f "$costs_file" ]]; then
		echo "0"
		return
	fi

	jq -s '[.[].cost] | add // 0' "$costs_file"
}

# ============================================================================
# OpenCode Cost Tracking
# ============================================================================

# Record OpenCode session ID for a ralph-loop iteration
# Args: ralph_session working_dir opencode_session iteration
# Thread-safe via file locking to prevent corruption from parallel GSD tasks
record_opencode_session() {
	local ralph_session="$1"
	local working_dir="$2"
	local opencode_session="$3"
	local iteration="$4"

	local sessions_file="$working_dir/.ralph/$ralph_session/opencode-sessions.txt"
	mkdir -p "$(dirname "$sessions_file")"

	acquire_lock "$sessions_file" || return 1
	echo "$iteration:$opencode_session" >>"$sessions_file"
	release_lock "$sessions_file"
}

# Get total cost for a ralph-loop session (sum of all iterations)
# Args: ralph_session working_dir
# Returns: total cost as decimal
get_ralph_session_cost() {
	local ralph_session="$1"
	local working_dir="$2"

	local sessions_file="$working_dir/.ralph/$ralph_session/opencode-sessions.txt"

	if [[ ! -f "$sessions_file" ]]; then
		echo "0"
		return
	fi

	local total=0
	while IFS=: read -r iteration opencode_session; do
		[[ -z "$opencode_session" ]] && continue
		local cost
		cost=$(get_opencode_session_cost "$opencode_session")
		total=$(awk -v t="$total" -v c="${cost:-0}" 'BEGIN {print t + c}')
	done <"$sessions_file"

	printf "%.4f" "$total"
}

# Check budget and return status
# Args: current_cost budget_limit [alert_threshold]
# Returns: "exceeded", "warning:PERCENT", or "ok"
check_budget() {
	local current_cost="$1"
	local budget_limit="$2"
	local alert_threshold="${3:-0.80}"

	# Check if exceeded using awk
	local exceeded
	exceeded=$(awk -v cost="$current_cost" -v limit="$budget_limit" 'BEGIN {print (cost >= limit) ? 1 : 0}')
	if [[ "$exceeded" == "1" ]]; then
		echo "exceeded"
		return 1
	fi

	# Check if approaching threshold
	local threshold_amount
	threshold_amount=$(awk -v limit="$budget_limit" -v thresh="$alert_threshold" 'BEGIN {print limit * thresh}')
	local warning
	warning=$(awk -v cost="$current_cost" -v thresh="$threshold_amount" 'BEGIN {print (cost >= thresh) ? 1 : 0}')
	if [[ "$warning" == "1" ]]; then
		local percent
		percent=$(awk -v cost="$current_cost" -v limit="$budget_limit" 'BEGIN {printf "%.0f", cost / limit * 100}')
		echo "warning:$percent"
		return 0
	fi

	echo "ok"
	return 0
}

# Display cost inline after iteration
# Args: iteration_cost total_cost [budget_limit]
display_iteration_cost() {
	local iteration_cost="$1"
	local total_cost="$2"
	local budget_limit="${3:-}"

	printf "Cost: \$%.4f (iter) | \$%.4f (total)" "$iteration_cost" "$total_cost"

	if [[ -n "$budget_limit" ]]; then
		local budget_status
		budget_status=$(check_budget "$total_cost" "$budget_limit")
		case "$budget_status" in
		exceeded)
			echo " | BUDGET EXCEEDED"
			;;
		warning:*)
			local percent="${budget_status#warning:}"
			printf " | %s%% of \$%.2f used ⚠️\n" "$percent" "$budget_limit"
			;;
		*)
			echo ""
			;;
		esac
	else
		echo ""
	fi
}

# Format number with thousands separators
# Args: number
_format_number() {
	local num="$1"
	# Use printf with grouping if locale supports it, fallback to manual formatting
	local formatted
	formatted=$(printf "%'d" "$num" 2>/dev/null) || formatted="$num"
	# If printf didn't add separators, do it manually
	if [[ "$formatted" == "$num" ]] && [[ $num -ge 1000 ]]; then
		formatted=$(echo "$num" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')
	fi
	echo "$formatted"
}

# Display token usage inline
# Args: tokens_json
display_token_usage() {
	local tokens_json="$1"

	local input output cache_read cache_write
	read -r input output cache_read cache_write < <(echo "$tokens_json" | jq -r '[.input // 0, .output // 0, .cacheRead // 0, .cacheWrite // 0] | @tsv')

	# Format with thousands separators
	printf "Tokens: %s in, %s out" "$(_format_number "$input")" "$(_format_number "$output")"

	if [[ $cache_read -gt 0 ]] || [[ $cache_write -gt 0 ]]; then
		printf " | cache: %s read, %s write" "$(_format_number "$cache_read")" "$(_format_number "$cache_write")"
	fi
	echo ""
}

# Get the most recent OpenCode session ID
# Returns: session_id or empty string if none found
get_latest_opencode_session() {
	opencode session list 2>/dev/null | tail -n +3 | head -1 | awk '{print $1}'
}

# Display budget exceeded warning
# Args: current_cost budget_limit
display_budget_exceeded() {
	local current_cost="$1"
	local budget_limit="$2"

	echo ""
	echo "╔════════════════════════════════════════════╗"
	printf "║  %-42s║\n" "BUDGET EXCEEDED"
	printf "║  %-42s║\n" "$(printf 'Current: $%.2f  Limit: $%.2f' "$current_cost" "$budget_limit")"
	echo "╚════════════════════════════════════════════╝"
	echo ""
}

# Save cost summary to file
# Args: ralph_session working_dir
save_cost_summary() {
	local ralph_session="$1"
	local working_dir="$2"

	local sessions_file="$working_dir/.ralph/$ralph_session/opencode-sessions.txt"
	local summary_file="$working_dir/.ralph/$ralph_session/cost-summary.json"

	if [[ ! -f "$sessions_file" ]]; then
		echo '{"totalCost":0,"iterations":[]}' >"$summary_file"
		return
	fi

	local total_cost=0
	local iterations_json="[]"

	while IFS=: read -r iteration opencode_session; do
		[[ -z "$opencode_session" ]] && continue

		# Get both cost and tokens in a single call for efficiency
		local session_data cost tokens
		session_data=$(_get_opencode_session_data "$opencode_session")
		cost=$(echo "$session_data" | jq -r '.cost')
		tokens=$(echo "$session_data" | jq -c '.tokens')
		total_cost=$(awk -v t="$total_cost" -v c="${cost:-0}" 'BEGIN {printf "%.10f", t + c}')

		# Add to iterations array
		iterations_json=$(echo "$iterations_json" | jq \
			--argjson iter "$iteration" \
			--arg session "$opencode_session" \
			--argjson cost "$cost" \
			--argjson tokens "$tokens" \
			'. += [{"iteration": $iter, "sessionId": $session, "cost": $cost, "tokens": $tokens}]')
	done <"$sessions_file"

	# Save summary
	if ! jq -n \
		--argjson total "$total_cost" \
		--argjson iterations "$iterations_json" \
		'{"totalCost": $total, "iterations": $iterations}' >"$summary_file"; then
		echo "Warning: Failed to save cost summary to $summary_file" >&2
	fi
}

# ============================================================================
# Global Cost Ledger - Aggregation by Date and Spec
# ============================================================================

# Get the global ledger directory
# Returns: path to ledger directory
get_ledger_dir() {
	local script_dir
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
	echo "$script_dir/state/costs"
}

# Record a completed session to the global ledger
# Args: ralph_session spec_name total_cost working_dir [model]
# Thread-safe via file locking to prevent corruption from parallel GSD tasks
record_to_ledger() {
	local ralph_session="$1"
	local spec_name="$2"
	local total_cost="$3"
	local working_dir="$4"
	local model="${5:-unknown}"

	local ledger_dir
	ledger_dir=$(get_ledger_dir)
	mkdir -p "$ledger_dir"

	local ledger_file="$ledger_dir/ledger.jsonl"
	local date_str
	date_str=$(date +%Y-%m-%d)
	local timestamp
	timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

	# Sanitize spec name (first 100 chars, no newlines)
	local clean_spec
	clean_spec=$(echo "$spec_name" | tr '\n' ' ' | cut -c1-100)

	# Build JSON line first
	local json_line
	json_line=$(jq -n -c \
		--arg session "$ralph_session" \
		--arg spec "$clean_spec" \
		--argjson cost "$total_cost" \
		--arg date "$date_str" \
		--arg timestamp "$timestamp" \
		--arg project "$working_dir" \
		--arg model "$model" \
		'{session: $session, spec: $spec, cost: $cost, date: $date, timestamp: $timestamp, project: $project, model: $model}')

	# Append to ledger with locking
	acquire_lock "$ledger_file" || return 1
	echo "$json_line" >>"$ledger_file"
	release_lock "$ledger_file"
}

# Get costs aggregated by date
# Args: [days_back] - number of days to look back (default: 30)
# Returns: JSON array of {date, cost, sessions}
get_costs_by_date() {
	local days_back="${1:-30}"
	local ledger_dir
	ledger_dir=$(get_ledger_dir)
	local ledger_file="$ledger_dir/ledger.jsonl"

	if [[ ! -f "$ledger_file" ]]; then
		echo "[]"
		return
	fi

	local cutoff_date
	cutoff_date=$(get_cutoff_date "$days_back")

	# Aggregate by date
	jq -s --arg cutoff "$cutoff_date" '
		[.[] | select(.date >= $cutoff)]
		| group_by(.date)
		| map({
			date: .[0].date,
			cost: (map(.cost) | add),
			sessions: length,
			specs: (map(.spec) | unique | length)
		})
		| sort_by(.date)
		| reverse
	' "$ledger_file"
}

# Get costs aggregated by spec
# Args: [days_back] - number of days to look back (default: 30)
# Returns: JSON array of {spec, cost, sessions, lastUsed}
get_costs_by_spec() {
	local days_back="${1:-30}"
	local ledger_dir
	ledger_dir=$(get_ledger_dir)
	local ledger_file="$ledger_dir/ledger.jsonl"

	if [[ ! -f "$ledger_file" ]]; then
		echo "[]"
		return
	fi

	local cutoff_date
	cutoff_date=$(get_cutoff_date "$days_back")

	# Aggregate by spec
	jq -s --arg cutoff "$cutoff_date" '
		[.[] | select(.date >= $cutoff)]
		| group_by(.spec)
		| map({
			spec: .[0].spec,
			cost: (map(.cost) | add),
			sessions: length,
			lastUsed: (map(.date) | max)
		})
		| sort_by(.cost)
		| reverse
	' "$ledger_file"
}

# Get costs aggregated by project
# Args: [days_back] - number of days to look back (default: 30)
# Returns: JSON array of {project, cost, sessions}
get_costs_by_project() {
	local days_back="${1:-30}"
	local ledger_dir
	ledger_dir=$(get_ledger_dir)
	local ledger_file="$ledger_dir/ledger.jsonl"

	if [[ ! -f "$ledger_file" ]]; then
		echo "[]"
		return
	fi

	local cutoff_date
	cutoff_date=$(get_cutoff_date "$days_back")

	# Aggregate by project
	jq -s --arg cutoff "$cutoff_date" '
		[.[] | select(.date >= $cutoff)]
		| group_by(.project)
		| map({
			project: .[0].project,
			cost: (map(.cost) | add),
			sessions: length,
			specs: (map(.spec) | unique | length)
		})
		| sort_by(.cost)
		| reverse
	' "$ledger_file"
}

# Get total spend for a date range
# Args: [days_back]
# Returns: total cost as decimal
get_total_spend() {
	local days_back="${1:-30}"
	local ledger_dir
	ledger_dir=$(get_ledger_dir)
	local ledger_file="$ledger_dir/ledger.jsonl"

	if [[ ! -f "$ledger_file" ]]; then
		echo "0"
		return
	fi

	local cutoff_date
	cutoff_date=$(get_cutoff_date "$days_back")

	jq -s --arg cutoff "$cutoff_date" '
		[.[] | select(.date >= $cutoff) | .cost] | add // 0
	' "$ledger_file"
}

# Get spend for a specific date
# Args: date (YYYY-MM-DD)
# Returns: JSON with date details
get_daily_spend() {
	local target_date="${1:-$(date +%Y-%m-%d)}"
	local ledger_dir
	ledger_dir=$(get_ledger_dir)
	local ledger_file="$ledger_dir/ledger.jsonl"

	if [[ ! -f "$ledger_file" ]]; then
		echo '{"date":"'"$target_date"'","cost":0,"sessions":0,"specs":[]}'
		return
	fi

	jq -s --arg date "$target_date" '
		[.[] | select(.date == $date)]
		| {
			date: $date,
			cost: (map(.cost) | add // 0),
			sessions: length,
			specs: (map({spec: .spec, cost: .cost}) | group_by(.spec) | map({spec: .[0].spec, cost: (map(.cost) | add)}))
		}
	' "$ledger_file"
}
