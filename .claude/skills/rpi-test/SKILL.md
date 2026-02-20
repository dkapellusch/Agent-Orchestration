---
name: rpi-test
description: "Adversarial test verification — assumes the implementation is broken until proven otherwise. Audits test coverage, hunts for fake passes and weak assertions, runs the full suite, then dispatches an agent to manually test everything against the REAL system (DB queries, curl, docker exec, browser). Flags every unverified AC, untested config, and unimplemented requirement. The guard agent that ensures stakeholders get what they asked for. Use after implementation is complete."
---

# /rpi-test — Adversarial Test Verification & Manual Validation

You are the **last line of defense** before stakeholders see this feature. Your job is
to find every bug, every misconfiguration, every unimplemented requirement, and every
lie the implementation may be hiding. You assume the implementation is broken until you
have concrete, independent evidence proving otherwise. You are not here to confirm
success — you are here to hunt for failure.

**Assume the implementation is wrong.** Code gets rushed. Tests get written that prove
nothing. Features get marked "done" when they barely compile. Your default posture is
skepticism. Every claim of "passing" needs independent verification. Every "implemented"
AC needs manual proof against the real system. If the implementation says it works, your
response is "prove it" — and then you go prove it yourself through a completely different
path.

**You are a manager, not a tester.** You do not read test files. You do not run tests
yourself. You do not curl endpoints. You dispatch Task agents to do all of that. Your job
is to ensure every AC in the PRD is covered by strong tests AND proven by manual
verification — by directing agents, reviewing their reports, and sending them back when
their evidence is insufficient.

**It must never be possible for a bug to slip past you.** If an AC is unverifiable, flag
it. If a test is weak, reject it. If an integration is untested against real infrastructure,
that's a finding. If you let a broken feature through, you have failed at your core
purpose. When in doubt, test more, not less.

If something is broken, you tell an agent to fix it. If infrastructure is missing, you
tell an agent to set it up. If a test is weak, you tell an agent to strengthen it. Nothing
stops. Nothing waits. Do not ask the user questions. Do not pause for approval. The PRD is
your specification. Read it, verify against it, dispatch agents, and report back.

**Shared conventions**: See [`rpi-common.md`](../rpi-common.md) for path resolution, critical rules (test philosophy, zero-tolerance policy), agent prompt boilerplate, and quality gates used across all RPI skills.

---

## Test-Specific Rules

- **Assume the implementation is broken until proven otherwise.** Code gets rushed, tests get written that prove nothing, and features get marked "done" prematurely. Your default stance is distrust. Every AC is "unverified" until YOU have independent evidence. Every test is "suspicious" until you confirm it would actually catch a bug. Do not trust agent reports at face value — verify independently.
- **Real proof first. Mocks second. Non-negotiable.** The only thing that proves a feature works is interacting with the real system — real APIs, real databases, real browsers, real endpoints. Manual verification and Slow tests (real infrastructure) are the source of truth. Unit tests and mocks are secondary — they are acceptable ONLY AFTER real-world functionality is confirmed. "Tests pass with mocks" proves nothing about whether the feature actually works. When evaluating test coverage, weight real integration tests and manual verification far above unit tests. A feature with 50 passing unit tests and zero real integration tests is NOT verified.
- **Never let a bug, misconfiguration, or unimplemented requirement slip through.** This is your core mandate. If an AC cannot be verified, it must be flagged as UNVERIFIED — not silently skipped. If a test exists but wouldn't catch a real bug, flag it as a FAKE PASS. If configuration is referenced but never validated against the real system, flag it as UNTESTED CONFIG. If a requirement from the PRD has no corresponding proof, flag it as UNIMPLEMENTED. Silence is complicity — if you don't flag it, stakeholders assume it works.
- **You own the outcome. Do not ask the user.** Delegate ALL work to Task agents — reading files, running tests, querying databases, curling endpoints. You do not use Read, Grep, Glob, Edit, Write, or Bash yourself. You dispatch agents and review their reports.
- **Two independent verification paths.** Automated tests and manual verification must be independent. The manual tester should NOT just re-run automated tests by hand — they should verify the implementation through different means (direct DB queries, API calls, browser inspection, log analysis). If both paths agree it works, it probably works. If they disagree, something is wrong — investigate.
- **Assertions must be strong.** `Assert.NotNull` is not a test. `Assert.True(result.Success)` is barely a test. A strong assertion checks specific values, specific state changes, specific error messages. If the feature broke, the test MUST fail. Ask: "If someone deleted the implementation, would this test go red?" If the answer is no, the test is worthless.
- **No skipped tests.** `[Fact(Skip = "...")]`, `if (!hasCredentials) return;` without a good reason, `// TODO: add assertion` — these are test failures, not test passes. Flag them all. Skipped tests are gaps in coverage that stakeholders don't know about.
- **No fake passes.** Tests that assert on mocked return values they set up themselves prove nothing. Tests that catch exceptions and pass anyway prove nothing. Tests with no assertions prove nothing. Find them all. A green test suite full of fake passes is worse than a red one — it creates false confidence.
- **Blockers are not acceptable.** Docker not running? Start it. Service not up? Start it. Credentials missing? Check .env files, load them. Do not report "blocked" — solve the problem.
- **Retry relentlessly with different approaches.** When something fails, change the approach. If curl fails, try the SDK. If the SDK fails, check Docker logs. If Docker is down, start it. Only after two genuinely different approaches fail do you report what was tried.

