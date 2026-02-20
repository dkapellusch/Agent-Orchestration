---
name: rpi-research
description: Research and document a codebase area as-is using role-differentiated agents with consensus-based verification
---

# /rpi-research — Consensus-Based Codebase Research

**Announce at start:** "I'm using the rpi-research skill to investigate this area."

Document what exists. Only accept what multiple agents agree on or what you can verify against source code. The output is a factual map of the codebase — not suggestions, not improvements, not critiques.

**Shared conventions**: See [`rpi-common.md`](../rpi-common.md) for path resolution, critical rules, walkthrough protocol, and consensus patterns used across all RPI skills.

---

## Research-Specific Rules

- **FAR filter.** Every finding must be **F**actual (verified against code), **A**ctionable (useful for planning), and **R**elevant (to the research question). Findings that aren't all three get flagged or dropped.
- **Consensus threshold**: >= 80% consensus rate required (see `rpi-common.md` for calculation)

---

## Input

**`$ARGUMENTS`**: A task description, area of code, or specific question to investigate. Optionally includes flags.

```bash
/rpi-research "the Health feature"
/rpi-research "how does the Slack tool registration pipeline work"
/rpi-research "the conversation WebSocket flow" --output docs/websocket-research.md
/rpi-research "the Snowflake query pipeline" --external
/rpi-research "Jira integration" --external --output docs/jira-research.md
```

If `$ARGUMENTS` is empty: error with usage example. **STOP.**

### Flags

| Flag | Effect |
|------|--------|
| `--output <path>` | Override default output path |
| `--external` | Launch 2 additional haiku agents for web research (library docs, API contracts, version compatibility) |

Strip all flags from `$ARGUMENTS` before parsing the research question.

### Output Path

**Default**: `ai-docs/{branchname}/research.md`

If `$ARGUMENTS` contains `--output <path>`, use that path instead. Strip `--output <path>` from the arguments before parsing the research question.

The resolved path is referred to as `{output_path}` throughout this document.

---

## Phase 1: Scope

1. Parse `$ARGUMENTS` — strip `--output <path>` and `--external` if present, remainder is `{research_question}`
2. Set `{external_mode}` = true if `--external` was present, false otherwise
3. Resolve `{output_path}` using the **Path Resolution Pattern** from `rpi-common.md`:
   - Skill-specific default: `ai-docs/{branchname}/research.md`
   - Detached HEAD without `--output`: error and STOP
4. State the research scope in one sentence and confirm with user if ambiguous
5. If `{external_mode}`: inform user — "External research enabled — 2 additional web research agents will run alongside codebase agents."

**Do not launch agents yet.**

---

## Phase 1.5: Read & Scout

Before dispatching investigation agents, build a **file map** so they start from known locations instead of searching blindly.

### Step 1: Read User-Mentioned Files

If `$ARGUMENTS` or `{research_question}` references specific files, tickets, folders, or docs — read them directly in main context now. This gives you concrete context for writing better agent prompts.

Examples of references to look for:
- File paths (`McpServerHost/Features/Slack/SlackService.cs`)
- Feature names that map to known folders (`"the Slack feature"` → `Features/Slack/`)
- Ticket IDs or doc links (fetch if accessible via MCP tools)

### Step 2: Dispatch Locator Agents

Dispatch 1-2 `codebase-locator` agents (haiku, fast) to identify WHERE the relevant code lives.

**Single-area research** — dispatch 1 locator:

```
Task: "Scout file locations" | subagent_type: essentials:codebase-locator | model: haiku
Prompt: |
  Find all files and directories relevant to: {research_question}

  I need:
  1. The primary feature folder(s) — full path
  2. Entry point files (controllers, MCP tools, endpoints, CLI commands)
  3. Service/business logic files
  4. Model/DTO files
  5. Test files (Slow tests, Fast tests, fixture directories)
  6. Configuration files (.env references, appsettings, constants files)
  7. Any CLAUDE.md or README.md inside the feature folder(s)

  Return a structured list of file paths grouped by category.
```

