#!/bin/bash
# setup-browser-access.sh - One-time setup to authorize browser password access
#
# This script triggers the macOS Keychain authorization dialog for browser passwords.
# When prompted, click "Always Allow" to enable automated access in the future.
#
# After setup, the credential-acquire.sh script will be able to retrieve passwords
# from your browser's password manager without prompting.

echo "=== Browser Password Access Setup ==="
echo ""
echo "This will trigger a macOS Keychain authorization dialog for each browser."
echo "Click 'Always Allow' to enable automated access."
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

declare -A BROWSERS=(
    ["Arc"]="Arc Safe Storage:Arc"
    ["Chrome"]="Chrome Safe Storage:Chrome"
    ["Edge"]="Microsoft Edge Safe Storage:Microsoft Edge"
    ["Brave"]="Brave Safe Storage:Brave"
)

for browser in "${!BROWSERS[@]}"; do
    IFS=':' read -r service account <<< "${BROWSERS[$browser]}"

    echo "Checking $browser..."

    if security find-generic-password -s "$service" -a "$account" &>/dev/null; then
        echo "  Found $browser keychain entry. Requesting access..."
        echo "  >>> Click 'Always Allow' in the dialog that appears <<<"

        result=$(security find-generic-password -s "$service" -a "$account" -w 2>&1)

        if [ $? -eq 0 ]; then
            echo "  ✓ $browser access authorized!"
        else
            echo "  ✗ $browser access denied or cancelled"
        fi
    else
        echo "  - $browser not installed or no passwords saved"
    fi

    echo ""
done

echo "=== Setup Complete ==="
echo ""
echo "Now you can use: source credential-acquire.sh <domain>"
echo "Browser passwords will be checked automatically."