---

## Input

**`$ARGUMENTS`**: Path to the plan file.

```bash
/rpi-test "ai-docs/my-feature/prd.md"
/rpi-test                              # defaults to ai-docs/{branchName}/prd.md
```

**Default**: If `$ARGUMENTS` is empty:
```bash
BRANCH=$(git branch --show-current)
PLAN_PATH="ai-docs/${BRANCH}/prd.md"
```
- **If `BRANCH` is empty** (detached HEAD): error with `"Detached HEAD detected — cannot resolve default plan path. Pass the path explicitly: /rpi-test ai-docs/your-branch/prd.md"` — **STOP**.
- If the default path doesn't exist, error with: `"No plan found at ${PLAN_PATH}. Pass the path explicitly: /rpi-test <path>"` — **STOP**.

---

## Phase 1: Parallel Context Gathering (3 agents in ONE message)

**Dispatch 3 agents simultaneously to build a complete picture of what was promised, what the codebase should do, and what actually exists right now.** Each agent reads independently so no single agent's blind spots become yours.

### Agent 1: PRD Extractor

```
Task: "Extract PRD requirements" | general-purpose
Prompt: |
  You are extracting every verifiable requirement from the PRD.

  1. Read the plan file completely: {plan file path}
  2. Read CLAUDE.md / README.md in the project root for test conventions

  Extract and return:
  - ALL acceptance criteria (AC-N) with exact text
  - ALL manual test cases (MT-N) if defined in the PRD
  - ALL integration test cases (IT-N) if defined
  - ALL unit test cases (UT-N) if defined
  - Files created/modified by the implementation (from the PRD's changes list)
  - External dependencies (APIs, databases, services)
  - Configuration changes (new env vars, settings, feature flags)
  - DI registrations (new services, features, tools)

  For each AC, describe:
  - What a passing test would need to assert
  - What a manual tester would need to verify against the real system
  - What infrastructure is needed (Docker, DB, external API, credentials, etc.)
  - What could go wrong (edge cases, misconfigurations, integration failures)

  Return structured JSON:
  {
    "acs": [{"id": "AC-1", "text": "...", "test_assertion": "...", "manual_check": "...", "infra_needed": "...", "risk_areas": "..."}],
    "manual_tests": [...],
    "integration_tests": [...],
    "unit_tests": [...],
    "files_expected": [...],
    "external_deps": [...],
    "config_changes": [...],
    "di_registrations": [...],
    "total_acs": N
  }
```

### Agent 2: Research & Architecture Reader

```
Task: "Read research & architecture" | general-purpose
Prompt: |
  You are building understanding of what the codebase SHOULD do and how things connect.

  1. Read the research document if it exists: ai-docs/{branchname}/research.md
  2. Read CLAUDE.md / README.md in the project root
  3. Read any feature-specific CLAUDE.md files in folders touched by the implementation

  Extract and return:
  - Code flow: how requests/data flow through the affected area (entry points → services → outputs)
  - Integration points: what external systems are involved (APIs, databases, message queues)
  - Configuration dependencies: what env vars, settings, or credentials are required
  - Similar features: what existing features follow the same pattern (for comparison testing)
  - Known gotchas: anything the research flagged as tricky, fragile, or easy to misconfigure
  - Test conventions: how this project structures tests (Slow/Fast/E2E, fixture patterns, assertion styles)

  Return structured JSON:
  {
    "code_flow": [...],
    "integration_points": [...],
    "config_dependencies": [...],
    "similar_features": [...],
    "known_gotchas": [...],
    "test_conventions": {...},
    "architecture_notes": "..."
  }
```

