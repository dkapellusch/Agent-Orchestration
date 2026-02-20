# RPI Skills — Shared Conventions

This file contains shared patterns, rules, and boilerplate used across all `rpi-*` skills.

---

## Path Resolution Pattern

All RPI skills support `--output <path>` flag and default to `ai-docs/{branchname}/`.

### Standard Resolution Logic

```bash
# 1. Parse flags from $ARGUMENTS
if $ARGUMENTS contains "--output <path>":
    CUSTOM_OUTPUT_PATH = <path>
    strip "--output <path>" from $ARGUMENTS

# 2. Get branch name
BRANCH=$(git branch --show-current)

# 3. Handle detached HEAD
if [ -z "$BRANCH" ]; then
    if [ -z "$CUSTOM_OUTPUT_PATH" ]; then
        error: "Detached HEAD detected — cannot resolve default path. Pass --output explicitly."
        STOP
    fi
fi

# 4. Resolve output path
if [ -n "$CUSTOM_OUTPUT_PATH" ]; then
    OUTPUT_PATH="$CUSTOM_OUTPUT_PATH"
else
    OUTPUT_PATH="ai-docs/${BRANCH}/<skill-specific-default>"
fi

# 5. Ensure parent directory exists
mkdir -p "$(dirname "$OUTPUT_PATH")"
```

Each skill declares its own default output path in its SKILL.md. The pattern above provides the shared resolution logic.

---

## Critical Rules (Shared Across All Skills)

### Context Priority Hierarchy

**CLAUDE.md is the highest authority.** When skill instructions conflict with project CLAUDE.md or README.md, the project conventions win. Always.

Priority order (highest to lowest):
1. **Project CLAUDE.md / README.md** — non-negotiable conventions, test structure, code style
2. **Research document** (`ai-docs/{branch}/research.md`) — what exists today, how the codebase works
3. **PRD / Plan** (`ai-docs/{branch}/prd.md`) — what we're building and why
4. **Skill instructions** — how to orchestrate the work

Every agent MUST read these files before writing any code or making decisions:
- `CLAUDE.md` at the repository root (and any parent worktree CLAUDE.md)
- `CLAUDE.md` in affected feature folders (if they exist)
- `README.md` at the repository root
- The research document (if it exists)
- The PRD (if it exists)

### Documentation Philosophy
- **Document what IS, not what SHOULD BE.** No suggestions, no improvements, no critiques (research).
- **Requirements before solutions.** Lock down behaviors before designing (plan).
- **Think before implementing.** Every phase must answer "How will we test this?" BEFORE writing code (implement).

### Evidence Requirements
- **Every claim needs evidence.** File path + line range, or it's not a finding.
- **No magic strings.** Use constants, `nameof()`, enums — never hardcode strings.
- **No comments except WHY.** Self-documenting code preferred. XML docs (`///`) on all public APIs.

### Quality Gates
- **Research consensus threshold**: >= 80% consensus rate required
  - Formula: `(consensus_3_3 + corroborated_2_3) / total_findings * 100`
  - Below 80%: warn user, recommend narrower scope or manual verification
- **Implementation AC coverage threshold**: 100% required
  - Every acceptance criterion must have at least one test (manual, integration, or unit)
  - < 100%: status is NEEDS_FIXES

### Test Philosophy

**Real proof first. Mocks second. This is non-negotiable.**

A feature is proven by interacting with the real system — calling real APIs, querying real databases, hitting real endpoints, opening real browsers. Mocks test your assumptions about reality; only real systems test reality itself. "It works with mocks" is not evidence that the feature works.

The required verification order:
1. **Manual tests come FIRST.** Prove it works like a human would — real HTTP calls, real DB queries, real browser interactions. If you can't demonstrate the feature working against the real system, it isn't done.
2. **Integration tests (Slow) use real infrastructure.** Real DI, real databases, real APIs. These are the automated source of truth. They must call real services and assert specific AC outcomes.
3. **Unit tests (Fast) come LAST.** They cover what integration tests can't — edge cases, validation, error handling. They are derived FROM real Slow test fixtures, not invented from assumptions. Unit tests are a supplement, not a substitute.
4. **Mock at the boundary only.** External HTTP, SDKs, databases, file I/O. Never mock your own code. And only after the real integration is proven.

