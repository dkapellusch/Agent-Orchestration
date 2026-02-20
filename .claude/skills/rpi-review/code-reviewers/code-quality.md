---
description: "Code quality review covering bugs, conventions, readability, error handling, and API design"
argument-hint: "[file-or-directory]"
---

# Code Quality Review

---

## Target

- `$ARGUMENTS`: File or directory to review (defaults to changed files on current branch vs default branch)

If no argument provided, get the changed files:
```bash
BASE_BRANCH=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')
BASE_BRANCH=${BASE_BRANCH:-main}
git diff --name-only "$BASE_BRANCH"...HEAD
```

Read every target file AND the project's CLAUDE.md for conventions before analysis.

---

## Review Checklist

### Bugs & Logic Errors
- Off-by-one errors, incorrect boolean logic, unreachable code
- Null reference risks, unhandled edge cases
- Incorrect exception types or swallowed exceptions

### Convention Compliance (per CLAUDE.md)
- Primary constructors for DI
- Record types for DTOs
- No magic strings (use constants, `nameof()`, enums)
- No WHAT comments (only WHY comments allowed)
- XML docs (`///`) on all public APIs
- Vertical slice folder structure compliance

### Readability & Maintainability
- Method length (flag >50 lines)
- Naming clarity and consistency
- DRY violations and unnecessary duplication
- Overly complex expressions or deeply nested logic

### Error Handling
- Empty catch blocks or silent error swallowing
- Missing error propagation
- Inconsistent error handling patterns across the feature

### API Design
- Consistent endpoint naming and response shapes
- Proper use of HTTP status codes
- Input validation at system boundaries

---

## Output Format

For each finding:

```
### QUAL-{NNN}: {Title}

**Severity**: CRITICAL | HIGH | MEDIUM | LOW
**Category**: bug | convention | readability | error-handling | api-design
**File**: path/to/file.cs:line

**Issue**: {What is wrong and why}

**Current**:
{code snippet}

**Recommended**:
{code snippet}

**Effort**: Quick | Medium | Large
```

---

## Summary

```
## Code Quality Review Summary

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Bugs & Logic | | | | |
| Conventions | | | | |
| Readability | | | | |
| Error Handling | | | | |
| API Design | | | | |

**Overall Quality Risk**: CRITICAL | HIGH | MEDIUM | LOW

### Top 5 Fixes (ranked by impact)
1. ...
2. ...
3. ...
4. ...
5. ...
```
