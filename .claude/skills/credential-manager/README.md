# Credential Manager Skill

Securely acquire, store, and retrieve credentials for browser automation on macOS.

## ⚠️ Security: Never Expose Passwords

**Default to `credential-fill.py`** - it handles credentials internally without exposing them in command output or conversation history.

```bash
# ✅ SAFE: Use credential-fill.py (passwords never appear in output)
python3 credential-fill.py example.com @e2 @e3 @e4

# ✅ SAFE: Verify credentials exist without seeing password
python3 browser-passwords.py example.com --verify

# ❌ UNSAFE: Don't run commands that output passwords
python3 browser-passwords.py example.com  # Exposes password!
```

## Supported Sources (Priority Order)

| Source | Best For | User Interaction |
|--------|----------|------------------|
| **macOS Keychain** | Persistent credentials | First access prompts (Touch ID/password) |
| **Saved Sessions** | Browser session reuse | None after initial login |
| **Browser Passwords** | Arc/Chrome saved passwords | Consent dialog per domain |
| **Environment Variables** | CI/CD, temporary creds | None |
| **Repo .env Files** | Dev/test environment creds | None (searches repo) |
| **Native Prompt** | One-time entry | Dialog with masked input |
| **Headed Browser** | SSO/2FA login flows | Manual login in browser |

## User Consent for Browser Passwords

When accessing credentials from browser password managers, you'll see a consent dialog:

| Button | Effect |
|--------|--------|
| **Allow Once** | Returns credentials for this request only |
| **Allow for Session** | Remembers approval until terminal closes |
| **Deny** | Blocks access and remembers denial for session |

To clear session approvals:
```bash
python3 browser-passwords.py --clear-session
```

To bypass consent (automation/testing):
```bash
python3 browser-passwords.py github.com --no-prompt
```

## One-Time Setup for Browser Passwords

To enable extraction from Arc/Chrome password managers:

```bash
./setup-browser-access.sh
```

This triggers a Keychain authorization dialog. **Click "Always Allow"** to enable automated access.

## Quick Start

### Store credentials for a domain
```bash
./credential-store.sh github.com --token
./credential-store.sh jira.example.com --username user@company.com
```

### Acquire credentials (auto-detection)
```bash
source credential-acquire.sh github.com

# Use credentials immediately; do NOT print credential variables
# (CRED_PASSWORD / CRED_HEADERS may contain secrets)
agent-browser open "https://api.example.com" --headers "$CRED_HEADERS"
```

### Use with agent-browser

### Method 1: credential-fill.py (Recommended - handles special characters)
```bash
# Navigate to login page first
agent-browser open "https://example.com/login"
agent-browser snapshot -i  # Find the refs for username, password, submit

# Fill credentials directly (avoids bash escaping issues)
python3 credential-fill.py example.com @e2 @e3 @e4
#                          domain    user pass submit
```

### Method 2: Headers (API/token auth)
```bash
source credential-acquire.sh api.example.com
agent-browser open "https://api.example.com" --headers "$CRED_HEADERS"
```

### Method 3: Manual form fill (fallback only when `credential-fill.py` cannot target the form)
```bash
source credential-acquire.sh example.com
agent-browser open "https://example.com/login"
agent-browser snapshot -i
agent-browser fill @username "$CRED_USERNAME"
agent-browser fill @password "$CRED_PASSWORD"
agent-browser click @submit
```

## Output Variables

After sourcing `credential-acquire.sh`:

| Variable | Description |
|----------|-------------|
| `CRED_USERNAME` | Username (if applicable) |
| `CRED_PASSWORD` | Password or token |
| `CRED_HEADERS` | JSON headers for Authorization |
| `CRED_METHOD` | Which acquisition method succeeded |

## Files

- `SKILL.md` - Full skill documentation for Claude
- `credential-acquire.sh` - Main acquisition script (source this)
- `credential-store.sh` - Store new credentials
- `~/.credential-manager/sessions/` - Saved browser sessions

## Security Notes

- Credentials stored in macOS Keychain (encrypted at rest)
- Session files stored with 700 permissions
- Environment variables cleared after use
- Never logs actual credential values