**Multi-area research** (research question spans 2+ distinct areas) — dispatch 2 locators in parallel, one per area.

### Step 3: Build the File Map

When locator(s) return, assemble a `{file_map}` — a structured block of specific paths to inject into Phase 2 agent prompts:

```
FILE MAP (from scout phase):
  Feature folder(s): {paths}
  Entry points: {paths}
  Services: {paths}
  Models: {paths}
  Tests: {paths}
  Config: {paths}
  Docs: {paths}
```

**Do not proceed to Phase 2 until the file map is built.**

---

## Phase 2: Parallel Investigation (Role-Differentiated Agents)

**Two waves.** Wave 1 dispatches 3 role-differentiated agents with the file map from scout. Wave 2 dispatches targeted follow-ups only if needed.

### Wave 1: Core Investigation

**Dispatch 3 agents in a single message.** Each has a different investigative lens and receives the file map so they start from known locations.

### Agent A: Structure Mapper

Finds files, folders, architecture, registration patterns.

```
Task: "Structure mapping" | subagent_type: Explore | thoroughness: very thorough
Prompt: |
  Research question: {research_question}

  Start from these known files: {file_map}. Expand outward from here.

  You are a Structure Mapper documenting an existing codebase. Your ONLY job is to describe what exists — not to suggest changes, critique, or recommend improvements.

  Your focus — the shape of the code:
  1. Find the primary feature folder(s) and list ALL files within them
  2. Read CLAUDE.md / README.md in affected feature folders
  3. Map the complete file structure: services, models, tools, tests, configuration
  4. Identify naming conventions and patterns (with examples)
  5. Document the DI registration pattern (IFeature vs extension methods)
  6. Find the closest analogous feature(s) for structural comparison
  7. Identify test file organization: where are Slow tests, Fast tests, fixtures?

  For every finding, include the exact file path and line range. No claims without evidence.

  Return a structured report covering:
  - Feature folder path(s) and complete file listing
  - Key classes, interfaces, and their responsibilities (with file paths)
  - DI registration approach (with file path and line range)
  - Naming patterns observed (with concrete examples)
  - Similar features in the codebase (with file paths)
  - Test structure and organization
  - Areas flagged for follow-up: list any references you found but couldn't fully trace (e.g., "found reference to X at file:line but couldn't locate the definition")
```

### Agent B: Code Flow Tracer

Traces execution paths, data flow, error handling.

```
Task: "Code flow tracing" | subagent_type: Explore | thoroughness: very thorough
Prompt: |
  Research question: {research_question}

  Start from these known files: {file_map}. Expand outward from here.

  You are a Code Flow Tracer documenting an existing codebase. Your ONLY job is to describe what exists — not to suggest changes, critique, or recommend improvements.

  Your focus — how the code executes:
  1. Identify every entry point (controllers, MCP tools, endpoints, CLI commands)
  2. Trace the primary code path step-by-step: entry → service → dependency → response
  3. Read key service method bodies — document what each method actually does
  4. Trace error handling: what exceptions are caught, what happens on failure, any retry logic
  5. Identify async patterns: is this sync or async? Any Task.WhenAll? CancellationToken usage?
  6. Document data transformations: what shape does data enter as, how is it transformed, what shape exits?
  7. Note any caching, batching, or optimization in the hot path

  For every finding, include the exact file path and line range. No claims without evidence.

  Return a structured report covering:
  - Entry points (with file paths and line ranges)
  - Step-by-step code flow (with function names and file:line references)
  - Error handling and fallback behavior
  - Async patterns and concurrency
  - Data transformations along the path
  - Areas flagged for follow-up: list any code paths you found but couldn't fully trace (e.g., "call to X at file:line leads to an area I couldn't fully explore")
```

