---
name: rpi-plan
description: Generate a consensus-driven spec from research — elicits behavioral requirements, dispatches 3 solution agents (minimal, proven, Style-Matching), synthesizes via agent review, and produces a verified implementation plan with manual/integration/unit test strategies. Use when someone says "plan", "design", "spec", or "how should we implement".
---

# /rpi-plan — Consensus-Driven Implementation Spec

You are an **agent orchestrator**. Your job is to fully understand the research document and feature scope, then prompt subagents to produce a complete implementation specification. You don't write the spec content yourself — you decompose the work, dispatch agents, and assemble their outputs into `{output_file}`.

**Shared conventions**: See [`rpi-common.md`](../rpi-common.md) for path resolution, critical rules, walkthrough protocol, and synthesis patterns used across all RPI skills.

---

## Input

**`$ARGUMENTS`**: A feature description, requirement, or change request. If empty: error with usage example. **STOP.**

### Flags

| Flag | Purpose | Default |
|------|---------|---------|
| `--research <path>` | Explicit path to the research document | `ai-docs/{branchname}/research.md` |
| `--output <path>` | Output directory for the spec | `ai-docs/{branchname}/` |

### Path Resolution

Use the **Path Resolution Pattern** from `rpi-common.md`:
- `{research_path}` = `--research` value, or `ai-docs/{branchname}/research.md`
- `{output_dir}` = `--output` value, or `ai-docs/{branchname}/`
- `{output_file}` = `{output_dir}/spec.md`
- Detached HEAD: error and STOP if no explicit paths provided

All subsequent phases use `{output_dir}` and `{output_file}` — never hardcoded paths.

---

## Phase 1: Load Research & Validate

