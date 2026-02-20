---
name: browser-use
description: Headless browser automation for web tasks. Use for viewing web pages (especially internal/authenticated pages that require login), filling forms, clicking buttons, taking screenshots, or interacting with web pages programmatically. Prefer this over WebFetch for authenticated pages or when WebFetch returns errors (401, 403, 404). Triggers on phrases like "open website", "click button", "fill form", "take screenshot", "browse to", "navigate to", "scrape page", "view page", "access site".
allowed-tools: Bash, Read, Write, TodoWrite
---

# Browser Automation with agent-browser

**You are automating a web browser using the `agent-browser` CLI.** This tool provides headless Chromium automation optimized for AI agents.

## Core Workflow (Ref-Based - Optimal for AI)

The recommended workflow uses accessibility snapshots with refs for deterministic element selection:

```bash
# 1. Navigate to page
agent-browser open <url>

# 2. Get snapshot with refs (shows interactive elements)
agent-browser snapshot -i

# 3. Interact using refs from snapshot
agent-browser click @e2
agent-browser fill @e3 "text"
agent-browser get text @e1

# 4. Re-snapshot after page changes
agent-browser snapshot -i
```

**Why refs?**
- **Deterministic**: Ref points to exact element from snapshot
- **Fast**: No DOM re-query needed
- **AI-friendly**: Snapshot + ref workflow is optimal for LLMs

---

## Quick Reference

### Navigation
```bash
agent-browser open <url>              # Navigate to URL
agent-browser back                    # Go back
agent-browser forward                 # Go forward
agent-browser reload                  # Reload page
```

### Snapshots (Your Primary Tool)
```bash
agent-browser snapshot                # Full accessibility tree
agent-browser snapshot -i             # Interactive elements only (buttons, inputs, links)
agent-browser snapshot -c             # Compact (remove empty structural elements)
agent-browser snapshot -d 3           # Limit depth to 3 levels
agent-browser snapshot -i -c          # Combine: interactive + compact
agent-browser snapshot --json         # JSON output for parsing
```

### Interaction (Use @refs from snapshot)
```bash
agent-browser click @e2               # Click element
agent-browser fill @e3 "text"         # Clear and fill input
agent-browser type @e3 "text"         # Type into element (appends)
agent-browser hover @e4               # Hover element
agent-browser check @e5               # Check checkbox
agent-browser uncheck @e5             # Uncheck checkbox
agent-browser select @e6 "option"     # Select dropdown option
agent-browser press Enter             # Press key (Enter, Tab, Escape, etc.)
agent-browser scroll down 300         # Scroll (up/down/left/right)
```

### Get Information
```bash
agent-browser get text @e1            # Get text content
agent-browser get value @e3           # Get input value
agent-browser get title               # Get page title
agent-browser get url                 # Get current URL
agent-browser is visible @e2          # Check if visible
agent-browser is enabled @e3          # Check if enabled
```

### Screenshots
```bash
agent-browser screenshot              # Screenshot viewport
agent-browser screenshot page.png     # Save to file
agent-browser screenshot --full       # Full page screenshot
```

### Wait
```bash
agent-browser wait @e1                # Wait for element visible
agent-browser wait 2000               # Wait milliseconds
agent-browser wait --text "Welcome"   # Wait for text to appear
agent-browser wait --load networkidle # Wait for network idle
```

### Browser Control
```bash
agent-browser close                   # Close browser
agent-browser set viewport 1280 720   # Set viewport size
agent-browser tab                     # List tabs
agent-browser tab new [url]           # New tab
agent-browser tab 1                   # Switch to tab
```

---

## Standard Task Pattern

For any web automation task, follow this pattern:

### Step 1: Navigate and Assess
```bash
agent-browser open <url>
agent-browser snapshot -i
```

### Step 2: Identify Target Elements
Read the snapshot output to find refs for elements you need:
```
- heading "Login" [ref=e1] [level=1]
- textbox "Email" [ref=e2]
- textbox "Password" [ref=e3]
- button "Sign In" [ref=e4]
- link "Forgot password?" [ref=e5]
```

