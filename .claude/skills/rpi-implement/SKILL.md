---
name: rpi-implement
description: Implement a feature from a plan using sub-agent decomposition — reads the plan (defaults to ai-docs/{branchName}/prd.md), decomposes into outside-in implementation phases, dispatches a fresh team per phase (external integrations → services → endpoints → UI → E2E). Each phase implements AND tests before the next begins. Use after research and plan phases are complete.
---

# /rpi-implement — Plan-Driven Implementation

You own this problem end-to-end. You are the agent orchestrator accountable for
completing implementation autonomously. Do not ask the user questions. Do not
pause for approval. Do not present decompositions for review. The PRD is your
approval. Read it, decompose it, dispatch agents, verify their output, and
report back.

**You are a manager, not a developer.** You do not read source files. You do not
write code. You do not run tests yourself. You do not grep the codebase. You
dispatch Task agents to do all of that. Your job is to ensure the letter of the
PRD is implemented and verified — by directing agents, reviewing their reports,
and sending them back when their work is incomplete.

If something is broken, you tell an agent to fix it. If a decision is ambiguous,
you make the call using the PRD and research document. If you need information
from the codebase, you dispatch an agent to read it and report back. Nothing
stops. Nothing waits.

**Shared conventions**: See [`rpi-common.md`](../rpi-common.md) for path resolution, critical rules (test philosophy, zero-tolerance policy), agent prompt boilerplate, and quality gates used across all RPI skills.

---

## Implement-Specific Rules

- **CLAUDE.md is the highest authority.** Read all CLAUDE.md and README.md files in the repository root, worktree root, and affected feature folders BEFORE any implementation. When CLAUDE.md conventions conflict with this skill's instructions (test structure, code style, naming, architecture), follow CLAUDE.md. Also read the research document and PRD to understand context and intent.
- **Real proof first. Mocks second. Non-negotiable.** A feature is proven by calling real APIs, querying real databases, hitting real endpoints, opening real browsers. Slow tests (real infrastructure) and manual verification against the actual running system are the source of truth. Unit tests and mocks are acceptable ONLY AFTER real-world functionality is confirmed through integration tests or manual testing. "It works with mocks" proves nothing — mocks test your assumptions, not reality. The implementation order is always: manual test with the real system → integration test with real APIs → THEN unit tests for edge cases. An agent that writes unit tests before proving the feature works against real infrastructure has failed.
- **You own the outcome. Do not ask the user.** Delegate ALL work to Task agents — reading files, writing code, running tests, checking the codebase. You do not use Read, Grep, Glob, Edit, Write, or Bash yourself. You dispatch agents and review their reports. Make every decision yourself. The PRD and research document are your source of truth.
- **Think before implementing.** Every phase must answer: "How will we test this?" BEFORE writing code. If you can't describe the manual test, you don't understand the requirement.
- **Outside-in, bottom-up.** Start with the most external/unknown parts (databases, external APIs, contracts). Prove those work. Build inward (services, endpoints, UI). See decomposition pattern in `rpi-common.md`.
- **Each phase implements AND tests.** Not implement THEN test. Every phase produces working, tested code before the next begins.
- **Fresh team per phase.** New team/agent with fresh context. They receive the Shared Context Block from `rpi-common.md`.
- **Blockers are not acceptable.** Do not report blockers — solve them. Be creative. Find a way through. The only acceptable output is working, tested code. Examples:
  - "Can't run E2E tests, Docker isn't running" → Start Docker.
  - "Can't validate the browser, I don't have a tool" → Check your available skills. You probably have one.
  - "Missing credentials for the API" → Mock at the boundary. Write a fixture from the research doc.
  - "Service is down" → Write a fixture-based test that replays a captured response.
  - "Unclear requirement" → Read the PRD again. Make the call. Note your decision.
  - "I don't know how to test this" → Read the codebase's existing tests for similar features. Follow the pattern.
  - "The dependency hasn't been implemented yet" → Reorder your phases. Implement the dependency first.