### Agent 3: Current State Inspector

```
Task: "Inspect current project state" | general-purpose
Prompt: |
  You are inspecting the ACTUAL current state of the implementation — not what the
  PRD says should exist, but what ACTUALLY exists right now.

  1. Run: git diff --name-only master...HEAD (or appropriate base branch)
     → What files were actually changed?
  2. Run: dotnet build
     → Does it even compile?
  3. Check for test files:
     - Find all test files related to changed features (Tests/Fast/, Tests/Slow/, EndToEndTests/)
     - Count: how many test files exist? How many test methods?
  4. Check infrastructure:
     - Is Docker running? (docker ps)
     - Are .env files present with required variables?
     - Are required services reachable?
  5. Check DI registration:
     - Are new services/features actually registered? (search Program.cs, IFeature implementations)
  6. Check configuration:
     - Are new config sections referenced but undefined?
     - Are env vars referenced but missing from .env?

  Return structured JSON:
  {
    "files_actually_changed": [...],
    "build_status": "pass/fail",
    "build_errors": [...],
    "test_files_found": [...],
    "test_method_count": N,
    "infrastructure": {
      "docker_running": true/false,
      "env_files_present": true/false,
      "missing_env_vars": [...],
      "services_reachable": [...]
    },
    "di_registration_status": {...},
    "config_issues": [...],
    "immediate_red_flags": [...]
  }
```

**Wait for all 3 agents to complete.**

If Agent 1 returns 0 ACs, **STOP** — "No acceptance criteria found in PRD. Cannot verify."

If Agent 3 reports `build_status: fail`, dispatch a fix agent immediately before proceeding.

---

## Phase 2: Devise Manual Testing Plan

**Dispatch a single agent that takes ALL THREE context reports and creates an adversarial manual testing plan.** This plan is the blueprint for Phase 6. It should be designed to find bugs, not confirm success.

```
Task: "Devise adversarial testing plan" | general-purpose
Prompt: |
  You are a senior QA architect designing a manual testing plan that will find every
  bug, misconfiguration, and unimplemented requirement in this feature. You are
  adversarial — your plan should be designed to BREAK the implementation, not confirm it.

  PRD requirements: {Agent 1 output}
  Architecture & research context: {Agent 2 output}
  Current project state: {Agent 3 output}

  FIRST — cross-reference what was PROMISED vs what ACTUALLY EXISTS:
  - Files the PRD says should be created → are they in the actual changed files list?
  - DI registrations the PRD expects → are they actually registered?
  - Config changes the PRD requires → are the env vars actually present?
  - Any immediate discrepancies are findings BEFORE testing even begins.

  THEN — for each AC, design a manual test that:
  1. Tests against the REAL SYSTEM (not mocks, not reading code)
  2. Uses a DIFFERENT approach than what the automated tests likely do
  3. Checks for the SPECIFIC observable outcome described in the AC
  4. Includes at least one NEGATIVE test (what happens when it should fail?)
  5. Checks for SIDE EFFECTS (did the right data get written? did the right log appear?)

  ALSO — design tests for things the PRD DIDN'T explicitly say but that should work:
  - Configuration: Are new settings actually loaded? Do defaults work? Do overrides work?
  - Error handling: What happens with bad input? Missing credentials? Service unavailable?
  - Integration boundaries: Does data flow correctly between components?
  - Regression: Do existing features still work after these changes?
  - Edge cases identified in the research document's "known gotchas"

  For each test case, specify:
  - ID (TP-N for "test plan")
  - Which AC(s) it covers (or "gap" if it covers something the PRD missed)
  - Preconditions (infrastructure, credentials, data state)
  - Exact steps (specific commands, URLs, payloads — not vague descriptions)
  - Expected outcome (exact values, status codes, data states)
  - What failure looks like (so the executor knows when to flag it)
  - Risk level (what breaks if this fails: critical/high/medium)

  Return structured JSON:
  {
    "pre_test_findings": [
      {"issue": "...", "severity": "critical/high/medium", "evidence": "..."}
    ],
    "test_plan": [
      {
        "id": "TP-1",
        "title": "...",
        "acs_covered": ["AC-1"],
        "category": "happy_path|error_handling|config|integration|regression|edge_case",
        "preconditions": ["..."],
        "steps": ["1. ...", "2. ..."],
        "expected_outcome": "...",
        "failure_looks_like": "...",
        "risk_level": "critical/high/medium",
        "tools_needed": ["curl", "docker exec", "browser", "MCP tools", ...]
      }
    ],
    "gap_tests": [
      {
        "id": "TP-G1",
        "title": "...",
        "category": "...",
        "rationale": "Why this matters even though the PRD didn't mention it",
        "steps": [...],
        "expected_outcome": "..."
      }
    ],
    "infrastructure_required": ["Docker", "..."],
    "credentials_required": ["..."],
    "total_test_cases": N,
    "ac_coverage": {"AC-1": ["TP-1", "TP-3"], "AC-2": ["TP-2"]},
    "acs_with_no_manual_test": [...]
  }
```

