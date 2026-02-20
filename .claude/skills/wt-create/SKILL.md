---
name: wt-create
description: "Create a new git worktree with proper conventions, config files, and remote setup. Use when the user says 'create worktree', 'new worktree', 'wt-create', or wants to start work on a new feature branch in an isolated worktree."
---

# /wt-create — Create a New Worktree

**Announce at start:** "Creating a new worktree."

**Shared conventions**: See [`wt-common.md`](../wt-common.md) for repo root resolution, branch naming, and config file conventions.

---

## Input

**`$ARGUMENTS`**: A slug (worktree folder name) with optional flags.

```bash
/wt-create my-feature
/wt-create my-feature --from staging
/wt-create urgent-fix --branch hotfix/urgent-fix
/wt-create urgent-fix --branch hotfix/urgent-fix --from main
```

If `$ARGUMENTS` is empty → **STOP** with usage examples.

### Flags

| Flag | Effect | Default |
|------|--------|---------|
| `--branch <name>` | Custom branch name | `feature/{slug}` |
| `--from <source>` | Source branch to create from | Origin's default branch |

---

## Execution

### Step 1: Parse Arguments

Extract from `$ARGUMENTS`:
- `{slug}` — the worktree folder name (required, first positional arg)
- `{branch}` — custom branch name (optional, from `--branch`)
- `{source}` — source branch (optional, from `--from`)

If no slug provided, check if user gave a branch name that can derive a slug:
- `feature/my-thing` → slug: `feature-my-thing`
- `hotfix/urgent` → slug: `hotfix-urgent`

### Step 2: Run Setup Script

```bash
bash .claude/skills/wt-create/setup-worktree.sh {slug} [--branch {branch}] [--from {source}]
```

The script handles:
- Resolving the **main repo root** (never nests inside existing worktrees)
- Creating the branch from the source branch
- Creating the worktree at `{repo-root}/worktrees/{slug}`
- Copying all `.env*` and `.mcp.json` files
- Copying matching ai-docs

### Step 3: Report

After the script completes, report:

```
Worktree created:
  Path:   {repo-root}/worktrees/{slug}
  Branch: {branch}
  From:   {source}

Config files copied. Ready for development.
```

---

## Error Handling

| Error | Action |
|-------|--------|
| Worktree already exists | Report the error, suggest `git worktree remove worktrees/{slug}` |
| Branch already exists | Script will use the existing branch (not an error) |
| Source branch not found | Report the error, suggest checking branch name |
| No arguments | Show usage examples |