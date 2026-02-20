# Worktree Skills — Shared Conventions

Shared patterns used across all `wt-*` skills. These skills are **standalone** — no dependency on RPI or other skill systems.

---

## Repo Root Resolution

Worktrees are ALWAYS created at the **main repository root**, never nested inside existing worktrees.

```bash
# Always resolves to the main repo root, even when running inside a worktree
REPO_ROOT="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"
WORKTREES_DIR="$REPO_ROOT/worktrees"
```

**Why**: `git rev-parse --show-toplevel` returns the current worktree's root, which would create `worktrees/feature-x/worktrees/` nesting. The `git worktree list` approach always returns the main working tree.

---

## Branch & Slug Conventions

- **Slug**: The worktree folder name under `worktrees/`. Always kebab-case.
- **Branch**: Defaults to `feature/{slug}` but accepts any name.
- **Slug from branch**: When a custom branch name is provided, derive slug by replacing `/` with `-` (e.g., `hotfix/urgent-fix` → `hotfix-urgent-fix`).

---

## Config File Copying

New worktrees need `.env*` and `.mcp.json` files copied from the main repo root:

```bash
find "$REPO_ROOT" \( -name '.env*' -o -name '.mcp.json' \) -type f \
    ! -path '*/worktrees/*' \
    ! -path '*/bin/*' \
    ! -path '*/obj/*' \
    ! -path '*/.git/*' \
    | while read -r file; do
    rel_path="${file#$REPO_ROOT/}"
    target_dir="$WORKTREE_PATH/$(dirname "$rel_path")"
    mkdir -p "$target_dir"
    cp "$file" "$WORKTREE_PATH/$rel_path"
done
```

---

## Git Operations Policy

Worktree management skills are **infrastructure utilities**. They ARE allowed to use:
- `git stash` / `git stash push` / `git stash pop`
- `git checkout -- <file>` (selective file restore)
- `git worktree add` / `git worktree remove`
- `git branch` (create/delete branches)
- `git diff` / `git apply` (patch-based operations)

They ARE also allowed to commit and push **new worktree branches only** (never the user's working branch):
- `git add` + `git commit` — to commit the applied changes in a newly created worktree
- `git push -u origin <branch>` — to push the new branch to remote

---

## Remote Type Detection

Detect whether the repo's origin is Azure DevOps or GitHub:

```bash
REMOTE_URL="$(git config --get remote.origin.url)"
if [[ "$REMOTE_URL" == *"visualstudio.com"* ]] || [[ "$REMOTE_URL" == *"dev.azure.com"* ]]; then
    REMOTE_TYPE="azure-devops"
elif [[ "$REMOTE_URL" == *"github.com"* ]]; then
    REMOTE_TYPE="github"
else
    REMOTE_TYPE="unknown"
fi
```

Used by `wt-pr` (and any future skills needing remote awareness). If `REMOTE_TYPE` is `unknown`, ask the user.

---

## Setup Script

All `wt-*` skills use `setup-worktree.sh` (bundled in `wt-create/`) for worktree creation. The script handles:
- Branch creation from a source branch
- Worktree directory creation
- Config file copying
- ai-docs copying

Call it as: `bash .claude/skills/wt-create/setup-worktree.sh <slug> [--branch <name>] [--from <source>]`