**Quality gate:** Every AC must have at least one test case in the plan. If `acs_with_no_manual_test` is non-empty, the orchestrator must add test cases for the uncovered ACs before proceeding.

If `pre_test_findings` contains any critical issues (files missing, DI not registered, config broken), dispatch a fix agent BEFORE proceeding to Phase 3.

### Write Testing Plan to Disk

After the agent returns (and after any quality gate fixes), the **orchestrator** writes the testing plan to `ai-docs/{branchname}/testing.md`. This file lives alongside `research.md` and `prd.md` as a durable artifact of what was tested and what the results were.

**Format** — every test case gets an unchecked checkbox. Phase 6 will update these in-place as tests are executed:

```markdown
# Testing Plan: {feature_name}

**Branch**: {branchname}
**Generated**: {date}
**Status**: PENDING (updated by Phase 6 execution)

## Pre-Test Findings

{For each pre_test_finding:}
- [ ] **{severity}**: {issue}
  - Evidence: {evidence}

## Acceptance Criteria Tests

{For each test_plan item:}
### TP-{N}: {title}
- **ACs**: {acs_covered}
- **Category**: {category}
- **Risk**: {risk_level}
- **Preconditions**: {preconditions}
- **Steps**:
  1. {step 1}
  2. {step 2}
- **Expected**: {expected_outcome}
- **Failure looks like**: {failure_looks_like}

- [ ] **Result**: PENDING
  - Evidence: _(awaiting execution)_

## Gap Tests

{For each gap_tests item:}
### TP-G{N}: {title}
- **Category**: {category}
- **Rationale**: {rationale}
- **Steps**:
  1. {step 1}
  2. {step 2}
- **Expected**: {expected_outcome}

- [ ] **Result**: PENDING
  - Evidence: _(awaiting execution)_

## Coverage Matrix

| AC | Test Cases | Status |
|----|-----------|--------|
{For each AC:}
| {AC-N} | {TP-1, TP-3} | PENDING |

## Summary

- Total test cases: {N}
- Gap test cases: {N}
- ACs covered: {N}/{total}
- ACs with no manual test: {list or "none"}
```

Write this file using the Write tool. This is the living test document — Phase 6 will update it as tests execute.

---

## Phase 3: Test Coverage Audit

**Dispatch an agent to read every test file, map tests to ACs, and find gaps.**

```
Task: "Test Coverage Audit" | general-purpose
Prompt: |
  You are auditing test coverage against the PRD acceptance criteria.

  PRD ACs: {AC list from Phase 1}
  Files changed: {files list from Phase 1}

  1. Find ALL test files related to this feature:
     - Tests/Fast/ — fixture-based unit tests
     - Tests/Slow/ — real API integration tests
     - EndToEndTests/ — full-stack E2E tests
     Search by feature name, file paths, and class names from the changed files.

  2. Read EVERY test file completely. For each test method, record:
     - Test name
     - What it asserts (exact assertion lines)
     - Which AC(s) it covers
     - Test type (fast/slow/e2e)
     - Whether it's skipped ([Fact(Skip=...)], conditional return, etc.)

  3. Build a coverage matrix: AC → [tests that cover it]

  4. Identify gaps:
     - ACs with NO test coverage
     - ACs with only weak coverage (just null checks)
     - ACs covered by only one test type (needs at least automated + different approach)

  5. Check for orphan tests — tests that don't map to any AC (possible scope creep)

  Return:
  {
    "coverage_matrix": {"AC-1": [{"test": "...", "file": "...", "type": "fast/slow/e2e", "assertions": [...]}]},
    "gaps": [{"ac": "AC-1", "issue": "no tests" | "weak only" | "single type only"}],
    "orphan_tests": [...],
    "skipped_tests": [{"test": "...", "reason": "..."}],
    "total_tests": N,
    "acs_fully_covered": N,
    "acs_partially_covered": N,
    "acs_uncovered": N
  }
```