### Step 3: Execute Actions
```bash
agent-browser fill @e2 "user@example.com"
agent-browser fill @e3 "password123"
agent-browser click @e4
```

### Step 4: Verify and Continue
```bash
agent-browser wait --load networkidle
agent-browser snapshot -i  # Re-snapshot to see new page state
```

---

## Complex Scenarios

### Form Filling
```bash
agent-browser open https://example.com/form
agent-browser snapshot -i

# Fill multiple fields
agent-browser fill @e2 "John Doe"
agent-browser fill @e3 "john@example.com"
agent-browser fill @e4 "555-1234"
agent-browser select @e5 "California"
agent-browser check @e6  # Agree to terms
agent-browser click @e7  # Submit button
```

### Authentication with Headers
```bash
# Skip login flow with auth headers
agent-browser open https://api.example.com --headers '{"Authorization": "Bearer <token>"}'
agent-browser snapshot -i
```

### Multi-Tab Operations
```bash
agent-browser open site1.com
agent-browser tab new site2.com
agent-browser tab 0  # Switch back to first tab
agent-browser tab    # List all tabs
```

### Sessions (Isolated Browser Instances)
```bash
# Different sessions for parallel work
agent-browser --session agent1 open site-a.com
agent-browser --session agent2 open site-b.com

# Or via environment
AGENT_BROWSER_SESSION=agent1 agent-browser click @e2
```

### Debugging
```bash
agent-browser open example.com --headed  # Show browser window
agent-browser console                     # View console messages
agent-browser errors                      # View page errors
agent-browser screenshot debug.png        # Capture current state
```

---

## CSS Selectors (Fallback)

When refs aren't suitable, CSS selectors also work:

```bash
agent-browser click "#submit-btn"
agent-browser fill ".email-input" "test@example.com"
agent-browser click "button[type=submit]"
```

### Semantic Locators
```bash
agent-browser find role button click --name "Submit"
agent-browser find text "Sign In" click
agent-browser find label "Email" fill "test@test.com"
```

---

## Common Workflows

### Login Flow
```bash
agent-browser open https://example.com/login
agent-browser snapshot -i
agent-browser fill @e2 "$USERNAME"
agent-browser fill @e3 "$PASSWORD"
agent-browser click @e4
agent-browser wait --load networkidle
agent-browser snapshot -i  # Verify logged in
```

### Form Submission
```bash
agent-browser open https://example.com/contact
agent-browser snapshot -i
agent-browser fill @e2 "Name"
agent-browser fill @e3 "email@example.com"
agent-browser fill @e4 "Message content here"
agent-browser click @e5
agent-browser wait --text "Thank you"
```

### Data Extraction
```bash
agent-browser open https://example.com/data
agent-browser snapshot -i
agent-browser get text @e1  # Get specific text
agent-browser get text @e2
# Or screenshot for visual capture
agent-browser screenshot data.png
```

### Navigate and Screenshot
```bash
agent-browser open https://example.com
agent-browser wait --load networkidle
agent-browser screenshot --full page.png
agent-browser close
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Element not found | Re-run `snapshot -i` to get fresh refs |
| Page not loaded | Use `wait --load networkidle` before snapshot |
| Can't click element | Check `is visible @ref` first |
| Stale refs | Refs are tied to specific snapshot - re-snapshot after page changes |
| Browser not starting | Run `agent-browser install` to download Chromium |

---

## Output for Machine Parsing

Use `--json` for structured output:
```bash
agent-browser snapshot --json
agent-browser get text @e1 --json
agent-browser is visible @e2 --json
```

---

## Remember

1. **Always snapshot first** - Get refs before interacting
2. **Re-snapshot after changes** - Refs become stale when page updates
3. **Use `-i` flag** - Interactive-only snapshots are cleaner
4. **Wait for stability** - Use `wait --load networkidle` for dynamic pages
5. **Close when done** - `agent-browser close` to clean up