### Agent C: Dependency Mapper

Maps integration points, configuration, cross-feature coupling.

```
Task: "Dependency mapping" | subagent_type: Explore | thoroughness: very thorough
Prompt: |
  Research question: {research_question}

  Start from these known files: {file_map}. Expand outward from here.

  You are a Dependency Mapper documenting an existing codebase. Your ONLY job is to describe what exists — not to suggest changes, critique, or recommend improvements.

  Your focus — what this code connects to:
  1. Find all references to the feature's main service/interface (Grep for usages)
  2. Identify every external API, SDK, or service called
  3. Map configuration: .env variables, appsettings, constants — where they're defined AND consumed
  4. Find shared infrastructure consumed: base classes, middleware, utilities, NuGet packages
  5. Check for cross-feature dependencies (does anything else import from this feature? does this import from others?)
  6. Identify the test infrastructure: fixtures, test helpers, shared test base classes, mock patterns
  7. Document credential/auth requirements: what tokens, keys, or connection strings are needed?

  For every finding, include the exact file path and line range. No claims without evidence.

  Return a structured report covering:
  - Upstream callers (what calls into this, with file:line)
  - Downstream dependencies (what this calls out to, with file:line)
  - Configuration variables and their purpose (where defined AND where consumed)
  - Shared infrastructure consumed
  - Cross-feature coupling
  - Credential and auth requirements
  - Areas flagged for follow-up: list any dependencies you found but couldn't fully trace (e.g., "references config var X but couldn't find where it's defined")
```

**Wait for all 3 Wave 1 agents to complete.**

### Wave 2: Targeted Follow-Ups (conditional)

After Wave 1 completes, review all 3 reports. Dispatch follow-up agents **only if** any of these conditions are true:

1. **Incomplete traces**: An agent flagged an area as "found references but couldn't fully trace"
2. **Solo findings with unexplored files**: A 1/3 finding references files that neither of the other two agents explored
3. **Contradictions pointing to unread code**: Two agents disagree and the resolution requires reading a file neither fully examined

**If none of these conditions are met, skip Wave 2 and proceed to Phase 2b/Phase 3.**

For each follow-up needed, dispatch a targeted haiku agent:

```
Task: "Follow-up: {specific_topic}" | subagent_type: essentials:codebase-analyzer | model: haiku
Prompt: |
  Read {specific_file}:{line_range} and answer this specific question:
  {specific_question_from_wave_1_gap}

  Return:
  - The exact code found at that location
  - What it does (factual description only)
  - How it relates to: {the_finding_that_triggered_this_followup}
```

**Follow-up agent consensus rules:**
- Follow-up findings participate in the consensus matrix as **corroborating evidence**
- A 1/3 finding that a follow-up agent confirms becomes 2/4 (higher confidence)
- A 2/3 finding that a follow-up agent also confirms becomes 3/4
- Follow-up agents do NOT create new top-level findings — they only confirm, deny, or clarify existing ones

**Wait for all follow-up agents to complete (if any were dispatched).**

---

## Phase 2b: External Research (Only if `--external`)

**Skip this phase entirely if `{external_mode}` is false.**

The codebase agents map what the code does. External agents validate what the code *should* do — current library versions, API contract accuracy, deprecation status, and upstream documentation. This catches cases where the code works but is built on stale assumptions.

**Dispatch 2 haiku agents in a single message.** Use the codebase agent findings and the file map from Phase 1.5 to focus the web research — don't search blindly.

### Agent D: Documentation Validator

Fetches current official documentation for libraries, SDKs, and APIs found by codebase agents.