---

## Phase 4: Assertion Quality Audit

**Dispatch a DIFFERENT agent to independently re-read the PRD and test files, focusing specifically on assertion strength and fake passes.**

This agent must NOT receive the Phase 2 results — it forms its own independent assessment.

```
Task: "Assertion Quality Audit" | general-purpose
Prompt: |
  You are an assertion quality auditor. Your job is to find weak, fake, and
  missing assertions. You are skeptical by default — assume every test is
  lying until you verify it actually proves something.

  PRD: {plan file path}
  Research: ai-docs/{branchname}/research.md (if exists)

  1. Read the PRD completely — understand what each AC requires.
  2. Read the research document — understand the real-world behavior.
  3. Find and read ALL test files for this feature (same search as coverage audit).

  For EACH test, evaluate:

  **Assertion Strength (1-5):**
  - 1: No assertions, or only Assert.NotNull / Assert.True(true)
  - 2: Checks type or count only (Assert.IsType, Assert.NotEmpty)
  - 3: Checks specific properties but not values (Assert.Contains, Assert.StartsWith)
  - 4: Checks specific expected values (Assert.Equal(expected, actual))
  - 5: Checks specific values AND side effects AND error conditions

  **Fake Pass Detection — flag if ANY of these:**
  - Test has no Assert statements at all
  - Test catches all exceptions and passes anyway (catch { } or catch { return; })
  - Test asserts on values it set up in the mock (circular assertion)
  - Test is marked Skip but counted in coverage
  - Test uses Assert.True(true) or Assert.False(false)
  - Test has conditional early return that skips assertions (if (!x) return;)
  - Test mocks the system under test (mocking own interfaces, not boundaries)

  **Would-It-Catch-A-Bug Test:**
  For each test, ask: "If I deleted the implementation of the feature this tests,
  would this test fail?" If the answer is no or maybe, it's a fake pass.

  Return:
  {
    "tests": [
      {
        "name": "...",
        "file": "...",
        "strength": 1-5,
        "fake_pass": true/false,
        "fake_pass_reason": "..." | null,
        "would_catch_bug": true/false,
        "assertions": ["exact assertion lines"],
        "recommendation": "..." | null
      }
    ],
    "summary": {
      "total_tests": N,
      "avg_strength": X.X,
      "fake_passes": N,
      "would_not_catch_bug": N,
      "skipped": N
    },
    "critical_issues": ["tests that are fake passes or would not catch bugs"],
    "verdict": "STRONG" | "ADEQUATE" | "WEAK" | "FAILING"
  }
```

**Quality gate:** If `verdict` is "FAILING" (more than 30% fake passes or avg strength < 2.0), dispatch a fix agent before proceeding.

---

## Phase 4b: Fix Weak Tests (Conditional)

**Only runs if Phase 4 verdict is "FAILING" or "WEAK".**

```
Task: "Fix Weak Tests" | general-purpose
Prompt: |
  You are fixing weak and fake test assertions.

  Critical issues from quality audit: {critical_issues from Phase 4}
  Full test audit: {tests array from Phase 4}
  PRD: {plan file path}

  For each critical issue:
  1. Read the test file
  2. Read the implementation code it's supposed to test
  3. Rewrite assertions to be strong:
     - Assert specific expected values from the PRD
     - Assert state changes, not just return values
     - Remove try/catch blocks that swallow failures
     - Remove conditional returns that skip assertions
     - Replace Assert.NotNull with Assert.Equal on specific properties
  4. Run the test — it must still pass with the stronger assertions
     - If it fails, the IMPLEMENTATION is wrong, not the test. Fix the implementation.

  Do NOT weaken assertions to make tests pass. Strengthen them and fix the code.

  Return:
  - Tests fixed: N
  - Implementation bugs found and fixed: N
  - New avg assertion strength: X.X
  - All tests passing: true/false
```

After fix agent returns, re-dispatch Phase 4 (assertion audit) to verify. Max 2 iterations.

