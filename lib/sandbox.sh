#!/usr/bin/env bash
# sandbox.sh - Sandbox execution and state management
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh"
#
# Provides:
# - Sandbox setup verification
# - State directory initialization
# - Sandbox execution wrapper

# Ensure strict mode if not already set by parent
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && set -euo pipefail

# ============================================================================
# State Directory Management
# ============================================================================

# Initialize state directory with optional extra JSON files
# Usage: init_state_dir "/path/to/state" ["extra1.json" "extra2.json" ...]
# Creates state dir, rate-limits.json, and any extra files specified
init_state_dir() {
	local state_dir=$1
	shift

	mkdir -p "$state_dir"

	# Always create rate-limits.json
	local rate_limits="$state_dir/rate-limits.json"
	[[ -f "$rate_limits" ]] || echo '{}' > "$rate_limits"

	# Create any extra JSON files requested
	for extra_file in "$@"; do
		local full_path="$state_dir/$extra_file"
		if [[ ! -f "$full_path" ]]; then
			# Default content depends on file type
			if [[ "$extra_file" == "queue.json" ]]; then
				echo '{"tasks":[]}' > "$full_path"
			elif [[ "$extra_file" == "model-slots.json" ]]; then
				echo '{}' > "$full_path"
			else
				echo '{}' > "$full_path"
			fi
		fi
	done
}

# ============================================================================
# Sandbox Setup & Verification
# ============================================================================

# Check sandbox prerequisites
# Usage: check_sandbox_setup "/path/to/contai-script"
# Returns 0 if sandbox is ready, 1 with error message if not
check_sandbox_setup() {
	local contai_script=$1

	if [[ ! -f "$contai_script" ]]; then
		echo "Error: Sandbox mode requires agent-sandbox to be set up."
		echo "Run: ./setup/sandbox.sh"
		return 1
	fi

	if ! run_with_timeout 5 docker info &>/dev/null; then
		echo "Error: Docker is not running (required for sandbox mode)."
		return 1
	fi

	return 0
}
