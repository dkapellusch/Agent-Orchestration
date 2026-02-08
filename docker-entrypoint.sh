#!/usr/bin/env bash
# docker-entrypoint.sh - Entrypoint for agent-sandbox container
# Syncs shared agents before running command

set -euo pipefail

# Sync shared agents to workspace if they're mounted
if [[ -d /opt/shared-agents ]] && [[ -d /workspace ]]; then
	mkdir -p /workspace/.opencode/agents
	# Copy shared agents (preserves project overrides by checking if file exists)
	for agent_file in /opt/shared-agents/*.md; do
		[[ -e "$agent_file" ]] || continue
		dest="/workspace/.opencode/agents/$(basename "$agent_file")"
		[[ ! -f "$dest" ]] && cp "$agent_file" "$dest"
	done
fi

# Execute the command
exec "$@"