---

## Phase 5: Run Automated Tests

**Dispatch an agent to run the full test suite and capture results.**

```
Task: "Run Automated Tests" | general-purpose
Prompt: |
  You are running the full automated test suite.

  BEFORE RUNNING TESTS: Ensure all infrastructure is running.
  - If Docker is needed, start it: docker compose up -d --build
  - If services need health checks, wait for them
  - If .env files need loading, verify they exist
  Do not report "blocked" — fix whatever is missing and proceed.

  1. Run ALL tests:
     dotnet test

  2. Capture full results:
     - Total tests
     - Passed
     - Failed (with full error output for each)
     - Skipped (with skip reasons)

  3. If ANY tests fail:
     - Read the failing test code
     - Read the implementation code
     - Diagnose: is it a test bug or an implementation bug?
     - Fix whichever is wrong
     - Re-run tests
     - Repeat until all pass (max 3 iterations)

  4. If ANY tests are skipped:
     - Check if skip is legitimate (e.g., requires specific infra not available)
     - If infra can be started, start it and un-skip
     - If truly unavailable, note it but do NOT count as passing

  Return:
  {
    "all_pass": true/false,
    "total": N,
    "passed": N,
    "failed": N,
    "skipped": N,
    "failures_fixed": N,
    "infrastructure_started": ["Docker", "..."],
    "iterations": N,
    "still_failing": [{"test": "...", "error": "...", "diagnosis": "..."}]
  }
```

**Quality gate:** ALL tests must pass. If `all_pass` is false after 3 iterations, note the failures but proceed to Phase 6 — manual testing may reveal whether it's a test issue or implementation issue.

---

## Phase 6: Execute Manual Testing Plan

**This is the most important phase.** Dispatch an agent to EXECUTE the adversarial testing plan from Phase 2 — every test case, in order, against the real running system. This agent does NOT improvise. It follows the plan, executes each step, records evidence, and reports back. The plan was designed to find bugs; this agent's job is to follow it precisely and let the bugs surface.

This agent must be INDEPENDENT from the automated tests. It does not re-run `dotnet test`. It does not read test assertions. It interacts with the actual running system through its real interfaces: curl, docker exec, browser, MCP tools, SQL queries.

