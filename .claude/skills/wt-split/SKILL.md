---
name: wt-split
description: "Split changes from the current branch into one or more new worktrees. Use when the user says 'split changes', 'small branches', 'decompose branch', 'move changes to new branch', 'wt-split', or wants to break a branch into focused, reviewable pieces. Supports manual file selection and automatic agent-based analysis."
---

# /wt-split — Split Changes into Worktrees

**Announce at start:** "Splitting changes into worktrees."

**Shared conventions**: See [`wt-common.md`](../wt-common.md) for repo root resolution, branch naming, and git operations policy.

**Git policy exception**: Per `wt-common.md` Git Operations Policy, worktree management skills ARE allowed to run `git add`, `git commit`, and `git push` on **new worktree branches only** (never the user's working branch). This exception overrides the CLAUDE.md prohibition for the specific operations documented below.

**Note**: Auto Mode subsumes the originally-spec'd `wt-small-branches` use case. There is no separate `/wt-small-branches` command — use `/wt-split` or `/wt-split --auto` instead.

---

## Input

**`$ARGUMENTS`**: Instructions, flags, or file lists. If empty, defaults to auto mode.

```bash
/wt-split                                              # Auto: agents analyze and propose groupings
/wt-split --auto                                       # Explicit auto mode
/wt-split my-feature -- src/Slack/SlackService.cs      # Manual: extract specific files into one worktree
/wt-split refactor-auth                                # Manual: slug provided, interactive file selection
/wt-split split the SDK changes from the API changes   # Auto with guidance: agents use instructions as context
/wt-split --base staging                               # Auto against a specific base branch
```

### Mode Detection

Determine mode from `$ARGUMENTS`:

| Signal | Mode | Reason |
|--------|------|--------|
| No arguments | **Auto** | Nothing specified, analyze the branch |
| `--auto` flag | **Auto** | Explicit |
| Only prose instructions (no slug, no `--`) | **Auto with guidance** | User wants analysis, but with direction |
| Slug + `-- <files>` | **Manual** | User knows exactly what to extract |
| Slug alone (no `--`, no prose) | **Manual (interactive)** | User named it, will pick files |

### Flags (both modes)

| Flag | Effect | Default |
|------|--------|---------|
| `--auto` | Force auto mode | Inferred from arguments |
| `--base <branch>` | Branch to diff against | `origin/{default}` (fetched, auto-detected) |
| `--from <branch>` | Source branch for new worktree(s) | Same as `--base` (`origin/{default}`) |
| `-- <files...>` | Explicit file list (manual mode only) | Interactive selection |

---

## Auto Mode

Analyzes the full branch diff and proposes how to split it into multiple focused worktrees.

**Key principle: The current branch keeps its primary changes.** Only "extras" that don't belong
on this branch get split into new worktrees. The current branch is then cleaned up to contain
only its focused changes. The result is: current branch (cleaned) + N new branches.

### Phase 1: Gather Context

```bash
REPO_ROOT="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"
CURRENT_BRANCH="$(git branch --show-current)"
```

Fetch latest from origin and determine the base branch:
```bash
git fetch origin
```
- If `--base` provided, use that (prefix with `origin/` if it's a plain branch name without a remote prefix)
- Otherwise, detect origin's default: `git remote show origin | grep 'HEAD branch' | cut -d' ' -f5`, then use `origin/{default}` (e.g., `origin/master`)

**Always use the `origin/` prefixed ref** (e.g., `origin/master`, not `master`) to ensure diffs and worktrees start from the latest remote state, not a potentially stale local branch.

Get the full diff:
```bash
git diff {base_branch}...HEAD
git diff {base_branch}...HEAD --stat
git log {base_branch}..HEAD --oneline
git status --porcelain
```

If the diff is empty AND no uncommitted changes → **STOP** with: "No changes found between `{current_branch}` and `{base_branch}`. Nothing to split."

Note if there are both committed and uncommitted changes — they need different handling.

### Phase 2: Discover Change Sets

Dispatch **2-3 discovery agents sequentially** (Task tool, subagent_type: Explore) to analyze the diff. Per CLAUDE.md guideline #5, use sequential dispatch since the orchestrator must synthesize all results. If the user provided prose instructions, include them as context for each agent.

**IMPORTANT**: Every agent must also identify which group is the **primary purpose** of the current branch. Use the branch name, commit messages, and ai-docs specs as signals. For example, if the branch is `worktree-management-skills`, changes to `wt-*` skill files are the primary group and should stay.

**Agent 1 — Feature Grouping**:
> Analyze this git diff and identify distinct features or functional areas. Group files that logically belong together (e.g., a service + its models + its tests). Each group should be independently reviewable and mergeable.
>
> The current branch is named `{current_branch}`. Identify which group best matches the branch's stated purpose — that group stays on this branch. All other groups will be split into new worktrees.
>
> {user_instructions if provided}
>
> Diff stat: {diff_stat}
> Commit log: {commit_log}
>
> For each group, provide:
> - Suggested slug name
> - Files in the group
> - One-line description
> - Whether this is the PRIMARY group (matches the current branch's purpose)
> - Dependencies on other groups (if any)

**Agent 2 — Spec/ai-docs Alignment**:
> Check if any `ai-docs/` specs exist that describe planned work on this branch. Match diff files to specs. The spec that aligns with the branch name is the primary group.
>
> Look in: `ai-docs/` for any spec files related to this branch.
> Branch name: `{current_branch}`
> Diff stat: {diff_stat}

**Agent 3 — Directory-Based Grouping** (optional, use if diff is large):
> Group changed files by their top-level feature directory. This is a simpler heuristic for cross-checking semantic groupings.
>
> Diff stat: {diff_stat}

### Phase 3: Synthesize Proposal

Combine agent results using consensus:
- Files all agents agree on → high confidence group
- Files with disagreement → flag for user review
- Files no agent grouped → "ungrouped" bucket

**Designate the primary group**: The group that best matches the current branch's purpose. Use these signals (in priority order):
1. Branch name match (e.g., branch `worktree-management-skills` → wt-skill changes are primary)
2. Agent consensus on which group is primary
3. Largest group by file count (tiebreaker)

The primary group **stays on the current branch**. All other groups become new worktrees.

```
Proposed Split for branch: {current_branch}

STAYS on {current_branch} — "{description}"
  Files:
    - path/to/file1.cs (primary purpose of this branch)
    - path/to/file2.cs
  Confidence: HIGH

Split to NEW worktree: {slug-1} — "{description}"
  Files:
    - path/to/file3.cs
    - path/to/file4.cs
  Confidence: HIGH

Split to NEW worktree: {slug-2} — "{description}"
  Files:
    - path/to/file5.cs
  Confidence: MEDIUM

Ungrouped (remain on {current_branch}):
    - path/to/misc-file.cs
```

If only one logical group is found → **STOP** with: "All changes form a single cohesive unit. No split needed."

### Phase 4: User Confirmation

Present the proposal via `AskUserQuestion`:

> "Here's the proposed split. Changes matching the branch purpose stay on `{current_branch}`, extras go to new worktrees. Should I proceed?"

Options: "Proceed with this split" / "Modify groupings" / "Cancel"

If "Modify groupings": Ask what changes they want (move files between groups, change which group is primary, rename slugs, merge groups). Rebuild and re-present.
If "Cancel": **STOP**.

### Phase 5: Execute Split

Only create new worktrees for non-primary groups. The primary group's files stay untouched on the current branch.

**Every new worktree is based off `{base_branch}`** (e.g., `origin/master` or `--base` override), NOT the current branch. This ensures each new branch starts from the latest remote state and contains ONLY its group's changes, cleanly isolated.

For each **non-primary** group, process one at a time:

1. **Generate patches** capturing all changes (committed, staged, and unstaged) for this group's files:
   ```bash
   # Committed changes relative to base:
   git diff {base_branch}...HEAD -- {file1} {file2} ... > /tmp/{slug}-committed.patch
   # Uncommitted changes (staged + unstaged) on top of HEAD:
   git diff HEAD -- {file1} {file2} ... > /tmp/{slug}-working.patch
   ```
   Two patches are needed: `git diff {base_branch}...HEAD` captures committed changes; `git diff HEAD` captures both staged and unstaged working tree changes. A single `git diff {base_branch}` would miss staged-but-uncommitted changes.

   **For untracked new files** in the group (files that don't exist in the base branch and aren't tracked by git), note them separately — they'll be copied directly.

2. **Create worktree** from the base branch:
   ```bash
   bash .claude/skills/wt-create/setup-worktree.sh {slug} --branch feature/{slug} --from {base_branch}
   ```

3. **Apply the patches** in the new worktree:
   ```bash
   cd {repo_root}/worktrees/{slug}
   git apply /tmp/{slug}-committed.patch
   [ -s /tmp/{slug}-working.patch ] && git apply /tmp/{slug}-working.patch
   ```
   If apply fails, try `git apply --3way`. The working patch may be empty if all changes were committed — that's fine.

   **Copy any untracked new files** directly:
   ```bash
   mkdir -p {repo_root}/worktrees/{slug}/{parent_dir}
   cp {repo_root}/{untracked_file} {repo_root}/worktrees/{slug}/{untracked_file}
   ```

4. **Commit and push** the new branch:
   ```bash
   cd {repo_root}/worktrees/{slug}
   git add -A
   ```
   **Safety check**: Before committing, verify no `.env*` files are staged:
   ```bash
   if git diff --cached --name-only | grep -qiE '\.env'; then
       git diff --cached --name-only | grep -iE '\.env' | xargs git reset HEAD --
       echo "Unstaged .env files — these should be in .gitignore"
   fi
   ```
   Then commit and push:
   ```bash
   git commit -m "{slug}: {one-line description}"
   git push -u origin feature/{slug}
   ```
   If the push fails, report the error but continue — the worktree is still usable locally.

5. **Verify** the new worktree contains only this group's changes:
   ```bash
   cd {repo_root}/worktrees/{slug} && git diff {base_branch}...HEAD --stat
   ```
   If unexpected files appear, warn the user.

### Phase 6: Clean Current Branch

After all non-primary groups have been split to new worktrees, clean the current branch so it only contains its primary changes.

**Revert uncommitted changes** for split-off files (safe, reversible):
```bash
# Tracked files with uncommitted modifications:
git checkout -- {split_tracked_file1} {split_tracked_file2} ...
# Untracked files — only delete after confirming the copy succeeded:
for file in {split_untracked_file1} {split_untracked_file2} ...; do
    if [ -f "{repo_root}/worktrees/{slug}/$file" ]; then
        rm "$file"
    else
        echo "WARNING: Skipping rm of $file — not found in new worktree (copy may have failed)"
    fi
done
```

**For committed changes that were split off**, report to the user with cleanup instructions:

> "The split-off changes have been copied to new worktrees and pushed to remote. To clean `{current_branch}` so it only contains {primary_group_description}:
>
> **Option A** — Mixed reset (recommended, cleanest result):
> ```bash
> git reset {base_branch}
> git add {primary_file1} {primary_file2} ...
> git commit -m "{primary_group_description}"
> ```
>
> **IMPORTANT**: Use mixed reset (no `--soft` flag). `--soft` keeps all changes staged,
> so `git add` on specific files won't unstage the rest — you'll commit everything.
>
> **Option B** — If you want to keep your commit history and just remove the split files:
> ```bash
> git checkout {base_branch} -- {split_file1} {split_file2} ...
> git commit -m "Remove changes split to other branches"
> ```"

**Do NOT run these cleanup commands automatically** — the user must review and choose their preferred cleanup approach.

### Verification

After the user runs cleanup, verify the branch contains only expected files:

```bash
git diff {base_branch}...HEAD --stat
```

If unexpected files appear, warn the user before they force-push. This is the last safety check.

### Phase 7: Report

```
Branch split complete: {current_branch}

KEPT on {current_branch}: {primary_description}
  {primary_file_count} files (branch purpose)

NEW worktrees created:

| Worktree | Branch | Files | Description |
|----------|--------|-------|-------------|
| worktrees/{slug-1} | feature/{slug-1} | {count} | {description} |
| worktrees/{slug-2} | feature/{slug-2} | {count} | {description} |

Ungrouped files (remain on {current_branch}):
  - {file1}

{cleanup_instructions from Phase 6}
```

---

## Manual Mode

Extracts specific files from the current branch into one new worktree.

### Step 1: Validate State

```bash
REPO_ROOT="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"
CURRENT_BRANCH="$(git branch --show-current)"
git status --porcelain
```

Fetch latest and determine the base branch (same logic as auto mode):
```bash
git fetch origin
```
- If `--base` provided, use that (prefix with `origin/` if it's a plain branch name)
- Otherwise, detect origin's default: `git remote show origin | grep 'HEAD branch' | cut -d' ' -f5`, then use `origin/{default}`

**Always use the `origin/` prefixed ref** to ensure worktrees start from the latest remote state.

Check for changes: `git diff {base_branch} --stat` (committed + uncommitted) and `git status --porcelain` (untracked).

If no changes at all → **STOP** with: "No changes to split. Use `/wt-create` for an empty worktree."

### Step 2: Determine Files

**If `-- <files>` provided**: Use those. Validate they exist and have changes (via `git diff {base_branch} -- {file}` or `git status`).

**If no files specified**: Present changed files to the user via `AskUserQuestion` (multiSelect: true). Include both committed and uncommitted changes.

### Step 3: Check Hunk Granularity

For each selected file with multiple distinct hunks, inform the user:

> "File `{file}` has {N} separate change hunks. Moving the entire file. If you need hunk-level splitting, I can extract specific hunks."

If user requests hunk-level splitting:
1. Show hunks via `git diff {base_branch} -- {file}`
2. User selects hunks
3. Create patch with selected hunks only
4. Apply patch in new worktree

### Step 4: Create Worktree and Apply Changes

The new worktree is based off `{base_branch}` (e.g., `origin/master`), NOT the current branch. This ensures it starts from the latest remote state and contains ONLY the selected files' changes.

1. **Generate patches** capturing all changes for the selected files:
   ```bash
   # Committed changes relative to base:
   git diff {base_branch}...HEAD -- {file1} {file2} ... > /tmp/{slug}-committed.patch
   # Uncommitted changes (staged + unstaged) on top of HEAD:
   git diff HEAD -- {file1} {file2} ... > /tmp/{slug}-working.patch
   ```
   Note any **untracked new files** — they'll be copied directly.

2. **Create worktree** from the base branch:
   ```bash
   bash .claude/skills/wt-create/setup-worktree.sh {slug} --branch feature/{slug} --from {base_branch}
   ```

3. **Apply the patches** in the new worktree:
   ```bash
   cd {repo_root}/worktrees/{slug}
   git apply /tmp/{slug}-committed.patch
   [ -s /tmp/{slug}-working.patch ] && git apply /tmp/{slug}-working.patch
   ```
   If apply fails, try `git apply --3way`. The working patch may be empty — that's fine.

   **Copy any untracked new files** directly:
   ```bash
   mkdir -p {repo_root}/worktrees/{slug}/{parent_dir}
   cp {repo_root}/{untracked_file} {repo_root}/worktrees/{slug}/{untracked_file}
   ```

### Step 5: Commit and Push

Stage, commit, and push the new worktree branch to remote:

```bash
cd {repo_root}/worktrees/{slug}
git add -A
```
**Safety check**: Before committing, verify no `.env*` files are staged:
```bash
if git diff --cached --name-only | grep -qiE '\.env'; then
    git diff --cached --name-only | grep -iE '\.env' | xargs git reset HEAD --
    echo "Unstaged .env files — these should be in .gitignore"
fi
```
Then commit and push:
```bash
git commit -m "{slug}: {one-line description of the split changes}"
git push -u origin feature/{slug}
```

If the push fails (e.g., no remote access), report the error but don't block — the worktree is still usable locally.

### Step 6: Clean Split Files from Current Branch

Revert the split-off files on the current branch:

```bash
# Tracked files with uncommitted modifications:
git checkout -- {file1} {file2} ...
# Untracked files — only delete after confirming the copy succeeded:
for file in {untracked_file1} {untracked_file2} ...; do
    if [ -f "{repo_root}/worktrees/{slug}/$file" ]; then
        rm "$file"
    else
        echo "WARNING: Skipping rm of $file — not found in new worktree (copy may have failed)"
    fi
done
```

For **committed changes** to the split files, provide cleanup instructions (same as Auto Mode Phase 6) — do NOT auto-run.

### Step 7: Report

```
Changes split successfully:
  New worktree: {repo_root}/worktrees/{slug}
  Branch: feature/{slug} (pushed to remote)
  Files moved: {count}
    - {file1}
    - {file2}

Original branch ({current_branch}) cleanup:
  - Uncommitted changes reverted for split files
  - {cleanup_instructions for committed changes if applicable}
```

---

## Error Handling

| Error | Action |
|-------|--------|
| No changes from base | STOP: nothing to split |
| Single change set (auto) | STOP: no split needed |
| No arguments + no changes | STOP with usage examples |
| Patch apply failure | Try `--3way`, then leave patch file and report |
| Worktree creation fails | Report, skip group, continue |
| Push fails | Report error, continue — worktree is still usable locally |
| Specified files invalid | Report which, continue with valid ones |