```
Task: "Documentation validation" | subagent_type: general-purpose | model: haiku
Prompt: |
  Research question: {research_question}

  You are a Documentation Validator. The codebase agents identified these
  external dependencies — your job is to verify the code's usage against
  current official documentation.

  Dependencies identified by codebase agents:
  {list of libraries, SDKs, NuGet packages, APIs from Agent C's report}

  For each significant dependency:
  1. Search for the OFFICIAL documentation (prefer docs sites, GitHub repos, NuGet pages)
  2. Find the CURRENT stable version and compare to what the codebase uses
  3. Check for breaking changes, deprecations, or migration guides between the used version and current
  4. Verify API contracts: do the methods/endpoints the code calls still exist and behave as expected?
  5. Check for known issues, security advisories, or CVEs against the used version
  6. Note any configuration patterns the docs recommend that the code doesn't follow

  Use WebSearch and WebFetch to find documentation. Prioritize:
  - Official docs sites (docs.microsoft.com, developer.*, etc.)
  - GitHub repos (README, CHANGELOG, releases)
  - NuGet/npm/PyPI package pages (for version info)

  DO NOT fabricate documentation URLs or version numbers. If you can't find
  authoritative info for a dependency, say so — don't guess.

  Return a structured report:
  - Dependency name, used version (from codebase), current version (from web)
  - Version delta and risk assessment (up-to-date / minor behind / major behind / deprecated)
  - API contract validation: methods/endpoints confirmed or flagged
  - Deprecation warnings with migration path if available
  - Security advisories if any
  - Source URL for each finding
```

### Agent E: Precondition & Contract Researcher

Validates assumptions, preconditions, and integration contracts the code relies on.

```
Task: "Contract research" | subagent_type: general-purpose | model: haiku
Prompt: |
  Research question: {research_question}

  You are a Precondition & Contract Researcher. The codebase agents traced
  how the code integrates with external systems — your job is to verify
  those integration assumptions are still valid.

  Integration points from codebase agents:
  {list of external APIs, endpoints, auth patterns, data contracts from Agents B and C}

  For each integration point:
  1. Search for the current API documentation or specification
  2. Verify endpoint URLs, HTTP methods, request/response schemas
  3. Check authentication requirements: has the auth method changed? Any new scopes needed?
  4. Look for rate limits, quotas, or usage policies the code should respect
  5. Find SLA/availability guarantees if documented
  6. Check for API versioning: is the code using a versioned endpoint? Is that version still supported?
  7. Look for any announced deprecation timelines or sunset dates

  Use WebSearch and WebFetch to find authoritative sources. Prioritize:
  - API reference docs (Swagger/OpenAPI specs, developer portals)
  - Changelogs and release notes
  - Status pages and deprecation announcements

  DO NOT fabricate API contracts or endpoints. If you can't verify a
  specific contract, say so explicitly.

  Return a structured report:
  - Integration point, what the code assumes, what docs say
  - Contract status: confirmed / changed / deprecated / unverifiable
  - Auth requirement changes if any
  - Rate limits or quotas the code should be aware of
  - Deprecation timelines if announced
  - Source URL for each finding
```

**Wait for both external agents to complete.**

---

## Phase 3: Consensus & Verification

**Cross-reference all agent reports. Apply the consensus filter.**

### Step 1: Build the Comparison Matrix

**Standard mode (3 core agents, no follow-ups):**

| Finding | Structure Mapper | Code Flow Tracer | Dependency Mapper | Consensus |
|---------|-----------------|------------------|-------------------|-----------|
| [claim] | reported / silent | reported / silent | reported / silent | 3/3, 2/3, 1/3, or contradiction |

**Standard mode with follow-ups (3 core + N follow-up agents):**

Core consensus is still based on the 3 role-differentiated agents. Follow-up agents count as additional corroborating evidence — they can upgrade confidence but don't create new top-level findings.

| Finding | Structure Mapper | Code Flow Tracer | Dependency Mapper | Follow-up(s) | Consensus |
|---------|-----------------|------------------|-------------------|-------------|-----------|
| [claim] | reported / silent | reported / silent | reported / silent | confirmed / denied / — | 3/3, 2/3+confirmed=3/4, 1/3+confirmed=2/4, etc. |