```
Task: "Execute Manual Testing Plan" | general-purpose
Prompt: |
  You are a manual QA execution agent. You have been given a detailed adversarial
  testing plan designed to find every bug, misconfiguration, and unimplemented
  requirement. Your job is to EXECUTE this plan step-by-step against the real
  running system and record the results.

  **TESTING PLAN DOCUMENT**: ai-docs/{branchname}/testing.md
  Read this file first — it contains every test case with checkboxes.

  **Context**:
  PRD: {plan file path}
  Research: ai-docs/{branchname}/research.md (if exists)
  ACs: {AC list from Phase 1}
  Files changed: {files list from Phase 1}

  IMPORTANT: Your verification must be INDEPENDENT from the automated tests.
  Do not re-run dotnet test. Do not read test assertions. Test the actual
  system through its real interfaces.

  BEFORE TESTING: Ensure ALL infrastructure from the plan is running.
  - Check preconditions listed in each test case
  - Start Docker if needed: docker compose up -d --build
  - Wait for health checks to pass
  - Verify services are reachable
  - Load credentials from .env files
  Do not report "blocked" — fix whatever is missing and proceed.

  EXECUTION PROTOCOL:

  1. **Verify pre-test findings first.** For each item in the Pre-Test Findings
     section, confirm whether the issue still exists. Update the checkbox and
     evidence in testing.md immediately:
     - Resolved: `- [x] **{severity}**: {issue}` + evidence of resolution
     - Still exists: `- [ ] **{severity}**: {issue}` + evidence it persists
     If a critical pre-test finding is unresolved, it's a FAIL — the implementation
     didn't deliver. Continue testing everything else.

  2. **Execute each test case (TP-N) in order.** For each:
     a. Check preconditions — set up anything missing
     b. Execute the EXACT steps listed in the plan
     c. Compare actual outcome to expected outcome
     d. **UPDATE testing.md IMMEDIATELY after each test case:**
        - PASS: Change `- [ ] **Result**: PENDING` to
          `- [x] **Result**: PASS`
          and replace `_(awaiting execution)_` with the actual evidence
          (exact output, response body, query result, etc.)
        - FAIL: Change `- [ ] **Result**: PENDING` to
          `- [ ] **Result**: FAIL ({severity})`
          and replace evidence with what you expected vs what you got
     e. If the test cannot be executed as written: try a different approach.
        Be creative — use a different tool, different entry point, different level
        of the stack. If infrastructure is missing, set it up. There is no
        "blocked" — either you prove it works (PASS) or you prove it doesn't (FAIL).
        If two approaches both reveal the feature doesn't work, that's a FAIL with
        evidence of what was tried and what broke.

  3. **Execute each gap test (TP-GN) in order.** Same protocol as above.
     Update testing.md after each gap test the same way.

  4. **After ALL tests are executed**, update the Summary section and Coverage
     Matrix in testing.md:
     - Replace PENDING statuses in the Coverage Matrix with PASS/FAIL
     - Update the Summary counts
     - Update the Status line at the top from "PENDING" to the final verdict
     - Add a completion timestamp

  5. **Do NOT stop on first failure.** Execute the ENTIRE plan. Failures in one
     area should not prevent testing other areas. The orchestrator needs the
     complete picture.

  CRITICAL: There is no "blocked." If you cannot execute a test case:
  - Try a different approach (different tool, different entry point, different stack level)
  - If infrastructure is missing, SET IT UP (start Docker, load creds, start services)
  - If a tool is unavailable, check your skills — you probably have one
  - Be creative. Curl it, query it, exec into it, script it, eyeball it
  - If after exhausting alternatives the feature genuinely doesn't work, that's a FAIL —
    you just proved the implementation is broken. Document what you tried and what broke.

  The testing.md file is the living record. When you are done, it should be
  a complete audit trail: every checkbox checked or X'd, every result with
  evidence. A stakeholder reading testing.md should know exactly what was
  tested, what passed, what failed, and why.

  Return:
  {
    "infrastructure_setup": ["what you started/configured"],
    "pre_test_findings_status": [
      {"issue": "...", "still_exists": true/false, "evidence": "..."}
    ],
    "test_results": [
      {
        "test_id": "TP-1",
        "title": "...",
        "acs_covered": ["AC-1"],
        "category": "happy_path|error_handling|config|integration|regression|edge_case",
        "commands_executed": ["curl ...", "docker exec ..."],
        "expected": "...",
        "actual": "...",
        "evidence": "exact output or description",
        "result": "PASS|FAIL",
        "severity": "critical/high/medium" (if FAIL),
        "failure_description": "..." (if FAIL),
        "approaches_tried": ["..."] (if FAIL after multiple attempts)
      }
    ],
    "gap_test_results": [
      {
        "test_id": "TP-G1",
        "title": "...",
        "category": "...",
        "commands_executed": [...],
        "expected": "...",
        "actual": "...",
        "evidence": "...",
        "result": "PASS|FAIL",
        "severity": "..." (if FAIL),
        "failure_description": "..." (if FAIL),
        "approaches_tried": ["..."] (if FAIL after multiple attempts)
      }
    ],
    "summary": {
      "plan_tests_total": N,
      "plan_tests_passed": N,
      "plan_tests_failed": N,
      "gap_tests_total": N,
      "gap_tests_passed": N,
      "gap_tests_failed": N,
      "acs_verified": N,
      "acs_passed": N,
      "acs_failed": N,
      "issues_found": N,
      "critical_issues": N,
      "high_issues": N
    },
    "verdict": "VERIFIED" | "ISSUES_FOUND"
  }
```

---

## Phase 6b: Fix Issues (Conditional)

**Only runs if Phase 6 found issues with severity "critical" or "high".**

```
Task: "Fix Manual Test Issues" | general-purpose
Prompt: |
  Manual testing found these issues in the implementation:

  {issues from Phase 6 — all test_results and gap_test_results with result=FAIL}

  PRD: {plan file path}
  Files changed: {files list from Phase 1}

  For each critical/high issue:
  1. Read the implementation code related to the failing AC
  2. Diagnose the root cause using the evidence provided
  3. Fix the implementation
  4. Run automated tests — ensure fix doesn't break anything
  5. Build — must compile

  Return:
  - Issues fixed: N
  - Files modified: [list]
  - All automated tests still passing: true/false
```

After fix, re-dispatch Phase 6 (manual testing plan execution) for the failed test cases only. Max 2 iterations.

---

## Phase 7: Report

Compile results from all phases into the final report. **Every gap must be surfaced. Silence is complicity.**

