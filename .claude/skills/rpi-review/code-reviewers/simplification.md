---
description: "Simplification analysis for dead code, duplication, over-engineering, and reduction opportunities"
argument-hint: "[feature-name-or-directory]"
---

# Simplification Review

---

## Target

- `$ARGUMENTS`: Feature name or directory to analyze (defaults to changed files on current branch vs default branch)

If no argument provided, get the changed files:
```bash
BASE_BRANCH=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')
BASE_BRANCH=${BASE_BRANCH:-main}
git diff --name-only "$BASE_BRANCH"...HEAD
```

Read every target file before analysis.

---

## Review Checklist

### Dead Code
- Unreachable branches, unused methods/classes/parameters
- Commented-out code blocks
- Unused imports and `using` statements
- Orphaned files (no references from anywhere)

### Duplication
- Copy-pasted logic across files or methods
- Near-duplicates that differ by 1-2 parameters
- Multiple implementations of the same concept

### Over-Engineering
- Abstractions with only one implementation (and no planned second)
- Configuration/flexibility that's never used
- Wrapper classes that add no value
- Premature optimization patterns

### Consolidation Opportunities
- Multiple small classes that could merge into one
- Utility methods that belong in an existing shared helper
- Feature code that duplicates shared infrastructure

---

## Output Format

For each finding:

```
### SIMP-{NNN}: {Title}

**Severity**: HIGH | MEDIUM | LOW
**Category**: dead-code | duplication | over-engineering | consolidation
**File**: path/to/file.cs:line
**Lines Removable**: ~N

**Issue**: {What can be simplified and why}

**Current**:
{code snippet}

**Recommended**:
{simplified code or "delete"}

**Effort**: Quick | Medium | Large
```

---

## Summary

```
## Simplification Review Summary

| Category | Findings | Lines Removable |
|----------|----------|-----------------|
| Dead Code | | |
| Duplication | | |
| Over-Engineering | | |
| Consolidation | | |
| **Total** | | **~N lines** |

### Top 5 Simplifications (ranked by lines saved)
1. ...
2. ...
3. ...
4. ...
5. ...
```