**External mode (5+ agents):** Add two columns for the external agents. External agents participate in consensus for dependency/integration findings only — they don't vote on codebase structure or code flow.

| Finding | Structure | Code Flow | Dependencies | Follow-up(s) | Doc Validator | Contract Researcher | Consensus |
|---------|-----------|-----------|-------------|-------------|--------------|-------------------|-----------|
| [codebase claim] | reported / silent | reported / silent | reported / silent | confirmed / — | — | — | 3/3, 2/3, 1/3 (+ follow-up corroboration) |
| [dependency claim] | reported / silent | reported / silent | reported / silent | confirmed / — | reported / silent | reported / silent | up to 5/5+ |

**Follow-up agent consensus rules:**
- Follow-up agents **corroborate** existing findings: a 2/3 finding confirmed by a follow-up becomes 3/4 (higher confidence)
- Follow-up agents **deny** existing findings: a 1/3 finding denied by a follow-up is downgraded and likely rejected
- Follow-up agents do NOT create new top-level findings — they only confirm, deny, or clarify Wave 1 findings

**External agent consensus rules:**
- External agents **strengthen** codebase findings about dependencies (e.g., Dependency Mapper says "uses Slack API v2", Doc Validator confirms current version is v2 → higher confidence)
- External agents **challenge** codebase findings (e.g., Dependency Mapper says "uses endpoint /v1/chat", Contract Researcher finds /v1/chat is deprecated → flag as risk)
- External-only findings (no codebase agent reported it) are tagged as **[EXTERNAL]** and included in a separate "External Findings" section — they inform planning but don't affect codebase consensus rate

### Step 2: Apply Classification Rules

| Consensus | Action |
|-----------|--------|
| 3/3 agree (codebase) | **Accept** — high confidence. Include directly. |
| 2/3 agree (codebase) | **Accept** — corroborated. Include, note confidence. |
| 1/3 only (codebase) | **Verify** — read the source code yourself. Accept only if confirmed. |
| Contradiction (codebase) | **Resolve** — use the contradiction checklist below. |
| External confirms codebase | **Strengthen** — upgrade confidence, note external validation. |
| External contradicts codebase | **Flag** — include both perspectives, mark as risk. The code is what it is, but the external source suggests the assumption may be stale. |
| External-only finding | **Include separately** — add to External Findings section. Does not count in consensus rate. |

### Step 3: Resolve Contradictions

When agents disagree on a finding:

1. **Are they describing different layers?** (e.g., one found the wrapper, one found the HTTP call underneath — both true)
2. **Is one describing old code vs new code?** (check git blame if unclear)
3. **Is one describing happy path vs error path?** (both valid, document both)
4. **Is one describing intended behavior vs actual behavior?** (document actual, flag discrepancy)
5. **Read the source code directly.** At least one agent is factually wrong. Open the file, read the function, determine which agent's claim matches reality. Document which agent was correct, which was wrong, and cite the exact file:line that proves it. Proceed.

If still unresolved after all 5 checks: document the ambiguity in Open Questions and proceed. Do not retry resolution steps.

### Step 4: Verify Solo Findings

For 1/3 findings, apply verification depth:

- **Syntax check**: Does the file path exist? Does it contain the cited code? (fast)
- **Semantic check**: Does the code do what the agent claimed? Read the function body. (medium)
- **Behavioral check**: If the claim is about runtime behavior, trace up/downstream (max 2 files deep). (slow — only for critical claims)

### Step 5: Track Confidence

Maintain a running tally:

```
Consensus findings (3/3): N
Corroborated findings (2/3): N
Follow-up corroborated (upgraded from lower consensus): N
Verified solo findings (1/3, confirmed): N
Rejected findings (1/3, unconfirmed): N
Contradictions resolved: N
Follow-up agents dispatched: N (0 if Wave 2 was skipped)
```