- **Zero tolerance for test failures.** ALL tests must pass — "not related to my changes" is NOT acceptable.

---

## Agent Prompt Boilerplate

### Shared Context Block Template

Include this in every agent prompt across all implementation phases:

```
SHARED CONTEXT:
  Working directory: {project root or worktree path}
  Phase assignment: {this phase's plan section — what to implement, which files, which ACs}
  Previous phases proved: {summary + file paths from earlier phases}
  Pattern file: {path to similar existing component}

  MANDATORY FIRST STEP — Read these files before writing ANY code:
  1. CLAUDE.md at the repository root (and parent worktree CLAUDE.md if applicable)
  2. CLAUDE.md in affected feature folders (if they exist)
  3. README.md at the repository root
  4. Research document: {research path} (if it exists)
  5. PRD: {prd path} (if it exists)
  These define test structure, code style, naming, architecture, and non-negotiables.
  CLAUDE.md conventions OVERRIDE skill instructions when they conflict.

  ZERO TOLERANCE TEST POLICY:
  ALL tests must pass — not just yours. The full suite must be green.
  You may NOT skip tests, comment out assertions, disable tests, or
  claim a failure is "pre-existing" or "not related to my changes."
  If a test fails, fix it. If you can't fix it, escalate to the TL.
  A phase is not complete until `test run = 0 failures`.
```

### Agent Anti-Patterns to Detect

**Flattery red flags** — if an agent says any of these phrases, its output is suspect and should be validated:
- "You're absolutely right"
- "That's a great point"
- "I completely agree"
- "Excellent observation"

When detected: mark output for manual verification, do not accept on first pass.

---

## Walkthrough Protocol (Shared Pattern)

After producing a document, always walk through key findings with the user:

1. **Write the draft** to the output path first
2. **Invite the user to read**: "The draft is at `{path}`. Please read through it — I'll wait, then walk through the key findings with you."
3. **Wait for user confirmation**
4. **Ask targeted questions** about specific claims (not generic "is this correct?")
5. **Update immediately** after each answer — don't batch corrections

### Good Walkthrough Questions (Examples)

- "I found that `SlackService` calls the Slack API through `HttpClient` directly at `SlackService.cs:L45`, with no retry wrapper. Is that accurate, or is there middleware I missed?"
- "The code flow shows requests go Controller → Service → Repository, but I didn't find any caching layer. Is that intentional, or does caching happen somewhere I didn't trace?"
- "I identified 3 entry points: the REST controller, the MCP tool, and the health check. Are there any other ways this feature gets invoked?"

---

## Failure Handling Patterns

### Retry Limits (Standard Across Skills)

| Situation | Max Retries | Fallback |
|-----------|-------------|----------|
| Build fails after scaffold | 2 | Report to user, human takes over |
| Manual test fails | 2 per phase | Developer fixes, Tester re-verifies |
| Manual test infrastructure missing | 2 per phase | Fix it (start Docker, load creds, start service), then retest |
| Review/PM rejects | 2 per phase | Report to user |
| Automated tests fail | 2 per phase | Report to user |
| Phase exhausts retries | 1 | Try a different approach. If that also fails, report what was tried and what worked. |

### Infrastructure Resolution (Implement Only)