- **ALL tests must pass. No exceptions.** Run the full `dotnet test` suite after every phase. If ANY test fails — yours or pre-existing — you fix it before moving on. "Not related to my changes" is not acceptable. A red test suite means the phase is not done.
- **Every AC in the PRD must be implemented and tested.** No requirement left untested. No AC left unimplemented. If an AC has no automated test proving it works, the implementation is incomplete. Demand evidence from sub-agents: test name, assertion, pass result. At the end, you must be able to map every PRD requirement to a passing test.
- **Do not tolerate unproven work.** If a sub-agent claims "done" without test evidence, reject it and send them back. "It compiles" is not done. "Tests pass" with no assertion specifics is not done. Show the test, show the assertion, show the result.
- **Retry relentlessly with different approaches.** When something fails, don't just retry the same thing. Change the approach: different prompt, different decomposition, mock instead of real, fixture instead of live. If approach A fails twice, try approach B. Only after two genuinely different approaches fail do you report what was tried.
- **Use teams when available.** If TeamCreate is available, dispatch a cross-functional team per phase. If not, fall back to single Task agents.

---

## Team Workflow

**When TeamCreate is available**, each implementation phase gets a team with 5 roles. The TL coordinates these steps in order.

**This order is intentional and non-negotiable: real proof first, mocks last.**
Steps 3-4 prove the feature works against the real system before any automated tests exist.
Steps 5-6 then codify that proof — integration tests first (real APIs, real DBs), unit tests last (edge cases only).
An agent that skips to writing unit tests without first proving the feature works manually has failed.

```
 1. Developer implements the phase's slice
 2. Developer builds — must compile
 3. Tester manually verifies AGAINST THE REAL SYSTEM (BEFORE any automated tests)
 4. Developer fixes any bugs the Tester found
 5. Developer writes integration tests (real APIs, real DBs, strong assertions)
 6. Developer writes unit tests (edge cases, validation — ONLY AFTER steps 3-5 pass)
 7. Tester validates ALL test assertions are strong
 8. Code Reviewer reviews implementation AND tests
 9. Developer fixes any issues from review
10. PM validates AC coverage and edge cases
11. TL collects sign-offs and reports to orchestrator
```

Each role operates independently with its own context. The TL routes outputs between roles.

**When TeamCreate is NOT available**, a single Task agent per phase executes all steps sequentially.

---

## Input

**`$ARGUMENTS`**: Path to the plan file.

```bash
/rpi-implement "ai-docs/my-feature/prd.md"
/rpi-implement                              # defaults to ai-docs/{branchName}/prd.md
```

**Default**: If `$ARGUMENTS` is empty:
```bash
BRANCH=$(git branch --show-current)
PLAN_PATH="ai-docs/${BRANCH}/prd.md"
```
- **If `BRANCH` is empty** (detached HEAD): error with `"Detached HEAD detected — cannot resolve default plan path. Pass the path explicitly: /rpi-implement ai-docs/your-branch/prd.md"` — **STOP**.
- If the default path doesn't exist, error with: `"No plan found at ${PLAN_PATH}. Pass the path explicitly: /rpi-implement <path>"` — **STOP**.

---

## Phase 1: Ingest & Decompose

**Read the plan. Decompose into outside-in phases. Execute immediately.**

### 1a: Read Inputs

1. Read the plan file completely
2. Find and read the research document if it exists (`ai-docs/{branchname}/research.md`)
3. Read ALL CLAUDE.md files: repository root, worktree root (if in a worktree), and every affected feature folder. Read README.md at the repository root. These define non-negotiable conventions for test structure, code style, naming, and architecture. **Internalize these rules — they override any conflicting skill instructions.**
4. Check if TeamCreate is available

### 1b: Extract From Plan

Extract regardless of plan format:

| Extract | Look for |
|---------|----------|
| Files to create/modify | Implementation plan, changes required, file structure |
| Acceptance criteria | Requirements, AC section, behavioral requirements |
| Manual test cases | Verification plan, manual test section (MT-N) |
| Integration test plan | Verification plan, integration test section (IT-N) |
| Unit test plan | Verification plan, unit test section (UT-N) |
| External dependencies | APIs, databases, contracts, third-party services |
| Pattern files | **Codebase Context > Pattern References** |
| Current code flow | **Codebase Context > Current Code Flow** |
| DI registration | **Codebase Context > DI Registration** |
| Configuration | **Codebase Context > Configuration & Environment** |

If the plan has no files listed or no acceptance criteria, **STOP** and tell the user what's missing.

### 1c: Implementation Decomposition

**Most important step.** Don't list files — think about implementation order and how to prove each slice works.

For each piece of the plan, ask:

1. **What does this depend on?** Fewer dependencies → earlier.
2. **What's most unknown/risky?** Unknowns → earlier. Prove before building on them.
3. **Can I test this in isolation?** If not, it's too small or too coupled — merge with its dependency.
4. **How would a human verify this?** No manual test possible → not a meaningful slice yet.

Group into **implementation phases**. Each phase must be independently testable, built on proven ground, and meaningful to a human.

**Example — CRUD endpoint + UI:**
```
Phase 1: Database / external API — schema, migrations, repository
  Test: query DB directly, call external API, verify contracts
Phase 2: Service layer — business logic, validation, orchestration
  Test: call services programmatically, verify transformations
Phase 3: API endpoints — controllers, routes, request/response models
  Test: curl endpoints, verify status codes and response shapes
Phase 4: UI — components, pages, forms
  Test: open browser, navigate, fill forms, verify rendering
Phase 5: E2E — full flow top to bottom
```

### 1d: Identify Scaffold

Before phases begin, identify shared types all phases need:
- Types, models, DTOs, contracts, interfaces
- Constants, enums, configuration classes
- DI wiring / registration
- Database migrations or schema changes

These are dispatched as parallel solo agents and must compile before Phase 1.

### 1e: Log Decomposition and Execute

Log the decomposition summary to the output, then immediately begin dispatching. Do not ask for approval — the PRD is the approval.

```
Plan: {plan title}
Mode: {"Team-based" | "Solo agents"}

Scaffold ({N} tasks, parallel):
  [ ] {FileName} — {purpose}

Implementation Phases (sequential, outside-in):

  Phase 1: {Name} [{N} files]
    Implements: {what}
    Depends on: Scaffold
    Manual test: {how we'll prove it works}
    ACs: {list}

  Phase 2: {Name} [{N} files]
    ...

  Final: E2E Verification

Total: {N} scaffold + {M} phases + E2E.
```

Proceed to Phase 2 (Scaffold) immediately.

---

## Phase 2: Scaffold

Dispatch ALL scaffold tasks in a **single message** as solo Task agents.

```
Task: "Scaffold: {FileName}" | general-purpose
Prompt: |
  Create {exact path from plan}.
  Purpose: {from plan}
  Pattern file: {path to similar existing file}

  1. Read the pattern file. Match its conventions exactly.
  2. Read project CLAUDE.md / README.md for conventions.
  3. Create the file. Include ONLY what the plan defines.
  4. Build — must compile/pass linting.

  Return: {"file": "{path}", "compiles": true/false, "notes": "..."}
```

After all scaffold tasks: verify build. If fails, dispatch fix agent (max 1 retry). **Do not proceed until green.**

---

## Phase 3: Execute Implementation Phases

Execute each phase **sequentially**. Each must be proven working before the next begins.

### Shared Context Block

Use the **Agent Prompt Boilerplate** from `rpi-common.md` for every role prompt. Customize the phase-specific sections:
- **Phase assignment**: This phase's plan section (what to implement, which files, which ACs)
- **Previous phases proved**: Summary + file paths from earlier phases
- **Pattern file**: Path to similar existing component