When follow-up agents were dispatched, note which findings they affected:
- `2/3 → 3/4 (follow-up confirmed)` — counts as consensus
- `1/3 → 2/4 (follow-up confirmed)` — counts as corroborated
- `1/3 → denied by follow-up` — counts as rejected

---

## Phase 4: Walkthrough & Validation

Follow the **Walkthrough Protocol** from `rpi-common.md`:

1. Write the draft to `{output_path}`
2. Invite user to read, then wait for confirmation
3. Ask targeted questions about **specific claims** (not generic "is this correct?")
4. Update immediately after each answer

**Research-specific walkthrough coverage** (minimum 4 questions):
1. **Architecture / code flow** — "Is this how it actually works?"
2. **Dependencies / integration points** — "Did I miss any connections?"
3. **Edge cases or error handling** — "What happens when X fails?"
4. **Tribal knowledge** — "Any historical context or undocumented behavior I should capture?"

---

## Phase 5: Finalize

The research document at `{output_path}` should now reflect all corrections from the walkthrough.

### GitHub Permalinks

If on a pushed branch or main, generate permanent references by getting the current commit hash and repo info (e.g., via `git rev-parse HEAD` and `gh repo view`). Replace key file references with: `https://github.com/{owner}/{repo}/blob/{hash}/{path}#L{line}`

### Quality Gate

Calculate the **consensus rate**: `(consensus + corroborated) / total * 100`

Where:
- `consensus` = 3/3 findings + any findings upgraded to consensus by follow-up corroboration (e.g., 2/3 → 3/4)
- `corroborated` = 2/3 findings + any findings upgraded to corroborated by follow-up (e.g., 1/3 → 2/4)
- `total` = consensus + corroborated + verified_solo + rejected

- **>= 80% consensus rate**: Research passes. Present to user.
- **< 80% consensus rate**: Warn the user: "Research quality is below threshold ({N}% consensus, minimum 80%). Many findings are unverified solo claims. Consider re-running with a narrower scope or verifying key findings manually."

### Present to User

```
Research complete: {output_path}

Confidence:
- Consensus (3/3): N findings
- Corroborated (2/3): N findings
- Follow-up corroborated: N findings (upgraded from lower consensus)
- Verified (1/3): N findings
- Rejected: N findings
- Contradictions resolved: N
- Follow-up agents dispatched: N {0 = Wave 2 skipped, all findings were solid}
- Consensus rate: N% {">= 80% — PASS" | "< 80% — BELOW THRESHOLD"}
{if --external:}
- External validations: N confirmed, N flagged, N external-only
- Dependencies checked: N (M up-to-date, P behind, Q deprecated)

Key findings:
- [2-3 bullet executive summary]

To ask follow-up questions, re-run /rpi-research — findings will be appended.
```

---

## Follow-Up Questions

If the user has follow-up questions after research is complete:

1. Append a new section to the existing research document:
   ```markdown
   ## Follow-Up: {question} (YYYY-MM-DD)
   ```
2. Dispatch agents as needed for the follow-up investigation
3. Apply the same consensus filter
4. Update confidence summary

---

## Output Format

The research document (`{output_path}`) must follow this structure:

