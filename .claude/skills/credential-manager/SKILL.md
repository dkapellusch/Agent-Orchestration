---
name: credential-manager
description: Securely acquire, store, and retrieve credentials for browser automation. Use when authentication is needed for web tasks - supports Keychain, browser password managers, user prompts, and interactive headed browser login. Triggers on "get credentials", "login to", "authenticate", "need password for", "store credentials".
allowed-tools: Bash, Read, Write, TodoWrite
---

# Credential Manager for Browser Automation

**You are managing credentials for authenticated browser sessions.** This skill provides secure methods to acquire, store, and retrieve credentials from multiple sources.

---

## ⚠️ CRITICAL: Use the Skill Base Directory

**All scripts in this skill MUST be run using the base directory path shown above the skill prompt.**

When invoking this skill, you'll see:
```
Base directory for this skill: /path/to/skill/credential-manager
```

**ALWAYS use that full path for scripts:**
```bash
# ✅ CORRECT - Use the base directory from the skill prompt
python3 /path/to/skill/credential-manager/browser-passwords.py domain.com --verify
python3 /path/to/skill/credential-manager/credential-fill.py domain.com @e2 @e3 @e4

# ❌ WRONG - Don't assume a global path
python3 ~/.claude/skills/credential-manager/browser-passwords.py  # WRONG!
python3 browser-passwords.py  # WRONG - not in PATH!
```

