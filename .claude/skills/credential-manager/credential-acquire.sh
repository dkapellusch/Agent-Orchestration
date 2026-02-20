#!/bin/bash
# credential-acquire.sh - Acquire credentials for a domain using multiple fallback methods
#
# Usage: source credential-acquire.sh <domain> [--method <method>]
#
# Methods (in priority order if not specified):
#   keychain    - Retrieve from macOS Keychain
#   session     - Load saved browser session
#   env         - Use environment variables
#   prompt      - Show native macOS dialog
#   browser     - Open headed browser for manual login
#
# Outputs:
#   CRED_USERNAME - Username (if applicable)
#   CRED_PASSWORD - Password or token
#   CRED_HEADERS  - JSON headers for Authorization
#   CRED_METHOD   - Which method succeeded

DOMAIN=""
METHOD="auto"
CREDENTIAL_MANAGER_DIR="${HOME}/.credential-manager"
SESSIONS_DIR="${CREDENTIAL_MANAGER_DIR}/sessions"

while [[ $# -gt 0 ]]; do
    case $1 in
        --method)
            METHOD="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            return 1 2>/dev/null || exit 1
            ;;
        *)
            DOMAIN="$1"
            shift
            ;;
    esac
done

if [ -z "$DOMAIN" ]; then
    echo "Usage: source credential-acquire.sh <domain> [--method <method>]"
    echo "Example: source credential-acquire.sh github.com"
    echo "Example: source credential-acquire.sh github.com --method keychain"
    return 1 2>/dev/null || exit 1
fi

SERVICE_NAME="credential-manager-$(echo "$DOMAIN" | tr '.' '-' | tr '/' '-')"
SESSION_FILE="${SESSIONS_DIR}/${DOMAIN//[\/:]/-}.json"

mkdir -p "$SESSIONS_DIR"
chmod 700 "$CREDENTIAL_MANAGER_DIR" 2>/dev/null || true
chmod 700 "$SESSIONS_DIR" 2>/dev/null || true

unset CRED_USERNAME CRED_PASSWORD CRED_HEADERS CRED_METHOD

log() {
    echo "[credential-manager] $1" >&2
}

try_keychain() {
    log "Trying Keychain..."

    local password
    password=$(security find-generic-password -s "$SERVICE_NAME" -w 2>/dev/null) || return 1

    if [ -n "$password" ]; then
        CRED_PASSWORD="$password"

        local account
        account=$(security find-generic-password -s "$SERVICE_NAME" 2>/dev/null | grep '"acct"' | head -1 | sed 's/.*<blob>="\([^"]*\)".*/\1/' 2>/dev/null) || true

        if [ -n "$account" ]; then
            CRED_USERNAME="$account"
        fi

        CRED_METHOD="keychain"
        log "Found credentials in Keychain"
        return 0
    fi

    return 1
}

try_session() {
    log "Trying saved session..."

    if [ -f "$SESSION_FILE" ]; then
        local age_seconds
        if [[ "$OSTYPE" == "darwin"* ]]; then
            age_seconds=$(( $(date +%s) - $(stat -f %m "$SESSION_FILE") ))
        else
            age_seconds=$(( $(date +%s) - $(stat -c %Y "$SESSION_FILE") ))
        fi

        local max_age=$((24 * 60 * 60))

        if [ "$age_seconds" -lt "$max_age" ]; then
            CRED_METHOD="session"
            log "Found valid session file (age: ${age_seconds}s)"
            echo "SESSION_FILE=$SESSION_FILE"
            return 0
        else
            log "Session file expired (age: ${age_seconds}s)"
            rm -f "$SESSION_FILE"
        fi
    fi

    return 1
}

try_browser_passwords() {
    log "Trying browser password managers (Arc/Chrome)..."

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    local py_script="${script_dir}/browser-passwords.py"

    if [ ! -f "$py_script" ]; then
        log "browser-passwords.py not found"
        return 1
    fi

    if ! command -v python3 &>/dev/null; then
        log "python3 not available"
        return 1
    fi

    if ! python3 -c "import Crypto" 2>/dev/null; then
        log "pycryptodome not installed (pip install pycryptodome)"
        return 1
    fi

    local result
    result=$(python3 "$py_script" "$DOMAIN" 2>/dev/null) || return 1

    local error
    error=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',''))" 2>/dev/null)
    if [ -n "$error" ]; then
        log "$error"
        return 1
    fi

    CRED_USERNAME=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('username',''))" 2>/dev/null)
    CRED_PASSWORD=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('password',''))" 2>/dev/null)

    if [ -n "$CRED_PASSWORD" ]; then
        CRED_METHOD="browser_passwords"
        local browser
        browser=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('browser',''))" 2>/dev/null)
        log "Found credentials in $browser password manager"
        return 0
    fi

    return 1
}

try_env() {
    log "Trying environment variables..."

    if [ -n "$AUTH_TOKEN" ]; then
        CRED_PASSWORD="$AUTH_TOKEN"
        CRED_HEADERS="{\"Authorization\": \"Bearer $AUTH_TOKEN\"}"
        CRED_METHOD="env"
        log "Found AUTH_TOKEN in environment"
        return 0
    fi

    local domain_upper
    domain_upper=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]' | tr '.' '_' | tr '-' '_')

    local user_var="${domain_upper}_USERNAME"
    local pass_var="${domain_upper}_PASSWORD"
    local token_var="${domain_upper}_TOKEN"

    local token_val user_val pass_val
    eval "token_val=\"\${$token_var:-}\""
    eval "user_val=\"\${$user_var:-}\""
    eval "pass_val=\"\${$pass_var:-}\""

    if [ -n "$token_val" ]; then
        CRED_PASSWORD="$token_val"
        CRED_HEADERS="{\"Authorization\": \"Bearer $token_val\"}"
        CRED_METHOD="env"
        log "Found $token_var in environment"
        return 0
    fi

    if [ -n "$user_val" ] && [ -n "$pass_val" ]; then
        CRED_USERNAME="$user_val"
        CRED_PASSWORD="$pass_val"
        CRED_METHOD="env"
        log "Found $user_var and $pass_var in environment"
        return 0
    fi

    if [ -n "$CRED_USERNAME" ] && [ -n "$CRED_PASSWORD" ]; then
        CRED_METHOD="env"
        log "Found CRED_USERNAME and CRED_PASSWORD in environment"
        return 0
    fi

    return 1
}

