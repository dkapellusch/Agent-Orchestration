#!/bin/bash
# setup-worktree.sh - Create and configure a git worktree for feature development
#
# Usage: setup-worktree.sh <slug> [--branch <name>] [--from <source-branch>]
#
# Arguments:
#   slug            - The worktree folder name (e.g., "permission-url", "jira-attachment")
#   --branch <name> - Optional: Custom branch name (default: feature/<slug>)
#   --from <source> - Optional: Branch to create from (default: origin's default branch)
#
# This script:
#   1. Resolves the main repo root (never nests inside existing worktrees)
#   2. Creates a branch from the source branch
#   3. Creates a worktree at ./worktrees/<slug>
#   4. Copies all .env* and .mcp.json files preserving directory structure
#   5. Copies ai-docs for the feature if they exist

set -e

SLUG=""
BRANCH_OVERRIDE=""
SOURCE_BRANCH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --branch)
            BRANCH_OVERRIDE="$2"
            shift 2
            ;;
        --from)
            SOURCE_BRANCH="$2"
            shift 2
            ;;
        *)
            if [ -z "$SLUG" ]; then
                SLUG="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$SLUG" ] || ! echo "$SLUG" | grep -qE '^[a-zA-Z0-9_-]+$'; then
    if [ -n "$SLUG" ]; then
        echo "ERROR: Slug must contain only letters, numbers, hyphens, and underscores: '$SLUG'"
    fi
    echo "Usage: $0 <slug> [--branch <name>] [--from <source-branch>]"
    echo ""
    echo "Arguments:"
    echo "  slug              - The worktree folder name (e.g., 'permission-url')"
    echo "  --branch <name>   - Custom branch name (default: feature/<slug>)"
    echo "  --from <source>   - Branch to create from (default: origin's default branch)"
    echo ""
    echo "Examples:"
    echo "  $0 my-feature"
    echo "  $0 my-feature --from staging"
    echo "  $0 urgent-fix --branch hotfix/urgent-fix"
    echo "  $0 urgent-fix --branch hotfix/urgent-fix --from main"
    exit 1
fi

# Always resolve to the MAIN repo root, even when inside a worktree
REPO_ROOT="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"
WORKTREE_PATH="$REPO_ROOT/worktrees/$SLUG"
BRANCH_NAME="${BRANCH_OVERRIDE:-feature/$SLUG}"

echo "=== Setting up worktree: $SLUG ==="
echo "Repository root: $REPO_ROOT"
echo "Worktree path: $WORKTREE_PATH"
echo "Branch: $BRANCH_NAME"

# Get default branch if not specified
if [ -z "$SOURCE_BRANCH" ]; then
    SOURCE_BRANCH=$(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5)
    echo "Source branch (auto-detected): origin/$SOURCE_BRANCH"
else
    echo "Source branch: $SOURCE_BRANCH"
fi

# Ensure we're in the repo root
cd "$REPO_ROOT"

# Create worktrees directory if it doesn't exist
mkdir -p "$REPO_ROOT/worktrees"

# Check if worktree already exists
if [ -d "$WORKTREE_PATH" ]; then
    echo "ERROR: Worktree already exists at $WORKTREE_PATH"
    echo "To remove it: git worktree remove worktrees/$SLUG"
    exit 1
fi

# Fetch latest from origin
echo ""
echo "=== Fetching latest from origin ==="
# Strip origin/ prefix if present to avoid double-prefixing (e.g., origin/origin/master)
BARE_SOURCE="${SOURCE_BRANCH#origin/}"
git fetch origin "$BARE_SOURCE"

# Create branch from origin if it doesn't exist
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    echo "Branch $BRANCH_NAME already exists"
else
    echo "Creating branch $BRANCH_NAME from origin/$BARE_SOURCE"
    git branch "$BRANCH_NAME" "origin/$BARE_SOURCE"
fi

# Create worktree
echo ""
echo "=== Creating worktree ==="
git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"

# Copy .env* and .mcp.json files
echo ""
echo "=== Copying configuration files ==="
cd "$REPO_ROOT"

# Find and copy .env* files (but not from worktrees or bin/obj directories)
# Use process substitution to keep loop in main shell — set -e won't propagate through pipe subshells
COPY_ERRORS=0
while IFS= read -r file; do
    rel_path="${file#./}"
    target_dir="$WORKTREE_PATH/$(dirname "$rel_path")"
    mkdir -p "$target_dir"
    if cp "$file" "$WORKTREE_PATH/$rel_path"; then
        echo "  Copied: $rel_path"
    else
        echo "  ERROR: Failed to copy $rel_path"
        COPY_ERRORS=$((COPY_ERRORS + 1))
    fi
done < <(find . \( -name '.env*' -o -name '.mcp.json' \) -type f \
    ! -path './worktrees/*' \
    ! -path '*/bin/*' \
    ! -path '*/obj/*' \
    ! -path '*/.git/*')

if [ "$COPY_ERRORS" -gt 0 ]; then
    echo "WARNING: $COPY_ERRORS config file(s) failed to copy. Check permissions and disk space."
fi

# Copy ai-docs for this feature if they exist
echo ""
echo "=== Checking for ai-docs ==="
if find ai-docs -maxdepth 1 -name "*${SLUG}*" -type d 2>/dev/null | grep -q .; then
    mkdir -p "$WORKTREE_PATH/ai-docs/$SLUG"
    for dir in ai-docs/*"${SLUG}"*/; do
        [ -d "$dir" ] || continue
        echo "  Copying: $dir"
        cp -r "$dir"/* "$WORKTREE_PATH/ai-docs/$SLUG/" 2>/dev/null || true
    done
else
    echo "  No existing ai-docs found for $SLUG"
    mkdir -p "$WORKTREE_PATH/ai-docs/$SLUG"
fi

# Summary
echo ""
echo "=== Worktree setup complete ==="
echo ""
echo "Worktree: $WORKTREE_PATH"
echo "Branch:   $BRANCH_NAME"
echo ""
echo "Files copied:"
find "$WORKTREE_PATH" \( -name '.env*' -o -name '.mcp.json' \) -type f 2>/dev/null | while read -r f; do
    echo "  ${f#$WORKTREE_PATH/}"
done
echo ""
echo "Next steps:"
echo "  cd $WORKTREE_PATH"
echo "  # Make your changes, then review with git status before committing"