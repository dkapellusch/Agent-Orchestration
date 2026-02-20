#!/bin/bash
# credential-store.sh - Store credentials securely in macOS Keychain
#
# Usage: ./credential-store.sh <domain> [--username <user>] [--token]
#
# Options:
#   --username <user>  Specify username (otherwise prompts)
#   --token           Store as token (no username, just password/token)
#   --update          Update existing credential
#
# Examples:
#   ./credential-store.sh github.com --token
#   ./credential-store.sh jira.atlassian.net --username user@company.com

set -e

DOMAIN=""
USERNAME=""
TOKEN_MODE=false
UPDATE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --username)
            USERNAME="$2"
            shift 2
            ;;
        --token)
            TOKEN_MODE=true
            shift
            ;;
        --update)
            UPDATE_MODE=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            DOMAIN="$1"
            shift
            ;;
    esac
done

if [ -z "$DOMAIN" ]; then
    echo "Usage: ./credential-store.sh <domain> [--username <user>] [--token]"
    echo ""
    echo "Examples:"
    echo "  ./credential-store.sh github.com --token"
    echo "  ./credential-store.sh jira.atlassian.net --username user@company.com"
    exit 1
fi

SERVICE_NAME="credential-manager-$(echo "$DOMAIN" | tr '.' '-' | tr '/' '-')"

log() {
    echo "[credential-store] $1"
}

if ! command -v osascript &>/dev/null; then
    echo "Error: This script requires macOS (osascript)"
    exit 1
fi

if [ "$TOKEN_MODE" = true ]; then
    USERNAME="api-token"
    log "Token mode: storing as '$USERNAME'"
elif [ -z "$USERNAME" ]; then
    USERNAME=$(osascript <<EOF
activate application "System Events"
set answer to text returned of (display dialog "Enter username for $DOMAIN:" default answer "" buttons {"OK", "Cancel"} default button 1 cancel button 2)
return answer
EOF
) || {
        log "User cancelled"
        exit 1
    }
fi

PASSWORD=$(osascript <<EOF
activate application "System Events"
set answer to text returned of (display dialog "Enter password/token for $DOMAIN:" default answer "" with hidden answer buttons {"OK", "Cancel"} default button 1 cancel button 2)
return answer
EOF
) || {
    log "User cancelled"
    exit 1
}

if [ -z "$PASSWORD" ]; then
    log "Error: Empty password not allowed"
    exit 1
fi

if security find-generic-password -s "$SERVICE_NAME" -a "$USERNAME" &>/dev/null; then
    if [ "$UPDATE_MODE" = true ]; then
        security delete-generic-password -s "$SERVICE_NAME" -a "$USERNAME" &>/dev/null || true
    else
        log "Credential already exists. Use --update to replace."
        exit 1
    fi
fi

security add-generic-password \
    -a "$USERNAME" \
    -s "$SERVICE_NAME" \
    -w "$PASSWORD" \
    -T /usr/bin/security \
    -U

log "Credential stored successfully"
log "  Domain:  $DOMAIN"
log "  Service: $SERVICE_NAME"
log "  Account: $USERNAME"
log ""
log "Retrieve with:"
log "  security find-generic-password -s \"$SERVICE_NAME\" -w"