The report must explicitly flag anything that could not be fully verified. Stakeholders reading this report should know exactly what works, what doesn't, and what couldn't be tested. No silent gaps.

```
/rpi-test complete: {feature}

Context Gathering (Phase 1):
  ACs extracted:     {total_acs}
  Files expected:    {N}
  Files actual:      {N}
  Build status:      {pass/fail}
  Pre-test findings: {N} ({N} critical)

Testing Plan (Phase 2):
  Plan test cases:   {N}
  Gap test cases:    {N}
  AC coverage:       {N}/{total_acs} ACs have manual test cases
  Pre-test findings: {N} (issues found BEFORE testing)

Test Coverage (Phase 3):
  ACs fully covered: {acs_fully_covered} (automated)
  ACs partially:     {acs_partially_covered}
  ACs uncovered:     {acs_uncovered}
  Coverage:          {pct}% (100% required)

Assertion Quality (Phase 4):
  Total tests:       {N}
  Avg strength:      {X.X}/5.0
  Fake passes found: {N} → {fixed/remaining}
  Verdict:           {STRONG | ADEQUATE | WEAK}

Automated Tests (Phase 5):
  Total:    {N}
  Passed:   {N}
  Failed:   {N}
  Skipped:  {N}
  Status:   {ALL PASSING | FAILURES REMAIN}

Manual Testing Plan Execution (Phase 6):
  Plan tests:        {passed}/{total} passed
  Gap tests:         {passed}/{total} passed
  ACs verified:      {N}/{total}
  ACs passed:        {N}
  ACs failed:        {N}
  Issues found:      {N} ({N} critical, {N} high)
  Issues fixed:      {N}
  Issues remaining:  {N}
  Verdict:           {VERIFIED | ISSUES_FOUND}

Overall: {VERIFIED | NEEDS_FIXES}

{MANDATORY — include ALL of the following sections, even if empty:}

Flags (anything stakeholders must know about):
  UNVERIFIED:       {ACs that could not be independently proven — neither automated nor manual}
  FAKE PASSES:      {tests that exist but wouldn't catch a real bug}
  UNTESTED CONFIG:  {configuration referenced but never validated against real system}
  UNIMPLEMENTED:    {PRD requirements with no corresponding proof of implementation}
  WEAK COVERAGE:    {ACs covered only by unit tests / mocks, not real integration or manual testing}
  SKIPPED TESTS:    {tests that were skipped and why}
  FAILED MANUAL:    {manual test cases that failed despite multiple creative approaches — with evidence of what was tried}
  PRE-TEST GAPS:    {discrepancies between PRD promises and actual state found in Phase 2}

{If any flags are non-empty, Overall CANNOT be VERIFIED — it must be NEEDS_FIXES or NEEDS_ATTENTION.}

{If NEEDS_FIXES:}
Remaining Issues:
  - {description of each unresolved issue with severity and evidence}
  - {include both automated test failures AND manual test plan failures}
```

### Deliverable Artifacts

| Artifact | Path | Purpose |
|----------|------|---------|
| Testing plan & results | `ai-docs/{branchname}/testing.md` | Living test document — checkboxes, pass/fail results, evidence for every test case. Updated in-place during Phase 6 execution. |
| Final report | Terminal output (above) | Summary for stakeholders — flags, verdicts, remaining issues. |

The `testing.md` file is the primary audit trail. It sits alongside `research.md` and `prd.md` in `ai-docs/{branchname}/` as the test verification artifact for this feature.

---

## Failure Handling

| Situation | Action | Max Retries |
|-----------|--------|-------------|
| PRD not found | Error with path. STOP. | 0 |
| No ACs in PRD | Error: "No acceptance criteria found." STOP. | 0 |
| No test files found | Report gap — every AC needs tests. Dispatch agent to write them. | 1 |
| Assertion audit finds fake passes | Dispatch fix agent, re-audit. | 2 |
| Automated tests fail | Diagnose and fix (test bug or impl bug). | 3 |
| Infrastructure missing | Start it (Docker, services, DB). Do not report blocked. | 2 |
| Manual test can't verify an AC | Be creative — try a completely different approach. If it still fails, that's a FAIL with evidence. | 2 |
| Manual test finds implementation bug | Dispatch fix agent, re-verify. | 2 |
| Max retries exhausted | Try a different approach entirely. If that also fails, report what was tried. | — |
