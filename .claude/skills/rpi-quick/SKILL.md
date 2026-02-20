---
name: rpi-quick
description: "Lightweight RPI workflow for small-to-medium tasks — thinks inline, dispatches 3 sequential agents (implement, test, validate), no documents, no user interaction. Use when the request is clear and doesn't need research or planning phases."
---

# /rpi-quick — Think, Do, Verify

**Announce at start:** "I'm using the rpi-quick skill for a lightweight implement-test-validate loop."

You are a **lean orchestrator**. You think inline, dispatch exactly 3 sequential agents, and report the result. No documents are written. No user interaction during execution. The user's request is the spec.

**Shared conventions**: See [`rpi-common.md`](../rpi-common.md) for critical rules and test philosophy used across all RPI skills.

---

## Input

**`$ARGUMENTS`**: The task to implement. Must be provided.

```bash
/rpi-quick "add retry logic to the Slack service"
/rpi-quick "fix the null reference in JiraService.GetIssue"
/rpi-quick "add Tableau config binding tests"
```

If `$ARGUMENTS` is empty → **STOP** with: "No task provided. Usage: `/rpi-quick \"your task\"`"

---

## Phase 1: Think (orchestrator — no agents)

You do this yourself. Do NOT delegate thinking to agents.

### 1a: Understand the Request

Parse `$ARGUMENTS` as `{request}`.

### 1b: Read Context

Read the minimum files needed to understand the task:

1. **CLAUDE.md** / **README.md** at the project root — conventions, patterns, test architecture
2. **Feature CLAUDE.md** — if the task targets a specific feature, read its `CLAUDE.md`
3. **Affected files** — read the files that will need to change (use Glob/Grep to find them)
4. **Pattern file** — find one similar existing implementation to mirror (e.g., if adding a new config test, find an existing config test)

### 1c: Define the Plan

Determine and log inline (not to a file):

- **What files need to change** — list each file and what changes
- **Pattern file** — the existing file to mirror
- **Acceptance criteria** — concrete, testable statements ("how will we know this is done?")
- **Test command** — the specific `dotnet test --filter` (or equivalent) to verify

### 1d: Verify Scope

If the task requires more than ~10 files or touches multiple unrelated features, warn:

```
"This task looks larger than rpi-quick is designed for. Consider /rpi-all instead.
Proceeding anyway — but expect less thoroughness than the full pipeline."
```

Continue regardless — the user chose this skill intentionally.

---

## Phase 2: Implement (1 agent)

Dispatch a Task agent:

```
Task: "Implement: {short summary}" | subagent_type: general-purpose
Prompt:
  You are implementing a task. Make the code changes, ensure they compile,
  and follow project conventions exactly.

  REQUEST: {request}

  FILES TO CHANGE:
  {file list with what to change in each}

  PATTERN FILE: {path}
  Read this file first. Match its conventions exactly.

  PROJECT CONVENTIONS:
  {relevant excerpts from CLAUDE.md — naming, style, test patterns}

  ACCEPTANCE CRITERIA:
  {numbered list}

  RULES:
  - Read the pattern file before writing any code.
  - Read each file you're modifying before changing it.
  - Match existing style — don't "improve" adjacent code.
  - Every changed line must trace to the acceptance criteria.
  - Build after changes — must compile with zero errors.
  - Do NOT run tests — that's the next agent's job.
  - Do NOT write to ai-docs/ or create any documents.

  Return:
  - Files changed (list with brief description of each change)
  - Build result (pass/fail)
  - Any decisions you made that weren't explicit in the request
```

If the agent reports build failure → dispatch a fix agent (max 1 retry with the compiler output). If still failing after retry, report the error and stop.

---

## Phase 3: Test (1 agent)

Dispatch a Task agent:

```
Task: "Test: {short summary}" | subagent_type: general-purpose
Prompt:
  You are verifying that code changes work correctly.

  WHAT WAS IMPLEMENTED: {summary from Phase 2}
  FILES CHANGED: {list from Phase 2}

  ACCEPTANCE CRITERIA:
  {numbered list}

  TEST COMMAND: {test command from Phase 1}

  ZERO TOLERANCE TEST POLICY:
  ALL tests must pass — not just new ones. The full suite must be green.
  You may NOT skip tests, comment out assertions, disable tests, or
  claim a failure is "pre-existing" or "not related to my changes."
  If a test fails, fix it.

  Steps:
  1. Run the targeted test command: {test command}
  2. If any tests fail:
     a. Read the failing test and the code it tests
     b. Fix the issue (in test or implementation code)
     c. Re-run — must pass
     d. Max 2 fix attempts per failure
  3. Run `dotnet test` for the full affected project to catch regressions
  4. If full suite has failures, fix them (same process)

  Return:
  - Targeted test result: {passed}/{total}
  - Full suite result: {passed}/{total}
  - Fixes applied (if any): {list}
  - Status: ALL_PASS or FAILURES_REMAIN
```

If FAILURES_REMAIN → report what failed and stop. Do not proceed to validation.

---

## Phase 4: Validate (1 agent)

Dispatch a Task agent:

```
Task: "Validate: {short summary}" | subagent_type: general-purpose
Prompt:
  You are validating that the original request is fully satisfied.
  You are a reviewer, NOT an implementer — do not change any code.

  ORIGINAL REQUEST: {request}

  ACCEPTANCE CRITERIA:
  {numbered list}

  FILES CHANGED: {list from Phase 2}

  Steps:
  1. Read every changed file
  2. For each acceptance criterion:
     - Is it fully implemented? (not partially, not "close enough")
     - Is there a test that proves it?
     - Would it break if the feature broke?
  3. Check for scope creep:
     - Was anything added that wasn't in the request?
     - Were any "improvements" made to adjacent code?
  4. Check for missed items:
     - Does the request ask for anything not covered by the ACs?
     - Are there obvious edge cases the ACs missed?

  Return:
  - Verdict: DONE or INCOMPLETE
  - AC status: {each AC with pass/fail and evidence}
  - Scope creep: {any extra changes not in the request}
  - Gaps: {anything missing}
```

---

## Phase 5: Report (orchestrator)

### If DONE:

```
/rpi-quick complete: {request}

Changes:
  {list of files changed with brief descriptions}

Acceptance Criteria:
  ✅ {AC 1}
  ✅ {AC 2}
  ...

Tests: {passed}/{total} passing

Changes ready for review. Run `git status` and `git diff`.
```

### If INCOMPLETE (first attempt):

Loop back to Phase 2 once with the gaps as additional context:

```
Append to implement prompt:
  GAPS FROM VALIDATION:
  {list of gaps from validator}

  Fix these specific issues. Do not re-implement what already works.
```

Then re-run Phases 2 → 3 → 4. Max 1 retry of the full cycle.

### If INCOMPLETE (after retry):

```
/rpi-quick partially complete: {request}

Completed:
  ✅ {ACs that passed}

Remaining:
  ❌ {ACs that failed — with explanation}

Changes ready for review. Run `git status` and `git diff`.
The remaining items may need manual attention or a full /rpi-all run.
```

---

## Rules

- **No documents** — nothing written to `ai-docs/`, no research.md, no spec.md
- **No user interaction** — no AskUserQuestion, no confirmation gates, no walkthroughs
- **Orchestrator thinks, agents do** — Phase 1 is yours (read files, define ACs). Phases 2-4 are agents.
- **3 agents max** — implement, test, validate. No parallel swarms, no teams.
- **1 retry max** — if validate says INCOMPLETE, loop once. After that, report and stop.
- **Zero tolerance test policy** — from `rpi-common.md`. All tests must pass.

---

## When NOT to Use This Skill

| Situation | Use Instead |
|-----------|-------------|
| Unclear requirements needing research | `/rpi-research` then `/rpi-plan` |
| Large feature spanning many files | `/rpi-all` |
| Need stakeholder buy-in on approach | `/rpi-plan` |
| Just need a code review | `/rpi-review` |
| Trivial one-line fix | Just do it directly — no skill needed |