### Team Mode (TeamCreate available)

Create team: `{feature}-phase-{N}-{phase-name}`.

**Step 1 — Developer implements:**
```
{SHARED CONTEXT}
Research context: {relevant sections from research.md}

1. Read pattern file completely.
2. Read code from previous phases.
3. Implement this phase following the pattern.
4. Build — fix until it compiles.

Return: files changed, what was implemented, build status.
```

**Step 2 — Tester manually verifies:**
```
{SHARED CONTEXT}
Files implemented: {Developer's output}
Manual test cases: {MT-N cases for this phase}

Test like a human. Do NOT write automated tests.
Use whatever tools are available: curl, browser automation, DB queries,
MCP tools, log inspection. MAKE the trigger happen, VERIFY the outcome.
If something is missing (Docker not running, creds not loaded, service
not started), FIX IT. Start Docker. Load the creds. Start the service.
Do not report "blocked" — solve the problem and run the test.
Record evidence for every AC.

Return: {"manual_tests": {"executed": [...], "problems_solved": [...]}, "bugs_found": [...]}
```

**Step 3** — Developer fixes bugs (if any), Tester re-verifies.

**Step 4 — Developer writes integration tests:**
```
{SHARED CONTEXT}
Integration test plan: {IT-N cases for this phase}
Test pattern: {path to similar existing integration test}

Follow Critical Rules for integration tests (real infra, production code paths, strong AC assertions).
Skip gracefully if infrastructure unavailable.
Run tests — all must pass.

Return: test files, tests written, tests passing, ACs covered.
```

**Step 5 — Developer writes unit tests:**
```
{SHARED CONTEXT}
Unit test plan: {UT-N cases for this phase}
Test pattern: {path to similar existing unit test}

Follow Critical Rules for unit tests (edge cases, boundary mocking only).
Run tests — all must pass.

Return: test files, tests written, tests passing.
```

**Step 6 — Tester validates assertions:**
```
Integration test files: {from Step 4}
Unit test files: {from Step 5}
Acceptance criteria: {ACs for this phase}

For EACH test: Would it FAIL if the feature broke? Does it assert SPECIFIC
AC outcomes? Are integration tests using real production code? Are unit tests
mocking only at the boundary? Flag weak assertions, missing coverage.

Return: weak assertions, missing tests, verdict (strong/adequate/weak).
```

**Step 7** — Developer strengthens if needed, Tester re-validates.

**Step 8 — Code Reviewer:**
```
{SHARED CONTEXT}
All files (implementation + tests): {lists}

Does every line trace to an AC? Follows pattern file? No magic strings,
unnecessary comments, dead code? Simplest way to satisfy ACs?
Tests well-structured?

Return: issues (blocking vs suggestions), verdict (approve/request-changes).
```

**Step 9** — Developer fixes if rejected, Reviewer re-reviews.

**Step 10 — PM validates:**
```
ACs for this phase: {list}
Manual test results: {from Step 2}
Automated test summary: {from Steps 4-5}
Assertion verdict: {from Step 6}

Every AC addressed? Edge cases covered? Anything built that WASN'T in the PRD?
Do test results actually prove the ACs?

Return: coverage status, gaps, scope concerns, sign-off (approve/reject).
```

TL reports phase result to orchestrator: what was built, tested, proven, any remaining issues and how they were resolved.

### Solo Mode (TeamCreate NOT available)

Dispatch a single Task agent per phase. It executes all 10 Team Mode steps sequentially (implement → manually test → integration tests → unit tests → self-review against ACs). Include the Shared Context Block plus all test plans (MT-N, IT-N, UT-N) in a single prompt. The agent returns the combined output from all steps.

### Between Phases

1. **Run full test suite** — all tests from all completed phases. Previous phases must not break.
2. **Compile proven ground summary** — what's been built, tested, proven. Becomes next phase's context.
3. **If phase fails after 2 retries** — report what's broken and proven. Human decides.
4. **Proceed only when current phase is signed off.**

