#!/usr/bin/env bash
# core.sh - Core utilities for agent-orchestrator
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/core.sh"
#
# Provides:
# - File locking (directory-based, cross-platform)
# - Thread-safe JSON operations
# - Cross-platform utilities

# Ensure strict mode if not already set by parent
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -euo pipefail

# Cache uname for performance (OS doesn't change during execution)
_UNAME_CACHE="$(uname)"

# ============================================================================
# File Locking
# ============================================================================

# Acquire a lock on a file (creates lockdir)
# Usage: acquire_lock "lockfile"
# Returns 0 on success, 1 on timeout
acquire_lock() {
	local lockfile="$1"
	local lockdir="${lockfile}.lockdir"
	local max_attempts=200
	local attempt=0

	while ! mkdir "$lockdir" 2>/dev/null; do
		# Check for stale lock (owning process no longer alive or too old)
		local owner_pid
		owner_pid=$(cat "$lockdir/pid" 2>/dev/null || echo "")

		# Check if lock is stale by age (older than 300 seconds)
		if [[ -f "$lockdir/timestamp" ]]; then
			local lock_age timestamp_value
			timestamp_value=$(cat "$lockdir/timestamp" 2>/dev/null)
			# Only use timestamp if it's a valid number, otherwise skip age-based detection
			if [[ -n "$timestamp_value" ]] && [[ "$timestamp_value" =~ ^[0-9]+$ ]]; then
				lock_age=$(( $(date +%s) - timestamp_value ))
				if (( lock_age > 300 )); then
					rm -rf "$lockdir" 2>/dev/null || true
					continue
				fi
			fi
		fi

		# Check if owning process is still alive
		if [[ -n "$owner_pid" ]] && ! kill -0 "$owner_pid" 2>/dev/null; then
			rm -rf "$lockdir" 2>/dev/null || true
			continue
		fi

		attempt=$((attempt + 1))
		if [[ $attempt -ge $max_attempts ]]; then
			echo "ERROR: Could not acquire lock on $lockfile" >&2
			return 1
		fi
		sleep 0.$((RANDOM % 100 + 10))
	done

	# Write PID and timestamp immediately after mkdir succeeds (before any other logic)
	# Critical: These must succeed for the lock to be valid
	if ! echo $$ > "$lockdir/pid" 2>/dev/null; then
		rm -rf "$lockdir" 2>/dev/null || true
		return 1
	fi
	if ! date +%s > "$lockdir/timestamp" 2>/dev/null; then
		rm -f "$lockdir/pid" "$lockdir/timestamp" 2>/dev/null
		rmdir "$lockdir" 2>/dev/null || true
		return 1
	fi
	return 0
}

# Release a lock
# Usage: release_lock "lockfile"
release_lock() {
	local lockfile="$1"
	local lockdir="${lockfile}.lockdir"
	rm -f "$lockdir/pid" "$lockdir/timestamp" 2>/dev/null
	rmdir "$lockdir" 2>/dev/null || true
}

# ============================================================================
# Thread-Safe JSON Operations
# ============================================================================

# Safe JSON update with file locking
# Usage: locked_json_update "file.json" jq_args...
# Example: locked_json_update "data.json" --arg key "value" '.[$key] = "new"'
locked_json_update() {
	local json_file="$1"
	shift

	acquire_lock "$json_file" || return 1

	local tmp_file
	tmp_file=$(mktemp)
	if jq "$@" "$json_file" >"$tmp_file" 2>/dev/null; then
		mv "$tmp_file" "$json_file"
		release_lock "$json_file"
		return 0
	else
		rm -f "$tmp_file"
		release_lock "$json_file"
		return 1
	fi
}

# Safe JSON read with file locking (optional, for consistency)
# Usage: locked_json_read "file.json" jq_args...
locked_json_read() {
	local json_file="$1"
	shift

	acquire_lock "$json_file" || return 1
	local result
	result=$(jq "$@" "$json_file")
	local exit_code=$?
	release_lock "$json_file"
	printf '%s\n' "$result"
	return $exit_code
}

# ============================================================================
# Cross-Platform Utilities
# ============================================================================

# Get portable file size (works on macOS and Linux)
# Usage: get_file_size "/path/to/file"
get_file_size() {
	local file=$1
	if [[ "$_UNAME_CACHE" == "Darwin" ]]; then
		stat -f%z "$file" 2>/dev/null || echo "0"
	else
		stat -c%s "$file" 2>/dev/null || echo "0"
	fi
}

# Shuffle lines (cross-platform: works on macOS and Linux)
# Usage: echo "line1\nline2" | shuffle_lines
shuffle_lines() {
	if command -v shuf &>/dev/null; then
		shuf
	else
		# macOS/BSD fallback using awk
		awk 'BEGIN{srand()} {print rand() "\t" $0}' | sort -n | cut -f2-
	fi
}

# Cross-platform timeout command
# Usage: run_with_timeout 300 command args...
# Uses GNU timeout on Linux, gtimeout on macOS (if available), or runs without timeout
run_with_timeout() {
	local timeout_secs=$1
	shift

	if command -v timeout &>/dev/null; then
		timeout "$timeout_secs" "$@"
	elif command -v gtimeout &>/dev/null; then
		gtimeout "$timeout_secs" "$@"
	else
		# No timeout available, just run the command
		"$@"
	fi
}

# Format time for display (cross-platform)
# Usage: format_time_display $unix_timestamp
format_time_display() {
	local timestamp=$1
	if [[ "$_UNAME_CACHE" == "Darwin" ]]; then
		date -r "$timestamp" '+%H:%M:%S'
	else
		date -d "@$timestamp" '+%H:%M:%S'
	fi
}

# Parse ISO 8601 date string to epoch seconds (cross-platform)
# Usage: parse_date_to_epoch "2025-01-01T12:00:00Z"
parse_date_to_epoch() {
	local date_str=$1
	if [[ "$_UNAME_CACHE" == "Darwin" ]]; then
		date -j -f "%Y-%m-%dT%H:%M:%S%z" "$date_str" +%s 2>/dev/null || \
		date -j -f "%Y-%m-%dT%H:%M:%SZ" "$date_str" +%s 2>/dev/null || \
		echo ""
	else
		date -d "$date_str" +%s 2>/dev/null || echo ""
	fi
}

# Format epoch seconds to date string (cross-platform)
# Usage: format_epoch_date $epoch_secs "+%Y-%m-%d"
format_epoch_date() {
	local epoch=$1
	local fmt=${2:-"+%Y-%m-%d"}
	if [[ "$_UNAME_CACHE" == "Darwin" ]]; then
		date -r "$epoch" "$fmt"
	else
		date -d "@$epoch" "$fmt"
	fi
}

# Get file modification time as epoch (cross-platform)
# Usage: get_file_mtime "/path/to/file"
get_file_mtime() {
	local f=$1
	if [[ "$_UNAME_CACHE" == "Darwin" ]]; then
		stat -f %m "$f"
	else
		stat -c %Y "$f"
	fi
}

# Get cutoff date for cost queries (cross-platform)
# Usage: get_cutoff_date [days_back]
# Returns: date string in YYYY-MM-DD format
get_cutoff_date() {
	local days="${1:-30}"
	if [[ "$_UNAME_CACHE" == "Darwin" ]]; then
		date -v-"${days}"d +%Y-%m-%d 2>/dev/null
	else
		date -d "$days days ago" +%Y-%m-%d 2>/dev/null
	fi
}
