#!/usr/bin/env bash
# models.sh - Show available models and their status
# Invoked via: ralph models [command] [agent]

CONFIG="$RALPH_CONFIG"
RATE_LIMITS="$RALPH_STATE_DIR/rate-limits.json"

now=$(date +%s)

usage() {
    cat <<EOF
Usage: ralph models [command] [agent]

Commands:
  list [agent]   List models for an agent (default: all agents)
  get <tier>     Get an available model for tier (opencode only)

Agents: opencode, claudecode

Examples:
  ralph models                    # List all models
  ralph models list opencode      # List opencode models only
  ralph models list claudecode    # List claudecode models only
  ralph models get high           # Get available high-tier model
EOF
}

show_models_for_agent() {
    local agent=$1
    local tier description model until remaining mins secs
    echo "[$agent]"
    printf '=%.0s' {1..40}
    echo

    for tier in high medium low; do
        description=$(jq -r --arg agent "$agent" --arg tier "$tier" '.agents[$agent].tiers[$tier].description // .tiers[$tier].description // ($tier + " tier")' "$CONFIG")
        echo ""
        echo "  $tier tier - $description"

        while IFS= read -r model; do
            [[ -z "$model" ]] && continue
            # Check rate limit status
            if [[ -f "$RATE_LIMITS" ]]; then
                until=$(jq -r --arg model "$model" '.[$model] // 0' "$RATE_LIMITS")
                if [[ $until -gt $now ]]; then
                    remaining=$((until - now))
                    mins=$((remaining / 60))
                    secs=$((remaining % 60))
                    printf "    [RATE LIMITED] %s (%dm %ds remaining)\n" "$model" "$mins" "$secs"
                else
                    printf "    [OK] %s\n" "$model"
                fi
            else
                printf "    [OK] %s\n" "$model"
            fi
        done < <(jq -r --arg agent "$agent" --arg tier "$tier" '.agents[$agent].tiers[$tier].models[] // .tiers[$tier].models[] // empty' "$CONFIG")
    done
    echo ""
}

case "${1:-list}" in
    list)
        agent="${2:-}"
        echo "Agent Orchestrator - Model Status"
        echo "================================="
        echo ""
        if [[ -n "$agent" ]]; then
            show_models_for_agent "$agent"
        else
            for agent in opencode claudecode; do
                show_models_for_agent "$agent"
            done
        fi
        echo "Configuration:"
        echo "  Max retries:  $(jq -r '.defaults.maxRetries' "$CONFIG")"
        echo "  Retry delay:  $(jq -r '.defaults.retryDelaySeconds' "$CONFIG")s"
        echo "  Cooldown:     $(jq -r '.defaults.cooldownSeconds' "$CONFIG")s"
        echo "  Timeout:      $(jq -r '.defaults.timeoutSeconds' "$CONFIG")s"
        ;;
    get)
        tier="${2:-high}"
        [[ -f "$RATE_LIMITS" ]] || echo '{}' > "$RATE_LIMITS"
        get_next_available_model "$tier" "$CONFIG" "$RATE_LIMITS" true "opencode"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