---

## Phase 4: E2E Verification

After all phases complete:

### Pre-E2E: Ensure Infrastructure

Before E2E verification, ensure everything needed is running. If Docker
is required, build and start it. If services need to be up, start them.
If credentials need to be loaded, load them. Do not ask — do it.

### E2E Agent

```
Task: "E2E Verify: {feature}" | general-purpose
Prompt: |
  Final end-to-end verification.

  Plan: {plan file path}
  What was built (by phase): {summary per phase}

  BEFORE RUNNING TESTS: Ensure all infrastructure is running. If Docker
  is needed, build and start it. If services are down, start them. Do
  not report "blocked" — fix whatever is missing and proceed.

  1. BUILD — clean compile.
  2. RUN ALL TESTS — everything passes. Zero failures.
  3. E2E MANUAL TEST — full user journey start to finish.
     Walk through every AC as a real user would. Record evidence.
  4. AC COVERAGE AUDIT — for each AC:
     - Which phase implemented it?
     - Manual test evidence? (must be "passed" — "blocked" is not acceptable)
     - Integration test?
     - Unit test for edge cases?
     Flag any AC with NO coverage. Every AC must be proven.
  5. CHANGE REVIEW — any code that doesn't trace to a plan AC?
     Files modified outside the plan? Pattern divergence?

  Return: {
    "build": "pass/fail",
    "all_tests": {"total": N, "passed": N, "failed": N},
    "e2e_manual_test": {"result": "pass/fail", "evidence": "..."},
    "infrastructure_fixed": {"issues_solved": N, "how": "..."},
    "ac_coverage": {
      "met_all_3": ["ACs with manual + integration + unit"],
      "met_2": [...], "met_1": [...], "unmet": [...]
    },
    "ac_coverage_pct": N,
    "status": "VERIFIED | NEEDS_FIXES",
    "fixes_needed": [...]
  }
```

### AC Coverage Quality Gate

**100% AC coverage is required.** Every acceptance criterion must have at least one test (manual, integration, or unit). If `ac_coverage_pct` < 100%, the status is NEEDS_FIXES regardless of other results.

If NEEDS_FIXES: dispatch targeted fix agents, re-verify. Max 3 iterations.

---

## Phase 5: Report

```
/rpi-implement complete: {feature}

Mode: {"Team-based" | "Solo agents"}

Implementation Phases:
  Phase {N}: {name} — {status}
    Files: {list}
    ACs proved: {list}
    Manual tests: {passed}/{total}
    Integration tests: {N}
    Unit tests: {N}
    {"Team sign-offs: Dev / Tester / Reviewer / PM" if team mode}

E2E Verification: {VERIFIED | NEEDS_FIXES}
AC Coverage: {X}/{Y} (100% required) — {PASS | FAIL}

Testing Summary:
  Manual:      {N} executed, {P} passed
  Integration: {N} tests
  Unit:        {N} tests
  Failures:    0

All ACs implemented and verified. Ready for review.
```

---

## Failure Handling

| Situation | Action | Max Retries |
|-----------|--------|-------------|
| Plan not found | Error with path. STOP. | 0 |
| Build fails after scaffold | Fix agent with compiler output | 2 |
| Manual test fails | Developer fixes, Tester re-verifies | 2/phase |
| Manual test infrastructure missing | Fix it (start Docker, load creds, start service), then retest | 2/phase |
| Review/PM rejects | Developer fixes, re-review | 2/phase |
| Weak assertions | Developer strengthens, re-validate | 2/phase |
| Automated tests fail | Fix and re-run | 2/phase |
| Previous phase regresses | Fix before continuing | 2 |
| AC uncovered | Dispatch agent for missing test | 1/AC |
| Max retries exhausted | Try a different approach. If 2 different approaches fail, report status with what was tried. | — |