When manual tests can't run (missing credentials, service down, Docker not running):
1. **Fix the infrastructure problem.** Start Docker. Load credentials. Start the service. Do not document — solve.
2. If the fix requires something truly unavailable (e.g., a third-party API key that doesn't exist), mock at the boundary and write a fixture-based test instead.
3. If two different approaches both fail, note what was tried and continue — but "I didn't try" is never acceptable.
4. Every test must be either "passed" or "passed via alternative approach" — never "blocked" or "not tested".

---

## Session Handoff Protocol

When a session approaches context limits or a workflow spans multiple sessions, write a handoff file so the next session can resume without rediscovery.

### When to Write a Handoff

- **Context exhaustion**: Before running `/compact` or when you see `max_tokens` warnings
- **End of session**: When stopping mid-workflow (e.g., research done, plan not started)
- **Branch switch**: When context will be lost by switching to a different worktree

### Handoff File Location

Write to `ai-docs/{branchname}/handoff.md`. Overwrite on each new handoff — only the latest matters.

### Required Sections

```markdown
# Handoff: {branch name}

**Date**: YYYY-MM-DD
**Session**: {session ID if known}
**Phase**: {which RPI phase we're in — research/plan/implement/cleanup/review/learn/retro}

## Current State
{What's done, what's in progress, what's next. Be specific — file paths, not descriptions.}

## Artifacts Produced
{List every file created or modified this session with its purpose.}
- `ai-docs/{branch}/research.md` — completed research document
- `.claude/skills/rpi-retro/SKILL.md` — new skill, needs review

## Pending Work
{Numbered list of what remains, in priority order.}
1. Run `/rpi-plan` on the research output
2. Fix the 2 critical issues from code review

## Key Decisions Made
{Decisions that would be expensive to re-derive.}
- Chose flat skill directories (`rpi-research/`) over nested (`rpi/research/`)
- Rate limit cap: max 5 parallel haiku agents

## Blockers
{Anything that prevents the next step. Empty if none.}
```

### Rules

- **Write state to files, not just context.** The next session starts fresh — it can't read your thinking.
- **File paths over descriptions.** "Research is at `ai-docs/documentation/research.md`" not "research is done."
- **Decisions are expensive.** If you spent 3 turns figuring something out, write it down. The next session shouldn't repeat that work.
- **All working files in `ai-docs/`, never `/tmp/`.** Working files must be versioned with the branch.

---

## Consensus & Verification Patterns

### Research: 3-Agent Consensus Matrix

| Consensus | Action |
|-----------|--------|
| 3/3 agree | **Accept** — high confidence |
| 2/3 agree | **Accept** — corroborated |
| 1/3 only | **Verify** — read source code yourself, accept only if confirmed |
| Contradiction | **Resolve** — use 5-step checklist, read source directly if needed |

### Plan: 3-Solution Synthesis

| Approach | Strategy | When to Prefer |
|----------|----------|----------------|
| Minimal | Fewest changes | Low-risk, fast iteration |
| Proven | Industry patterns | External APIs, unfamiliar domains |
| Pattern-matching | Codebase conventions | Consistency with existing code |

Synthesize by taking the best elements of each, not by voting.

### Implement: Phase-Based Decomposition

**Outside-in, bottom-up order:**
1. Database / external APIs (prove contracts work)
2. Service layer (prove business logic works)
3. API endpoints (prove request/response works)
4. UI (prove rendering works)
5. E2E (prove full journey works)

Each phase implements AND tests before the next begins.

---

## Output Format Standards

### File References
Always use `file:line` format for precise references:
- Good: `SlackService.cs:45`
- Bad: "in the Slack service file somewhere"

### GitHub Permalinks (When Available)
If on a pushed branch or main:
```bash
HASH=$(git rev-parse HEAD)
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
# https://github.com/{REPO}/blob/{HASH}/{path}#L{line}
```

### Confidence Scoring (Research & Review)
- 90-100: Certain — exact line, clear explanation
- 70-89: Likely — strong evidence, some ambiguity
- 50-69: Possible — suspicious but may be intentional
- Below 50: Don't report

Only report findings with confidence >= 70 in draft. Final threshold: >= 80 after cross-validation.

---

## Attribution

These patterns were identified by the code review in `ai-docs/rpi-skills/code-review.md` and extracted to reduce duplication. Original finding:

> **Issue #17: Duplicated content across skills (~231 lines)**
> Path resolution logic, critical rules structure, walkthrough protocols, and agent prompt boilerplate are repeated across all 3 skills. Changes must be applied in 3 places.

This file is the solution.
