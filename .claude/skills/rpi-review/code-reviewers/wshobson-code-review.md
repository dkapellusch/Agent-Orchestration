---
description: "Multi-agent parallel review across 5 dimensions with consolidated report (adapted from wshobson/commands)"
argument-hint: "[file-or-directory]"
---

# Multi-Agent Code Review

Adapted from [wshobson/commands](https://github.com/wshobson/commands) (`workflows/full-review.md`).

---

## Target

- `$ARGUMENTS`: File or directory to review (defaults to changed files on current branch vs default branch)

If no argument provided, get the changed files:
```bash
BASE_BRANCH=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')
BASE_BRANCH=${BASE_BRANCH:-main}
git diff --name-only "$BASE_BRANCH"...HEAD
```

---

## Phase 1: Parallel Specialized Reviews (5 Agents in ONE Message)

Launch ALL 5 agents in a SINGLE message using the Task tool. Each runs independently.

### Agent 1: Code Quality Review

```
Task: "Code quality review" | general-purpose | model: opus
Prompt: |
  Review code quality and maintainability for the changed files on this branch.

  Use the changed file list resolved in the Target section.

  Read each changed file, then check for:
  - Code smells and readability issues
  - Naming conventions and consistency
  - SOLID principles adherence
  - DRY violations and duplication
  - Documentation gaps on public APIs
  - Magic strings and hardcoded values

  For each finding provide: file, line, severity (CRITICAL/HIGH/MEDIUM/LOW), description, fix.
  Return findings as structured JSON.
```

### Agent 2: Security Audit

```
Task: "Security audit" | general-purpose | model: opus
Prompt: |
  Perform a security audit on the changed files on this branch.

  Use the changed file list resolved in the Target section.

  Read each changed file, then check for:
  - OWASP Top 10 vulnerabilities (injection, broken auth, XSS, etc.)
  - Hardcoded secrets, keys, passwords, connection strings
  - Missing input validation and sanitization
  - Authorization gaps (missing [Authorize], direct object references)
  - Sensitive data in logs or error messages
  - Insecure deserialization

  For each finding provide: file, line, severity, CWE ID, description, fix.
  Return findings as structured JSON.
```

### Agent 3: Architecture Review

```
Task: "Architecture review" | general-purpose | model: opus
Prompt: |
  Review architectural design and patterns in the changed files on this branch.

  Use the changed file list resolved in the Target section.

  Read each changed file and the project's CLAUDE.md for conventions, then check for:
  - Service boundary violations and inappropriate coupling
  - Design pattern compliance (vertical slice, IFeature, etc.)
  - Dependency direction (do dependencies flow correctly?)
  - Layer violations (controllers bypassing services)
  - DI lifetime correctness (scoped injected into singleton)
  - Circular dependencies between features

  For each finding provide: file, line, severity, description, fix.
  Return findings as structured JSON.
```

### Agent 4: Performance Analysis

```
Task: "Performance analysis" | general-purpose | model: opus
Prompt: |
  Analyze performance characteristics of the changed files on this branch.

  Use the changed file list resolved in the Target section.

  Read each changed file, then check for:
  - Algorithmic complexity issues (O(n^2) in hot paths)
  - N+1 query patterns (database calls inside loops)
  - Multiple enumeration of IEnumerable/IQueryable
  - Async anti-patterns (.Result, .Wait(), async void)
  - Missing CancellationToken propagation
  - Resource leaks (IDisposable without using)
  - Unnecessary allocations in hot paths (boxing, LINQ in loops)
  - Missing caching opportunities

  For each finding provide: file, line, severity, current complexity, recommended complexity, description, fix.
  Return findings as structured JSON.
```

### Agent 5: Test Coverage Assessment

```
Task: "Test coverage assessment" | general-purpose | model: opus
Prompt: |
  Evaluate test coverage and quality for the changed files on this branch.

  Use the changed file list resolved in the Target section.

  For each changed file, check:
  - Does a corresponding test file exist? (Tests/Fast/ and Tests/Slow/)
  - Are new code paths covered by tests?
  - Are edge cases and error paths tested?
  - Test quality: meaningful assertions (not just NotNull)?
  - Are mocks at the right level (boundary, not own interfaces)?
  - Skipped or commented-out tests?
  - Missing integration tests for new API endpoints?

  Run: dotnet test --list-tests to see available tests.

  For each gap provide: file, line, severity, what's missing, suggested test.
  Return findings as structured JSON.
```

**Wait for ALL 5 agents to complete before Phase 2.**

---

## Phase 2: Consolidate Report

Compile all agent findings into a unified report:

### Critical Issues (must fix)
Security vulnerabilities, bugs, data loss risks, resource leaks.

### High (should fix)
Performance bottlenecks, architecture violations, missing tests for new code.

### Medium (plan to fix)
Code quality issues, convention violations, test quality improvements.

### Low (nice to have)
Documentation improvements, minor refactoring suggestions.

---

## Output Format

```
## Multi-Agent Code Review: {branch_name}

**Agents**: Quality, Security, Architecture, Performance, Testing
**Files Reviewed**: {count}

### Risk Assessment

| Dimension | Risk | Critical | High | Medium | Low |
|-----------|------|----------|------|--------|-----|
| Code Quality | | | | | |
| Security | | | | | |
| Architecture | | | | | |
| Performance | | | | | |
| Test Coverage | | | | | |
| **Overall** | | | | | |

### Verdict: APPROVED | APPROVED_WITH_NOTES | NEEDS_WORK | BLOCKED

{One paragraph summary}

---

### CRITICAL ({count})
{findings}

### HIGH ({count})
{findings}

### MEDIUM ({count})
{findings}

### LOW ({count})
{findings}

---

### Action Items (Priority Order)

| # | Severity | Dimension | File:Line | Action | Effort |
|---|----------|-----------|-----------|--------|--------|
| 1 | | | | | |

```

---

## Attribution

Based on [wshobson/commands](https://github.com/wshobson/commands) full-review workflow.