```markdown
# Research: {Title}

**Date**: YYYY-MM-DD
**Branch**: {branchname}
**Scope**: One sentence describing what was researched
**Method**: Scout → {3 or 5}-agent role-differentiated consensus with source verification {+ targeted follow-ups if needed} {+ external web research if --external}

## Confidence Summary

| Category | Count |
|----------|-------|
| Consensus (3/3 agents) | N |
| Corroborated (2/3 agents) | N |
| Follow-up corroborated (upgraded) | N |
| Verified (1/3, source-confirmed) | N |
| Rejected (unconfirmed) | N |
| Contradictions resolved | N |
| Follow-up agents dispatched | N |

## Executive Summary

2-3 sentences: what this area does, how it's structured, key characteristics.

## How It Currently Works

### Architecture
- Entry points (controllers, MCP tools, endpoints)
- Service layer (main services, interfaces)
- External dependencies (APIs, databases, SDKs)

### Entry / Exit Points
| Entry Point | Type | File | Line |
|-------------|------|------|------|
| `MethodOrEndpoint` | Controller / MCP Tool / etc. | `path/to/file.cs` | L42 |

### Key Files
| File | Purpose |
|------|---------|
| `path/to/file.cs` | Description |

### Code Flow
1. [Actor] calls [API/method] at `file.cs:L42`
2. [Service] processes via [method] at `file.cs:L78`
3. [Service] calls [dependency] at `file.cs:L95`
4. [Dependency] returns [type] at `file.cs:L102`
5. [Response] returned to [Actor]

### Error Handling & Fallbacks
| Scenario | Behavior | File |
|----------|----------|------|
| [External API down] | [What happens] | `file.cs:L120` |
| [Invalid input] | [What happens] | `file.cs:L55` |

## Integration Points

### Upstream (what calls this)
- [Caller]: `file.cs:L30` — [how and why]

### Downstream (what this calls)
- [Dependency]: `file.cs:L90` — [how and why]

### Configuration
| Variable | Purpose | Defined | Consumed | Required |
|----------|---------|---------|----------|----------|
| `ENV_VAR` | Description | `.env:L5` | `file.cs:L12` | Yes/No |

### Credentials & Auth
| Credential | Purpose | Source |
|------------|---------|--------|
| `API_KEY` | Authenticates to X | `.env` / KeyVault |

## Patterns & Conventions

### Patterns Used
- [Pattern]: `file.cs:L42` — [how it's applied]

### Similar Features
| Feature | Similarity | Key File |
|---------|-----------|----------|
| `Feature/` | Description | `path/to/file.cs` |

## External Findings (only if --external)

### Dependency Versions
| Dependency | Used Version | Current Version | Delta | Risk | Source |
|------------|-------------|-----------------|-------|------|--------|
| `Package.Name` | 1.2.3 | 1.4.0 | Minor | Low | [docs link] |

### API Contract Validation
| Integration Point | Code Assumes | Docs Say | Status | Source |
|-------------------|-------------|----------|--------|--------|
| `POST /api/endpoint` | v1 schema | v2 schema | Changed | [docs link] |

### Deprecation & Security Alerts
| Item | Issue | Timeline | Action Needed | Source |
|------|-------|----------|---------------|--------|
| `Library.Name` | Deprecated in v3.0 | EOL 2025-12 | Migrate to X | [link] |

## Open Questions

- [ ] [Anything unresolved or ambiguous after research]
- [ ] [Contradictions that couldn't be fully resolved]
```

---

## Principles

1. **Role diversity beats redundancy.** Three agents with different lenses catch more than three identical agents. Structure Mapper, Code Flow Tracer, and Dependency Mapper each see things the others miss.
2. **Consensus over confidence.** A single agent can hallucinate. Two agents agreeing is signal. Three is strong evidence. But even 2/3 agreement isn't infallible — spot-check.
3. **Evidence over votes.** A minority finding with a clear file:line reference outweighs majority consensus without evidence. Require proof.
4. **Verify, don't trust.** Solo findings get verified against source code, not taken on faith. Contradictions get investigated, not majority-voted away.
5. **Document what IS.** No suggestions, no improvements, no "you should." Just facts with file references.
6. **User knowledge fills gaps.** The validation phase catches what all agents miss — tribal knowledge, undocumented behaviors, historical context.
7. **FAR filter.** Every finding must be Factual, Actionable, and Relevant. If it's not all three, flag it or drop it.
8. **External validates, not replaces.** Web research confirms or challenges what the codebase agents found. It never overrides source code evidence — code is truth, docs are context. External findings inform planning but don't change what the code does today.
