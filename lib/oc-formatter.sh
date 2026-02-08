#!/usr/bin/env bash
# oc-formatter.sh - Format OpenCode JSON output for human readability
# Reads JSON lines from stdin (opencode run --format json), outputs colored formatted text
#
# Environment:
#   RALPH_VERBOSE=true  - Show full output without truncation
#   NO_COLOR=1          - Disable color output (https://no-color.org/)

# Truncation limits (when not verbose)
TOOL_INPUT_CHARS=200
TOOL_RESULT_CHARS=300

# Check verbose mode
if [[ "${RALPH_VERBOSE:-false}" == "true" ]]; then
    TOOL_INPUT_CHARS=0
    TOOL_RESULT_CHARS=0
fi

# Color support - respect NO_COLOR standard
if [[ -n "${NO_COLOR:-}" ]]; then
    RST="" BOLD="" DIM="" ITAL=""
    RED="" GRN="" YEL="" BLU="" MAG="" CYN="" GRY=""
else
    RST=$'\033[0m' BOLD=$'\033[1m' DIM=$'\033[2m' ITAL=$'\033[3m'
    RED=$'\033[31m' GRN=$'\033[32m' YEL=$'\033[33m' BLU=$'\033[34m'
    MAG=$'\033[35m' CYN=$'\033[36m' GRY=$'\033[90m'
fi

# Extract a simple string value from JSON without forking jq
# Usage: extract_json_string "$json" "key"
# Returns empty string if not found
extract_json_string() {
    local json="$1" key="$2"
    local pattern="\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
    if [[ "$json" =~ $pattern ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # Fast type extraction without forking jq
    case "$line" in
        *'"type":"text"'*|*'"type": "text"'*) type="text" ;;
        *'"type":"tool_use"'*|*'"type": "tool_use"'*) type="tool_use" ;;
        *'"type":"step_finish"'*|*'"type": "step_finish"'*) type="step_finish" ;;
        *) continue ;;
    esac

    case "$type" in
        text)
            text=$(jq -r '.part.text // empty' <<< "$line" 2>/dev/null)
            [[ -n "$text" ]] && echo "$text"
            ;;
        tool_use)
            content=$(jq -r \
                --arg rst "$RST" --arg bold "$BOLD" --arg dim "$DIM" \
                --arg cyn "$CYN" --arg yel "$YEL" --arg red "$RED" \
                --arg mag "$MAG" --arg blu "$BLU" --arg gry "$GRY" \
                --argjson tool_chars "$TOOL_INPUT_CHARS" \
                --argjson result_chars "$TOOL_RESULT_CHARS" \
                '
                # Shorten file paths to last 3 segments
                def short_path:
                    if . == null or . == "" then "?"
                    elif $tool_chars == 0 then .
                    else split("/") |
                        if length > 3 then "…/" + (.[-3:] | join("/"))
                        else join("/") end
                    end;

                # Normalize OC tool name to title case for display
                def display_name:
                    if . == "read" then "Read"
                    elif . == "grep" then "Grep"
                    elif . == "glob" then "Glob"
                    elif . == "edit" then "Edit"
                    elif . == "write" then "Write"
                    elif . == "bash" then "Bash"
                    elif . == "list" then "LS"
                    elif . == "fetch" then "Fetch"
                    else . end;

                .part as $p |
                ($p.tool // "unknown") as $tool |

                # Icon by tool name
                ({"read":"📖","grep":"🔍","glob":"📂","edit":"✏️ ","write":"📝",
                  "bash":"⚡","list":"📁","fetch":"🌐"}[$tool] // "🔧") as $icon |
                # Color by tool category
                (if $tool == "read" or $tool == "glob" or $tool == "grep" or $tool == "list" then $cyn
                 elif $tool == "edit" or $tool == "write" then $yel
                 elif $tool == "bash" then $red
                 elif $tool == "fetch" then $blu
                 else "" end) as $color |

                # Extract meaningful detail (OC uses camelCase input fields)
                ($p.state.input // {}) as $input |
                (if $tool == "read" then
                    ($input.filePath // "" | short_path)
                 elif $tool == "grep" then
                    "/" + ($input.pattern // "") + "/"
                    + (if $input.glob then " {" + $input.glob + "}" else "" end)
                    + (if $input.path then "  " + ($input.path | short_path) else "" end)
                 elif $tool == "glob" then
                    ($input.pattern // "")
                    + (if $input.path then "  " + ($input.path | short_path) else "" end)
                 elif $tool == "edit" then
                    ($input.filePath // "" | short_path)
                 elif $tool == "write" then
                    ($input.filePath // "" | short_path)
                 elif $tool == "bash" then
                    ($input.command // "" | gsub("\n"; " ") |
                        .[0:if $tool_chars > 0 then $tool_chars else 999999 end])
                    + (if $tool_chars > 0 and (($input.command // "") | length) > $tool_chars then "…" else "" end)
                 else
                    ($input | tostring |
                        .[0:if $tool_chars > 0 then $tool_chars else 999999 end])
                    + (if $tool_chars > 0 and (($input | tostring) | length) > $tool_chars then "…" else "" end)
                 end) as $detail |

                # Build tool call line
                ($color + $icon + " " + $bold + ($tool | display_name) + $rst + "  " + $gry + $detail + $rst) as $header |

                # Build result line if tool completed
                (if $p.state.status == "completed" and $p.state.output and ($p.state.output | length) > 0 then
                    if $result_chars == 0 then
                        $gry + "   " + ($p.state.output | tostring) + $rst
                    else
                        $gry + "   " + ($p.state.output | tostring | .[0:$result_chars]) +
                        (if ($p.state.output | tostring | length) > $result_chars then "…" else "" end) + $rst
                    end
                elif $p.state.status == "error" then
                    $red + "   ⚠ " + ($p.state.error // $p.state.output // "unknown error" | tostring) + $rst
                else "" end) as $result |

                if $result != "" then $header + "\n" + $result
                else $header end
                ' <<< "$line" 2>/dev/null)
            [[ -n "$content" ]] && echo "$content"
            ;;
        step_finish)
            # Show cost on final step (reason=stop means conversation ended)
            # Validate JSON first to avoid jq parse errors
            if echo "$line" | jq -e '.part' &>/dev/null; then
                info=$(jq -r \
                    --arg rst "$RST" --arg bold "$BOLD" --arg grn "$GRN" --arg gry "$GRY" '
                    .part as $p |
                    if $p.reason == "stop" then
                        "\n" + $grn + $bold + "✅ Done" + $rst + " " +
                        $gry + "($" + ($p.cost // 0 | tostring) +
                        ", " + (($p.tokens.input // 0) + ($p.tokens.output // 0) | tostring) + " tokens)" + $rst
                    else empty end
                    ' <<< "$line" 2>/dev/null)
                [[ -n "$info" ]] && echo "$info"
            fi
            ;;
    esac
done
:
