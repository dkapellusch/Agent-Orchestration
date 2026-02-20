---
name: wt-pr
description: "Create a pull request for the current branch. Use when the user says 'create PR', 'open PR', 'wt-pr', or wants to open a pull request. Auto-detects Azure DevOps vs GitHub from git remote, links Jira tickets, and sets the PR title."
---

# /wt-pr — Create a Pull Request

**Announce at start:** "Creating a pull request."

**Shared conventions**: See [`wt-common.md`](../wt-common.md) for repo root resolution, branch naming, and remote type detection.

---

## Input

**`$ARGUMENTS`**: Optional Jira ticket key and/or flags.

```bash
/wt-pr                                  # Auto: detect everything
/wt-pr FULFAI-123                       # Explicit Jira ticket
/wt-pr --title "Add worktree skills"    # Custom title
/wt-pr --target staging                 # Target branch override
/wt-pr --draft                          # Create as draft PR
/wt-pr FULFAI-123 --title "Fix auth"    # Both explicit
```

### Flags

| Flag | Effect | Default |
|------|--------|---------|
| `--title <text>` | Custom PR title | Auto-generated from branch + commits |
| `--target <branch>` | Target/base branch | Origin's default branch |
| `--draft` | Create as draft/WIP | Not draft |
| First positional arg matching `[A-Z]+-\d+` | Jira ticket key | Inferred from branch name |

---

## Execution

### Phase 1: Gather Context

```bash
REPO_ROOT="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"
CURRENT_BRANCH="$(git branch --show-current)"
```

Detect remote type (see `wt-common.md` — Remote Type Detection):
```bash
REMOTE_URL="$(git config --get remote.origin.url)"
```
- Contains `visualstudio.com` or `dev.azure.com` → **Azure DevOps**
- Contains `github.com` → **GitHub**
- Otherwise → ask user: "Azure DevOps or GitHub?"

Detect default target branch (if `--target` not provided):
```bash
git remote show origin | grep 'HEAD branch' | cut -d' ' -f5
```

Get commit log and diff stat for PR description:
```bash
git log origin/{target}..HEAD --oneline
git diff origin/{target}...HEAD --stat
```

### Phase 2: Ensure Branch is Pushed

Check if remote tracking branch exists:
```bash
git ls-remote --heads origin {branch}
```

- If not pushed or behind: `git push -u origin {branch}`
- If already up-to-date: skip

### Phase 3: Detect Jira Ticket

1. If `$ARGUMENTS` contains a token matching `[A-Z]+-\d+` (e.g., `FULFAI-123`), use that as the Jira key.
2. Otherwise, parse `{CURRENT_BRANCH}` for the same pattern (e.g., `feature/FULFAI-123-slug` → `FULFAI-123`).
3. If no key found → `AskUserQuestion`: "No Jira ticket detected in the branch name. Provide a ticket key, or select 'No ticket'."
   - Options: "No ticket" / Other (free text input)

If a Jira key is found, attempt to fetch the issue title:
- Use `ToolSearch` to search for Jira MCP tools (search for "jira")
- If a get-by-key tool is available, call it with the ticket key and extract the issue title for the PR description
- If no Jira MCP tools are available, use just the ticket key without a title

### Phase 4: Generate PR Title & Description

**Title** (if `--title` not provided):
1. Start with the branch name
2. Remove prefixes: `feature/`, `hotfix/`, `bugfix/`, and the Jira key + separator (e.g., `FULFAI-123-`)
3. Convert kebab-case to sentence case (e.g., `add-worktree-skills` → `Add worktree skills`)
4. Present to user via `AskUserQuestion` for confirmation/edit:
   > "Proposed PR title: `{generated_title}`. Use this, or provide a custom title?"
   - Options: "Use this title" / Other (free text input)

**Description** template:

If Jira ticket exists:
```markdown
## Jira

[{TICKET_KEY}] {Jira issue title}

## Summary

{One-line summary from commit log or branch purpose}

## Changes

{diff --stat output, formatted}
```

If no Jira ticket:
```markdown
## Summary

{One-line summary from commit log or branch purpose}

## Changes

{diff --stat output, formatted}
```

### Phase 5: Create PR

**Azure DevOps**:
```bash
az repos pr create \
  --title "{title}" \
  --description "$(cat <<'EOF'
{description}
EOF
)" \
  --source-branch "{branch}" \
  --target-branch "{target}" \
  --detect \
  --open \
  {--draft if flag set}
```

**GitHub**:
```bash
gh pr create \
  --title "{title}" \
  --body "$(cat <<'EOF'
{description}
EOF
)" \
  --base "{target}" \
  --head "{branch}" \
  {--draft if flag set}
```

Capture the PR URL from the command output.

### Phase 6: Report

```
PR created:
  URL:    {pr_url}
  Title:  {title}
  Target: {target}
  Jira:   {ticket_key} — {jira_title}    (omit line if no ticket)
  Draft:  {yes/no}
```

---

## Error Handling

| Error | Action |
|-------|--------|
| Remote type undetectable | Ask user: "Azure DevOps or GitHub?" |
| Branch not pushed + push fails | Report error, stop |
| No Jira ticket found | Ask user, allow "No ticket" |
| PR creation fails | Report full error output |
| `az` / `gh` CLI not installed | Report which CLI is needed and how to install it |
| PR already exists for branch | Report existing PR URL |