**Tip:** Use full paths inline (shell variables don't persist between Bash calls):
```bash
# ✅ CORRECT - Full path in each command
python3 "/path/to/skill/credential-manager/browser-passwords.py" domain.com --verify

# ❌ WRONG - Variable set in previous Bash call is lost
SKILL_DIR="..."  # This won't exist in the next Bash invocation
python3 "$SKILL_DIR/browser-passwords.py"  # Fails - empty variable
```

---

## ⚠️ CRITICAL SECURITY RULES

**NEVER expose plaintext passwords in the conversation.** Follow these rules:

1. **NEVER run commands that output passwords** - Don't run `browser-passwords.py <domain>` without `--verify`
2. **Default to credential-fill.py** - This handles credentials internally without exposing them
3. **NEVER echo, print, or log passwords** - Even partially masked passwords are a risk
4. **NEVER store passwords in shell variables in your commands** - Use the helper scripts instead

### ✅ SAFE Pattern (Use This)
```bash
# Navigate to login page
agent-browser open "https://example.com/login"
agent-browser snapshot -i

# Fill credentials WITHOUT exposing them (credential-fill.py handles it internally)
python3 credential-fill.py example.com @e2 @e3 @e4
```

### ❌ UNSAFE Patterns (Never Do This)
```bash
# DON'T: Run commands that output passwords
python3 browser-passwords.py example.com  # Outputs password in JSON!

# DON'T: Store passwords in variables
PASSWORD=$(some-command)
agent-browser fill @e3 "$PASSWORD"

# DON'T: Echo or log credentials
echo "$CRED_PASSWORD"
```

### Verifying Credentials Exist (Safe)
```bash
# Use --verify flag to check without exposing password
python3 browser-passwords.py example.com --verify
# Output: {"url": "...", "username": "user@example.com", "password": "********", "browser": "arc"}
```

---

## Available Methods (Brief Reference)

Each method below is used by the workflow. The helper scripts handle most complexity.

### Keychain
```bash
# Check for stored credentials (safe existence check)
security find-generic-password -s "credential-manager-<domain>" >/dev/null 2>&1

# Store credentials (interactive, no plaintext in shell history)
"$SKILL_DIR/credential-store.sh" <domain> --username <username>
```

### Saved Sessions
```bash
# Load existing session
agent-browser session load ~/.credential-manager/sessions/<domain>.json

# Save session after login
agent-browser session save ~/.credential-manager/sessions/<domain>.json
```

### Browser Password Managers (Arc/Chrome/Firefox)
```bash
# Check if credentials exist (use --verify to mask password)
python3 "$SKILL_DIR/browser-passwords.py" <domain> --verify

# Fill login form automatically
python3 "$SKILL_DIR/credential-fill.py" <domain> @username-ref @password-ref @submit-ref
```

### Environment Variables
```bash
# Check for credentials in environment
$AUTH_TOKEN, $CRED_USERNAME, $CRED_PASSWORD
```

### User Prompt (macOS dialog)
```bash
# Prompt with masked password input
osascript -e 'text returned of (display dialog "Enter password:" default answer "" with hidden answer)'
```

### .env File Search
```bash
# Find .env files (don't output contents!)
find . -name ".env*" -type f ! -path "*/node_modules/*" 2>/dev/null
```

### Headed Browser Login (Manual)
```bash
agent-browser open "https://example.com/login" --headed
# User logs in manually, then save session
agent-browser session save ~/.credential-manager/sessions/<domain>.json
```

---

## Credential Acquisition Workflow

Follow this decision tree to acquire credentials:

```
Need credentials for <domain>?
│
├─► 1. Check Keychain first (most secure)
│   security find-generic-password -s "credential-manager-<domain>" >/dev/null 2>&1
│   └─► Found? Use them
│
├─► 2. Check for saved session (already authenticated)
│   ~/.credential-manager/sessions/<domain>.json
│   └─► Found and not expired? Load session - no login needed
│
├─► 3. Check browser password managers (Arc/Chrome/Firefox)
│   python3 browser-passwords.py <domain> --verify
│   └─► Found? Use credential-fill.py
│
├─► 4. Check environment variables
│   $AUTH_TOKEN, $APP_USERNAME, $APP_PASSWORD
│   └─► Set? Use them
│
├─► 5. Prompt user (interactive)
│   └─► osascript dialog
│       └─► Store in Keychain for next time
│
├─► 6. Search repo .env files (last resort for stored creds)
│   find . -name ".env*" and grep for domain patterns
│   └─► Found? Load and use them
│
└─► 7. Headed browser login (final fallback)
    └─► User logs in manually
        └─► Save session for next time
```

**Priority rationale:**
- **Keychain first** - Explicitly stored for this purpose
- **Saved session second** - Already authenticated, fastest path
- **Browser passwords third** - User's real credentials from Arc/Chrome/Firefox
- **.env files last** - Often contain stale dev/test credentials, less secure

---

## Security Best Practices

1. **Keychain is preferred** - Encrypted at rest, OS-managed security
2. **Never log credentials** - Use `set +x` before handling secrets
3. **Clear environment after use** - `unset CRED_PASSWORD`
4. **Session files are sensitive** - Store in `~/.credential-manager/` with 600 permissions
5. **Temporary files** - Use `/tmp` and delete immediately after use
6. **Touch ID when available** - Keychain prompts use biometric authentication

### Secure Cleanup
```bash
# After using credentials
unset CRED_USERNAME
unset CRED_PASSWORD
unset TOKEN
unset HEADERS

# Clear command history of sensitive commands
history -d $(history 1 | awk '{print $1}')
```

---

## Directory Structure

```
~/.credential-manager/
├── sessions/                    # Saved browser sessions
│   ├── github-com.json
│   ├── jira-atlassian-net.json
│   └── example-com-cookies.json
└── config.json                  # Optional: default settings
```

### Initialize Structure
```bash
mkdir -p ~/.credential-manager/sessions
chmod 700 ~/.credential-manager
chmod 700 ~/.credential-manager/sessions
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Keychain access denied | First access prompts - click "Always Allow" for `security` |
| Browser DB locked | Close Chrome/Arc/Firefox before extraction |
| Session expired | Delete session file, re-authenticate with headed browser |
| osascript cancelled | User clicked Cancel - handle gracefully |
| Touch ID not available | Falls back to password prompt |
| credential-fill.py fails | Uses **positional args only**: `<domain> <user_ref> <pass_ref> [submit_ref]` - no `--flags` |
| Two-step login (email then password) | Fill email manually, click Next, resnapshot, then run `credential-fill.py` with refs from the new form. Never pipe plaintext password output from `browser-passwords.py`. |

---

## Quick Start Example

```bash
# 1. Set skill directory (copy from skill prompt header)
SKILL_DIR="/path/to/skill/credential-manager"

# 2. Check for credentials
python3 "$SKILL_DIR/browser-passwords.py" github.com --verify

# 3. Navigate and get form refs
agent-browser open "https://github.com/login"
agent-browser snapshot -i

# 4. Fill and submit (credential-fill.py handles password securely)
python3 "$SKILL_DIR/credential-fill.py" github.com @e2 @e3 @e4

# 5. Save session for next time
agent-browser session save ~/.credential-manager/sessions/github-com.json
```