try_prompt() {
    log "Prompting user for credentials..."

    if ! command -v osascript &>/dev/null; then
        log "osascript not available (not macOS)"
        return 1
    fi

    local username
    username=$(osascript <<EOF 2>/dev/null
activate application "System Events"
set answer to text returned of (display dialog "Enter username for $DOMAIN:" default answer "" buttons {"OK", "Cancel"} default button 1 cancel button 2)
return answer
EOF
) || {
        log "User cancelled username prompt"
        return 1
    }

    local password
    password=$(osascript <<EOF 2>/dev/null
activate application "System Events"
set answer to text returned of (display dialog "Enter password for $DOMAIN:" default answer "" with hidden answer buttons {"OK", "Cancel"} default button 1 cancel button 2)
return answer
EOF
) || {
        log "User cancelled password prompt"
        return 1
    }

    if [ -z "$password" ]; then
        log "Empty password provided"
        return 1
    fi

    CRED_USERNAME="$username"
    CRED_PASSWORD="$password"
    CRED_METHOD="prompt"

    local save_response
    save_response=$(osascript <<EOF 2>/dev/null
activate application "System Events"
set answer to button returned of (display dialog "Save credentials to Keychain for future use?" buttons {"Save", "Don't Save"} default button 1)
return answer
EOF
) || save_response="Don't Save"

    if [ "$save_response" = "Save" ]; then
        security add-generic-password \
            -a "$CRED_USERNAME" \
            -s "$SERVICE_NAME" \
            -w "$CRED_PASSWORD" \
            -T /usr/bin/security \
            -U 2>/dev/null || log "Failed to save to Keychain"
        log "Credentials saved to Keychain"
    fi

    return 0
}

try_browser() {
    log "Opening headed browser for manual login..."

    if ! command -v agent-browser &>/dev/null; then
        log "agent-browser not available"
        return 1
    fi

    local url="https://$DOMAIN"
    if [[ "$DOMAIN" != http* ]] && [[ "$DOMAIN" != */* ]]; then
        url="https://$DOMAIN/login"
    fi

    agent-browser open "$url" --headed

    echo ""
    echo "=========================================="
    echo "Please log in to $DOMAIN in the browser window"
    echo "Press Enter when login is complete..."
    echo "=========================================="
    read -r

    agent-browser session save "$SESSION_FILE" 2>/dev/null || {
        log "Could not save session - trying cookies"
        agent-browser cookies --json > "${SESSION_FILE}.cookies" 2>/dev/null || true
    }

    agent-browser close 2>/dev/null || true

    if [ -f "$SESSION_FILE" ] || [ -f "${SESSION_FILE}.cookies" ]; then
        CRED_METHOD="browser"
        log "Session captured successfully"
        return 0
    fi

    return 1
}

acquire_credentials() {
    local -a methods_array

    if [ "$METHOD" = "auto" ]; then
        methods_array=(keychain session browser_passwords env prompt browser)
    else
        methods_array=("$METHOD")
    fi

    for method in "${methods_array[@]}"; do
        case "$method" in
            keychain)
                try_keychain && return 0
                ;;
            session)
                try_session && return 0
                ;;
            browser_passwords)
                try_browser_passwords && return 0
                ;;
            env)
                try_env && return 0
                ;;
            prompt)
                try_prompt && return 0
                ;;
            browser)
                try_browser && return 0
                ;;
            *)
                log "Unknown method: $method"
                ;;
        esac
    done

    log "All credential acquisition methods failed"
    return 1
}

build_headers() {
    if [ -n "$CRED_HEADERS" ]; then
        return
    fi

    if [ -n "$CRED_PASSWORD" ]; then
        if [[ "$CRED_PASSWORD" == ghp_* ]] || [[ "$CRED_PASSWORD" == sk-* ]] || [[ "$CRED_PASSWORD" == Bearer* ]]; then
            local token="$CRED_PASSWORD"
            token="${token#Bearer }"
            CRED_HEADERS="{\"Authorization\": \"Bearer $token\"}"
        elif [ -n "$CRED_USERNAME" ]; then
            local basic_auth
            basic_auth=$(echo -n "$CRED_USERNAME:$CRED_PASSWORD" | base64)
            CRED_HEADERS="{\"Authorization\": \"Basic $basic_auth\"}"
        fi
    fi
}

if acquire_credentials; then
    build_headers

    echo ""
    log "=== Credentials Acquired ==="
    log "Method: $CRED_METHOD"
    [ -n "$CRED_USERNAME" ] && log "Username: $CRED_USERNAME"
    [ -n "$CRED_PASSWORD" ] && log "Password: ****${CRED_PASSWORD: -4}"
    [ -n "$CRED_HEADERS" ] && log "Headers available: CRED_HEADERS"
    [ -n "$SESSION_FILE" ] && [ -f "$SESSION_FILE" ] && log "Session: $SESSION_FILE"
    echo ""

    export CRED_USERNAME CRED_PASSWORD CRED_HEADERS CRED_METHOD
else
    log "Failed to acquire credentials for $DOMAIN"
    return 1 2>/dev/null || exit 1
fi