1. Resolve paths using the [Path Resolution](#path-resolution) rules above.

2. **Read user-mentioned files** — if `$ARGUMENTS` references specific files, tickets, or docs, read them directly in main context now. This gives you concrete context for writing better agent prompts and more precise requirements.

3. Locate the research document at `{research_path}`:
   - If found → proceed to step 4
   - If not found → warn: "No research document found at `{research_path}`. Proceeding without research context — solution quality may be reduced." Skip to step 6.

4. If research exists, dispatch one agent to extract structured context from it:

   ```
   Task: "Load research" | subagent_type: Explore | model: haiku
   Prompt:
   Read the file at {research_path}. Extract and return the following sections VERBATIM
   from the research document. Copy tables and structured data exactly — do not summarize
   into prose. If a section doesn't exist in the document, write "Not documented."

   ## Research Summary
   2-3 sentences: what area of the codebase does this cover and what was investigated.

   ## Key Files
   Copy the key files table from the research doc (file path, purpose, responsibilities).

   ## Code Flow
   Copy the code flow / execution path section (numbered steps with file:line references).

   ## Entry/Exit Points
   Copy the entry points and exit points table (callers, endpoints, consumers).

   ## Configuration & Environment
   Copy the configuration and environment variables table (variable name, purpose, where defined).

   ## Similar Features / Pattern References
   Copy the similar features or pattern references table (feature name, file paths, what to mirror).

   ## Integration Points
   Copy upstream callers and downstream dependencies (services, APIs, databases).

   ## Credentials & Auth
   Copy credentials and authentication requirements (what's needed, where stored, how consumed).

   Return ONLY facts from the document. No opinions. No suggestions. Preserve original formatting.
   ```

5. **Validate key files** — dispatch a locator agent to verify the research document's key files still exist and haven't moved since research was written. Files may have been modified between research and planning.

   ```
   Task: "Validate research file map" | subagent_type: essentials:codebase-locator | model: haiku
   Prompt:
   The research document references these key files:
   {list of file paths from the research extraction agent's Key Files section}

   For each file:
   1. Verify it still exists at the listed path
   2. If it doesn't exist, search for where it may have moved (same filename, different directory)
   3. Note any files that have been deleted entirely

   Return a validated file map:
   - Confirmed files (still exist at listed path)
   - Moved files (old path → new path)
   - Missing files (deleted or not found)
   ```

   Assemble the locator's output into a `{validated_file_map}` — the same format as the research file map, but with corrections applied. Include this in the shared context block for Phase 3 agents.

6. Create output folder if it doesn't exist (ensure `{output_dir}` is created).

**Do not proceed to solutions. Requirements come first.**

---

## Phase 2: Behavioral Requirements

**Goal:** Define exactly what observable behaviors the system should exhibit when the feature is working.

### Step 1: Draft requirements from the prompt

Parse `$ARGUMENTS` and the research summary into concrete observable behaviors.

Think about:
- What does the user/caller see or receive?
- What data changes occur?
- What side effects happen (logs, events, cache updates)?
- What are the boundary conditions and error cases?
- What performance/timing characteristics matter?

Frame every requirement as: **"When [trigger], then [observable outcome]"**

Examples:
- "When a GET request hits `/api/exports/csv`, then the response has Content-Type `text/csv` and contains all matching records"
- "When the Slack API returns 429, then the service waits for the `Retry-After` duration and retries"
- "When the cache TTL expires, then the next request fetches fresh data from the upstream API"
- "When the user visits `/settings`, then they see the current configuration values pre-populated"
- "When validation fails on field X, then the response includes error code Y with a message describing the constraint"

### Step 2: Elicitation (only if genuinely needed)

**Skip straight to Step 3** if ALL of the following are true:
- Research documents config files and entry points for the affected area
- The prompt includes explicit acceptance criteria or concrete behavioral outcomes
- No architectural decisions are needed (e.g., no new patterns, no choice of library, no new infrastructure)

**If any of those conditions are NOT met**, ask the user targeted questions about:
- Behaviors that could legitimately go multiple ways
- Edge cases that affect the implementation approach
- Performance or scale expectations that constrain design
- Integration contracts that aren't documented in the research

Use `AskUserQuestion` for structured choices when the ambiguity is between concrete options. Use plain text for open-ended clarifications.

### Step 3: Confirm requirements with user

Present the requirements table:

```markdown
## Behavioral Requirements

| # | Trigger | Expected Outcome | Priority |
|---|---------|-------------------|----------|
| R1 | When X happens | Then Y should occur | Must |
| R2 | When A is requested | Then B is returned with properties C, D | Must |
| R3 | When error Z occurs | Then the system responds with W | Should |
| R4 | When edge case Q | Then graceful behavior P | Could |
```

Ask: **"Do these requirements capture what you want? Anything missing, wrong, or overly broad?"**

Incorporate feedback. Repeat until the user confirms.

Once confirmed, write the initial `{output_file}` with the requirements table as the anchor. Everything else builds on this.

---

## Phase 3: Three Solution Agents

**Dispatch 3 agents in a single message.** Each receives the same research summary and confirmed requirements but applies a different strategy.

### Shared Context (included in all 3 prompts)

```
## Research Context
{research_context}

## Validated File Map
{validated_file_map from Phase 1 step 5 — confirmed paths, moved files, missing files}
Start from these known files. Do not search blindly — expand outward from here.

## Confirmed Requirements
{requirements_table_from_phase_2}

## Codebase Conventions
{relevant sections from CLAUDE.md and README.md — testing patterns, naming conventions, DI registration, folder structure}
```

### Agent 1: Minimal Solution

```
Task: "Minimal solution" | subagent_type: general-purpose
Prompt:
You are the MINIMAL solution architect. Satisfy every confirmed requirement while changing the absolute fewest lines of code.

{shared_context}

Rules:
- Reuse existing infrastructure wherever possible
- Prefer modifying existing files over creating new ones
- Avoid new abstractions, patterns, or dependencies unless a requirement forces it
- If an existing utility or service already does 80% of what's needed, extend it

For each requirement, specify:
- Which existing file(s) to modify (with paths and line ranges where possible)
- What the change looks like (concrete description, not vague)
- Why this is the minimal path

Return:
1. Ordered file change list with estimated lines changed per file
2. Total files touched / total estimated lines changed
3. Any requirements that CANNOT be satisfied minimally (with explanation)
4. Risks or tradeoffs of the minimal approach
5. Codebase context discovered: for each file you read, include path + what you learned; for key method signatures include file:line
```

### Agent 2: Proven Solution

```
Task: "Proven solution" | subagent_type: general-purpose
Prompt:
You are the PROVEN solution researcher. Find how other projects, official documentation, and established patterns recommend solving this, then propose a battle-tested approach.

{shared_context}

Research process:
1. Search the web for how this kind of feature is typically implemented in the relevant framework/language
2. Find official documentation for any libraries, APIs, or SDKs involved
3. Look for open-source implementations, blog posts, or Stack Overflow answers showing proven patterns
4. Use any available MCP tools to find external documentation or contracts
5. Check if the codebase already uses libraries that have built-in support for this

For each requirement, specify:
- The proven approach (with source URLs or references)
- How it maps to our codebase structure
- Any new dependencies it would require

Return:
1. Recommended approach with references/sources for each recommendation
2. File change list
3. New dependencies (if any) with justification
4. Risks or gotchas discovered from real-world implementations
5. Anything the official docs specifically warn against
6. External references: URLs/docs consulted, library versions confirmed
```

### Agent 3: Style-Matching Solution

```
Task: "Style-Matching solution" | subagent_type: general-purpose
Prompt:
You are the Style-MATCHING solution architect. Propose a solution that follows every convention and pattern in this codebase so precisely that a reviewer couldn't distinguish it from the original team's work.

{shared_context}

Investigation:
1. Read the similar features identified in the research document
2. Study their folder structure, file naming, class naming, DI registration
3. Study their testing patterns (Slow tests, Fast tests, fixtures, test helpers)
4. Study their error handling, logging, and configuration patterns
5. Study how they expose functionality (controllers, MCP tools, endpoints)

For each requirement, specify:
- Files to create or modify (following exact naming conventions)
- Which existing feature each structural decision mirrors (with file paths)
- The test files and structure following the project's exact test patterns

Return:
1. Complete file list with naming justification (citing the pattern source)
2. DI registration approach (citing the pattern source)
3. Test plan following the project's Slow → fixture capture → Fast workflow
4. Pattern references: for every decision, name the existing feature it mirrors
5. Pattern reference sheet:
   | Decision | Pattern Source File | Lines | What to Copy |
   |----------|-------------------|-------|--------------|
   | DI registration | `XFeature.cs` | L10-25 | ConfigureServices method |
   | Tool definition | `XTool.cs` | L1-50 | Full tool class |
   | Test fixture | `XTestFixture.cs` | L1-30 | Fixture class pattern |
   (Fill in with REAL file paths and line ranges from this codebase)
```

**Wait for all 3 Wave 1 agents to complete.**

### Wave 2: Targeted Follow-Ups (conditional)

After all 3 agents return, the orchestrator reviews their proposals. Dispatch follow-up agents **only if** any of these conditions are true:

1. **Uncertain requirements**: An agent flagged a requirement as "uncertain how to satisfy" or "needs more codebase investigation"
2. **File disagreement**: The Minimal and Style-Matching agents disagree on which existing files to modify for the same requirement
3. **Fundamental approach divergence**: All 3 agents proposed fundamentally different approaches for a requirement (not just different files — different strategies)

**If none of these conditions are met, skip Wave 2 and proceed to Phase 4.**

For each issue, dispatch a targeted haiku agent to read the specific contested files and return concrete evidence:

```
Task: "Clarify: {specific_ambiguity}" | subagent_type: essentials:codebase-analyzer | model: haiku
Prompt: |
  The solution agents disagree on: {description_of_disagreement}

  Agent A proposed: {approach_A}
  Agent B proposed: {approach_B}

  Read these specific files to resolve the ambiguity:
  {list of contested file paths}

  Return:
  - Method signatures found at the contested locations
  - Existing patterns that favor one approach over the other
  - Test structure that constrains the implementation choice
  - A concrete recommendation with file:line evidence
```

The synthesis agent (Phase 4) receives Wave 1 outputs + any Wave 2 clarifications. Wave 2 findings are included in the synthesis prompt as an additional `## Follow-Up Clarifications` section.

---

## Phase 4: Review & Synthesis

Dispatch a review agent to compare all 3 proposals (and any Wave 2 clarifications) against the requirements and produce a single synthesized plan.

```
Task: "Synthesis review" | subagent_type: general-purpose
Prompt:
You have 3 implementation proposals for the same requirements. Compare them and produce one synthesized implementation plan that takes the best elements of each.

## Requirements
{requirements_table}

## Proposal 1: Minimal
{agent_1_output}

## Proposal 2: Proven
{agent_2_output}

## Proposal 3: Style-Matching
{agent_3_output}

{if Wave 2 follow-ups were dispatched:}
## Follow-Up Clarifications
{wave_2_agent_outputs — concrete evidence resolving ambiguities between proposals}
{end if}

For each requirement:
1. Compare how all 3 proposals satisfy it
2. Pick the best approach (or combine elements from multiple)
3. Briefly justify the choice (1 sentence)

Produce:

### Codebase Context
Compile from the Research Context and all 3 proposals into a section the implementing agent needs to avoid re-exploring the codebase. Filter rule: "Would the implementing agent need this to avoid re-exploring the codebase?"

1. **Current State** — 2-3 sentences on what exists today in the affected area
2. **Key Files** table — existing files the implementer must read, with relevance to this feature:
   | File | Purpose | Relevance to This Feature |
   |------|---------|--------------------------|
3. **Current Code Flow** — numbered steps with file:line refs through the affected area
4. **Pattern References** table — for each new file to create, the existing file to mirror:
   | New File | Pattern Source | What to Mirror |
   |----------|---------------|----------------|
5. **DI Registration Pattern** — concrete code example citing the pattern source file:line
6. **Configuration & Environment** table:
   | Variable | Purpose | Where Defined | Where Consumed |
   |----------|---------|---------------|----------------|

### Test Matrix
Consolidated table of ALL test cases (manual, integration, unit) — one row per test, placed immediately after the Requirements table in the spec. Every requirement must map to at least one test. Columns: ID, Req, Type (Manual/Slow/Fast), Description, Status (⬜).

### Implementation Plan
Ordered list of changes. For each:
- File path and action (create/modify)
- What changes and why
- Which proposal(s) this draws from
- Dependencies on other changes

### Verification Plan

**Real proof first. Mocks second. Non-negotiable.**

The verification plan must prove the feature works against the real system before any mocks or fixtures enter the picture. A plan that only describes unit tests is not a verification plan. Manual tests and integration tests against real infrastructure are the primary evidence. Unit tests are supplementary.

For EACH requirement, provide all three test levels:

#### Manual Test Cases (Priority 1 — AI-Agent Executable, REAL SYSTEMS)
These will be run by an AI agent against the actual running system — real APIs, real databases, real browsers, real endpoints. Each test case must be:
- Concrete and step-by-step (no "verify it works")
- Executable with tools available to an AI agent
- Targeting the real system, not mocks or stubs
- Clear about preconditions, inputs, and expected outputs

For each:
- ID (MT-N)
- Requirement it verifies
- Preconditions (services running, data seeded, credentials needed)
- Steps (exact actions)
- Expected result (exact observable outcome)
- **Access requirements**: credentials, running services, browser, MCP tools, special permissions. Flag ANYTHING the agent might not have.

#### Integration Tests (Priority 2 — REAL INFRASTRUCTURE)
Following the project's testing conventions from CLAUDE.md/README. These tests call real APIs and real databases — they are the automated source of truth:
- Test file location (following project structure)
- What to test (real API calls, real service interactions, real database queries)
- Fixture capture strategy (what responses to save from Slow tests for later Fast test use)
- These must pass BEFORE any unit tests are written

#### Unit Tests (Priority 3 — ONLY AFTER REAL TESTS PASS)
Following the project's testing conventions. Unit tests are acceptable ONLY after integration tests prove the feature works against real infrastructure. They cover edge cases that are impractical to test with real systems:
- Test file location
- What to test in isolation (edge cases, validation, error handling)
- Mock strategy (mock at the boundary — HttpClient, SDK — never mock own interfaces)
- Fixtures must be captured from real Slow test runs, never hand-written
- Key assertions

### Tradeoff Summary
One paragraph: what we gained and what we gave up in the synthesis.
```

---

## Phase 5: Write spec

**Write the complete spec to `{output_file}` NOW — before any user review.** The file must exist on disk before proceeding to Phase 6. Do not present findings inline or ask for feedback until the document is written.

### Output Format

```markdown
# Spec: {Feature Title}

**Date**: YYYY-MM-DD
**Branch**: {branchname}
**Research**: [{research_path}]({relative_research_path})
**Status**: Draft

---

## Requirements

| # | Trigger | Expected Outcome | Priority | Verified By |
|---|---------|-------------------|----------|-------------|
| R1 | When X | Then Y | Must | MT-1, IT-1, UT-1 |
| R2 | When A | Then B | Must | MT-2, IT-2 |
| R3 | When error Z | Then W | Should | MT-3, UT-2 |

## Test Matrix

| ID | Req | Type | Description | Status |
|----|-----|------|-------------|--------|
| MT-1 | R1 | Manual | {concise description of manual test} | ⬜ |
| MT-2 | R2 | Manual | {concise description of manual test} | ⬜ |
| IT-1 | R1 | Slow | {concise description of integration test} | ⬜ |
| IT-2 | R2 | Slow | {concise description of integration test} | ⬜ |
| UT-1 | R1 | Fast | {concise description of unit test} | ⬜ |

> Every requirement MUST appear in at least one row. Every row MUST trace to a requirement. This table is the at-a-glance verification contract — detailed preconditions, steps, and strategies live in the Verification Plan section below.

## Codebase Context

### Current State
2-3 sentences: what exists today in the affected area.

### Key Files
| File | Purpose | Relevance to This Feature |
|------|---------|--------------------------|

### Current Code Flow
1. [Actor] calls [method] at `file.cs:L42`
2. ...

### Pattern References
| New File | Pattern Source | What to Mirror |
|----------|---------------|----------------|

### DI Registration
{code example from existing feature, with source file:line}

### Configuration & Environment
| Variable | Purpose | Where Defined | Where Consumed |
|----------|---------|---------------|----------------|

## Implementation Approach

### Summary
2-3 sentences: what approach was chosen and why.

### Proposals Considered

| Approach | Strategy | Strengths | Weaknesses | Adopted |
|----------|----------|-----------|------------|---------|
| Minimal | Fewest changes | Low risk, fast | May miss X | Partial |
| Proven | Industry patterns | Battle-tested | New dependency | Core logic |
| Style-Matching | Codebase conventions | Consistent | More files | Structure |

### Changes Required

| Order | File | Action | Requirement(s) | Description |
|-------|------|--------|-----------------|-------------|
| 1 | `path/to/file.cs` | Modify | R1, R2 | What changes and why |
| 2 | `path/to/new.cs` | Create | R3 | What this file does |

### Dependencies
- New packages, services, or configuration needed (or "None")

## Verification Plan

### Manual Test Cases (AI-Agent Executable)

| ID | Req | Preconditions | Steps | Expected Result |
|----|-----|---------------|-------|-----------------|
| MT-1 | R1 | Service running on :5133 | 1. Send GET to /api/X 2. Check response | Status 200, body contains Y |
| MT-2 | R2 | Cache empty | 1. Call endpoint 2. Call again within TTL | Second call returns cached data |

#### Access Requirements

> **These items must be available for an AI agent to execute manual tests.**

- [ ] Credentials: {list or "None"}
- [ ] Running services: {list or "None"}
- [ ] MCP tools: {list or "None"}
- [ ] Browser access: {Yes/No}
- [ ] Other: {list or "None"}

### Integration Tests (Slow)

| ID | Req | Test File | Description | Fixture Strategy |
|----|-----|-----------|-------------|------------------|
| IT-1 | R1 | `Features/X/Tests/Slow/XIntegrationTests.cs` | Calls real API, verifies response | Capture JSON response |

### Unit Tests (Fast)

| ID | Req | Test File | Description | Mock Strategy |
|----|-----|-----------|-------------|---------------|
| UT-1 | R1 | `Features/X/Tests/Fast/XFixtureTests.cs` | Tests service logic with fixture | MockHttpMessageHandler |

## Open Questions

- [ ] {Anything unresolved after synthesis}
```

---

## Phase 6: Guided Walkthrough

**Prerequisite**: `{output_file}` MUST already be written to disk (Phase 5). Do not start this phase until the file exists.

**First**, tell the user where the spec is so they can follow along:

> "The spec is written to `{output_file}`. Open it now — I'll walk you through the key sections and ask for your feedback."

**Then** dispatch an agent to read the completed spec and prepare a structured walkthrough.

```
Task: "Prepare walkthrough" | subagent_type: Explore | model: haiku
Prompt:
Read the spec at {output_file} thoroughly.

Prepare a guided review with these sections. For each, write:
- A concise summary (2-3 sentences max)
- 1-2 targeted questions for the user

Sections to cover:
1. **Requirements** — Summarize the N requirements. Ask if they match intent and if anything's missing.
2. **Implementation approach** — Summarize the chosen approach and key tradeoff. Ask if the direction feels right.
3. **Manual test cases** — Summarize what will be tested manually. Ask if these would give confidence it works.
4. **Access requirements** — List what the AI agent needs. Ask if these are available.
5. **Integration & unit tests** — Summarize the automated test strategy. Ask if coverage seems adequate.
6. **Open questions** — List any unresolved items. Ask for clarification.

Return the walkthrough as structured text ready to present to the user.
```

Present the walkthrough to the user section by section. Collect feedback on each.

Update the spec with any changes. Set status to **Reviewed** if the user approves.

### Completion

```
Spec complete: {output_file}

Requirements: N behavioral requirements confirmed
Approach: {1-sentence summary}
Verification:
  - Manual test cases: N
  - Integration tests: N
  - Unit tests: N
Access needed: {list or "None"}

```

---

## Principles

1. **Requirements before solutions.** Lock down observable behaviors before designing anything.
2. **Real proof first. Mocks second.** The verification plan must prioritize real-system testing. Manual tests against the actual running system (real APIs, real databases, real browsers) are Priority 1. Integration tests calling real infrastructure are Priority 2. Unit tests with mocks are Priority 3 and only acceptable AFTER the plan establishes how real-world functionality will be proven. A verification plan that only has unit tests is not a verification plan — it's a wishlist.
3. **Three lenses, one plan.** Minimal finds the shortest path. Proven finds the safest. Style-Matching finds the most consistent. The best plan draws from all three.
4. **Every requirement gets a test.** If a requirement row doesn't link to at least one test case, it's a wish, not a requirement. Prefer linking to a manual or integration test over a unit test.
5. **Surface blockers early.** Access needs, missing credentials, unavailable services — all flagged in the spec, not discovered during implementation.
6. **User owns the requirements.** The skill proposes, the user confirms. No requirement is final until the human says so.
7. **Don't ask what you already know.** If the prompt is clear, move. Only elicit when genuine ambiguity exists.
8. **Test matrix at the top.** A consolidated test matrix immediately follows the Requirements table — every test case (manual, integration, unit) in one table so the verification contract is visible at a glance without scrolling to the Verification Plan.
