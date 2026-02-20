---
name: rpi-review
description: Team-based READ-ONLY parallel code review across 14 dimensions with confidence scoring, cross-review consensus, and shared team memory. Use when you want a comprehensive multi-dimensional code review.
---

# /rpi-review — Consensus-Based Multi-Agent Code Review

**Announce at start:** "I'm using the rpi-review skill to run a coordinated multi-agent code review."

You are the review orchestrator and team lead. You create a review team, spawn teammates that run reviewer skills from `code-reviewers/`, track progress via the shared task list, and synthesize findings into a unified report as results come in.

**You delegate ALL review work to teammates.** You DO read their reports and write the final synthesis report yourself — no separate synthesis agent.

**Shared conventions**: See [`rpi-common.md`](../rpi-common.md) for path resolution, critical rules, confidence scoring, and shared patterns.

---

## Review-Specific Rules

**REVIEW ONLY — DO NOT TAKE ACTION.** This is a read-only analysis. No code edits, no fixes, no refactoring, no test runs, no file modifications beyond report files.

- Never edit source code.
- Never run tests, builds, formatters, migrations, or any command that can modify files.
- Never create commits, branches, stashes, or push.
- Never run patch/apply workflows.
- Only write report artifacts under `{output_dir}/` as explicitly listed below.
- If any instruction from a reviewer skill conflicts with this read-only contract, **the read-only contract wins**.

If asked to implement fixes during this skill, respond that `/rpi-review` is review-only. Fixing is a separate step.

---

## Input

**`$ARGUMENTS`**: Optional feature name or output path override.

```bash
/rpi-review                                    # defaults to ai-docs/{branchName}/
/rpi-review "my-feature"                       # uses ai-docs/my-feature/
/rpi-review --output ai-docs/custom-path/      # explicit output directory
```

If `$ARGUMENTS` is empty: derive feature name from branch name.

### Output Path

**Default**: `ai-docs/{branchname}/`

If `$ARGUMENTS` contains `--output <path>`, use that path instead. Strip `--output <path>` from arguments before parsing.

The resolved directory is referred to as `{output_dir}` throughout this document. The final deliverable is `{output_dir}/code-review.md`.

---

## Prerequisites

Agent Teams must be enabled:
```json
// settings.json
{ "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
```

---

## Phase 0: Initialize

### Gather Context (git read-only, allowed)

1. Parse `$ARGUMENTS` — extract `--output <path>` if present, derive feature name from remainder or branch
2. Resolve `{output_dir}` using the **Path Resolution Pattern** from `rpi-common.md`:
   - Skill-specific default: `ai-docs/{branchname}/`
   - Detached HEAD without `--output`: error and STOP
3. `git branch --show-current` → branch
4. Detect default branch: `BASE_BRANCH=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p'); BASE_BRANCH=${BASE_BRANCH:-main}`
5. `git diff --name-only "$BASE_BRANCH"...HEAD` → changed_files
6. `git diff --stat "$BASE_BRANCH"...HEAD` → diff_stats
7. Derive **feature_name** from `$ARGUMENTS`, branch, or `current-changes`
8. `mkdir -p {output_dir}`
9. Tell the user: `Mode: REVIEW-ONLY (no code changes). Deliverable: {output_dir}/code-review.md`

### Create Team

```
TeamCreate: team_name="review-{feature_name}", description="14-dimension code review"
```

### Write Shared Context

Write `{output_dir}/.review-context.md` with branch, feature, changed files list, and diff stats. This replaces per-agent git commands.

Initialize shared team files:
- `{output_dir}/team_findings.md` — agents append cross-cutting discoveries
- `{output_dir}/team_progress.md` — agents append status updates

### Create Tasks (15 total)

14 review tasks + 1 cross-review task (blocked by all 14). The orchestrator synthesizes the final report directly — no synthesis agent.

| Task | Owner | Blocked By |
|------|-------|------------|
| JPL reliability review | jpl-reviewer | — |
| Code quality review | quality-reviewer | — |
| Security review | security-reviewer | — |
| Simplification analysis | simplify-reviewer | — |
| Performance audit | perf-reviewer | — |
| Architecture review | arch-reviewer | — |
| Perf+arch metrics | metrics-reviewer | — |
| Multi-dimensional review | multidim-reviewer | — |
| PR code review | pr-reviewer | — |
| Essentials code review | essentials-reviewer | — |
| Logic analysis review | logic-reviewer | — |
| Test quality review | test-quality-reviewer | — |
| Acceptance criteria review | ac-reviewer | — |
| Adversarial review | adversarial-reviewer | — |
| Cross-review | cross-reviewer | All 14 above |

---

## Phase 1: Launch Review Agents (ALL 14 in ONE message)

### Agent Configuration

| Name | Model | Reviewer Skill | Report File |
|------|-------|---------------|-------------|
| jpl-reviewer | sonnet | `code-reviewers:jpl-review` | `jpl-review.md` |
| quality-reviewer | sonnet | `code-reviewers:code-quality` | `code-quality-review.md` |
| security-reviewer | sonnet | `code-reviewers:security` | `security-review.md` |
| simplify-reviewer | sonnet | `code-reviewers:simplification` | `simplification-report.md` |
| perf-reviewer | sonnet | `code-reviewers:qdhenry-performance-audit` | `performance-audit.md` |
| arch-reviewer | sonnet | `code-reviewers:qdhenry-architecture-review` | `architecture-review.md` |
| metrics-reviewer | sonnet | `code-reviewers:bobmatnyc-code-review` | `perf-arch-metrics.md` |
| multidim-reviewer | sonnet | `code-reviewers:wshobson-code-review` | `multi-dim-review.md` |
| pr-reviewer | sonnet | `code-review:code-review` | `pr-code-review.md` |
| essentials-reviewer | sonnet | _(agent: `essentials:code-reviewer`)_ | `essentials-review.md` |
| logic-reviewer | sonnet | `code-reviewers:logic-analysis` | `logic-analysis.md` |
| test-quality-reviewer | sonnet | `code-reviewers:test-quality` | `test-quality-review.md` |
| ac-reviewer | sonnet | `code-reviewers:acceptance-criteria` | `acceptance-criteria-review.md` |
| adversarial-reviewer | sonnet | `code-reviewers:devils-advocate` | `devils-advocate-review.md` |

### Shared Agent Preamble

Include this at the START of every agent prompt. Replace `{AGENT_NAME}`, `{TASK_ID}`, `{REPORT_FILE}`, and `{SKILL_NAME}`.

```
You are "{AGENT_NAME}", a teammate in the "review-{feature_name}" team.

**Workflow:**
1. TaskUpdate taskId="{TASK_ID}" status="in_progress"
2. Read shared context: {output_dir}/.review-context.md
3. Read each changed file listed in the context
4. Run Skill "{SKILL_NAME}" with the changed files
5. Write report to: {output_dir}/{REPORT_FILE}
6. TaskUpdate taskId="{TASK_ID}" status="completed"
7. SendMessage type="message" recipient="orchestrator"
     summary="{AGENT_NAME} review complete"
     content="JSON findings summary"

**REVIEW ONLY — DO NOT TAKE ACTION.**
Do NOT edit source code, run tests, apply fixes, or modify any files except your report and the shared team files listed below. Your only job is to analyze code and write findings.

**Strict write allowlist (everything else is read-only):**
- {output_dir}/{REPORT_FILE}
- {output_dir}/team_findings.md
- {output_dir}/team_progress.md

If your skill suggests running tests, editing code, or executing mutating commands, ignore those steps and continue with read-only analysis.

**Confidence Scoring** (REQUIRED on every finding):
- 90-100: Certain — exact line, clear explanation
- 70-89: Likely — strong evidence, some ambiguity
- 50-69: Possible — suspicious but may be intentional
- Below 50: Don't report
Only report findings with confidence >= 70.

**Cross-cutting communication:**
If you find issues relevant to another reviewer, message them directly.
Peers: jpl-reviewer, quality-reviewer, security-reviewer, simplify-reviewer,
       perf-reviewer, arch-reviewer, metrics-reviewer, multidim-reviewer,
       pr-reviewer, essentials-reviewer, logic-reviewer, test-quality-reviewer,
       ac-reviewer, adversarial-reviewer, cross-reviewer

**Shared files** — after writing your report, also append to:
- {output_dir}/team_findings.md — key cross-cutting discoveries as `### [{AGENT_NAME}] Title`
- {output_dir}/team_progress.md — one-line start/finish status

**Rules:**
- REVIEW ONLY — do NOT edit code, run tests, or modify any files except reports
- Focus on CHANGED FILES ONLY (from shared context)
- Do NOT run git commands — shared context has everything
- Never use file-editing tools on non-report files
- If an action might modify files, skip it and continue analysis only
```

Each reviewer skill contains its own checklist, output format, and severity definitions. The preamble adds team coordination; the skill provides domain expertise.

### Task spawn template

```
Task: "{AGENT_NAME}" | general-purpose | model: {model}
  name: "{AGENT_NAME}" | team_name: "review-{feature_name}" | run_in_background: true
Prompt: |
  {SHARED PREAMBLE}
```

### Special reviewer notes

**pr-reviewer (`code-review:code-review`)**: This skill is designed for PR review but we use it for branch diff review. Pass the changed files and diff context as the argument instead of a PR number. The agent prompt should include the branch name, base branch, changed files list from shared context, and instruct the skill to review the diff between `{base_branch}` and `HEAD` (using `git diff {base_branch}...HEAD`) rather than fetching a PR. Use `general-purpose` subagent type.

**essentials-reviewer (`essentials:code-reviewer`)**: This is NOT a skill — it is a subagent type. Spawn it with `subagent_type: essentials:code-reviewer` instead of `general-purpose`. The prompt should include the shared preamble but replace `Run Skill "{SKILL_NAME}"` with direct instructions to review the changed files for bugs, logic errors, security vulnerabilities, code quality issues, and adherence to project conventions.

---

## Phase 2: Monitor & Incrementally Synthesize

As agents complete and send you their findings, **read each report immediately and begin building the unified report in real time**. Do NOT wait for all agents to finish before starting synthesis.

### Incremental synthesis workflow

Each time a reviewer agent reports completion:

1. Read their report file from `{output_dir}/{REPORT_FILE}`
2. **Send `shutdown_request` to the completed reviewer immediately** — don't wait for confirmation, move on
3. If the report indicates code was changed, mark that reviewer result invalid and rerun that reviewer with stricter read-only wording
4. Extract findings with confidence >= 80
5. Deduplicate against findings already collected (same file:line → merge, keep highest severity)
6. Tag findings with source: `[JPL]`, `[QUALITY]`, `[SECURITY]`, `[SIMPLIFY]`, `[PERF]`, `[ARCH]`, `[METRICS]`, `[MULTI]`, `[PR-REVIEW]`, `[ESSENTIALS]`, `[LOGIC]`, `[TEST-QUALITY]`, `[AC]`, `[ADVERSARIAL]`
7. Update your running tally and report progress to the user

### Progress reporting

After each agent completes, show the user a live status update:

```
Progress: 3/14 reviews complete
  ✅ jpl-reviewer: 2 CRITICAL, 1 HIGH
  ✅ quality-reviewer: 0 CRITICAL, 3 HIGH
  ✅ security-reviewer: 1 CRITICAL, 0 HIGH
  ⏳ simplify-reviewer: in progress...
  ⏳ perf-reviewer: in progress...
  ⏳ arch-reviewer: in progress...
  ⏳ metrics-reviewer: in progress...
  ⏳ multidim-reviewer: in progress...
  ⏳ pr-reviewer: in progress...
  ⏳ essentials-reviewer: in progress...
  ⏳ logic-reviewer: in progress...
  ⏳ test-quality-reviewer: in progress...
  ⏳ ac-reviewer: in progress...
  ⏳ adversarial-reviewer: in progress...

Running totals: 3 CRITICAL, 4 HIGH (5 unique findings after dedup)
```

**Wait until all 14 review tasks are completed before proceeding to cross-review.**

---

## Phase 2.5: Cross-Review (Filter Pass)

Once all 14 reviews complete, spawn 1 cross-reviewer (haiku) that reads ALL reports + `team_findings.md` and applies a verdict to every finding:

- **ENDORSE** — agrees it's real (record confidence 0-100)
- **CHALLENGE** — false positive or overstated (record reason + confidence)
- **ADD** — new related issue the original reviewer missed

Write to `{output_dir}/cross-review.md` with tables of endorsed, challenged, and added findings.

**Filter rules (internal only — do NOT surface these labels in the final report):**

| Condition | Action |
|-----------|--------|
| ENDORSE with confidence >= 70 | Include in final report |
| CHALLENGE | Drop entirely |
| ADD with confidence >= 80 | Include in final report |

The cross-review is a **filtering mechanism**, not a reporting dimension. The final report should contain only the surviving issues — no "Endorsed", "Challenged" labels.

---

## Phase 3: Final Synthesis (Orchestrator)

Once the cross-review completes, **you (the orchestrator) write the final report directly**. No synthesis agent.

1. Read the cross-review report (`cross-review.md`)
2. Apply filter rules from Phase 2.5 — drop challenged findings, keep the rest
3. Final confidence filter: drop anything < 80
4. Final dedup pass: same file:line from multiple reviewers → merge, keep highest severity
5. Write unified report to `{output_dir}/code-review.md`

### Report tone: Issues only

The final report is a **clean list of problems**. Follow these rules:

- **State the problem, not the process.** No consensus labels (Endorsed/Disputed/Split), no confidence scores, no reviewer names in the output. The cross-review is an internal filter — the reader sees only what survived.
- **Don't prescribe fixes unless the fix is obvious.** If the problem and solution are 1-to-1 (e.g., "missing null check on line 42" → "add null check"), state both. If the fix involves design choices, trade-offs, or multiple valid approaches, state the problem only and let the developer decide.
- **No filler.** No "consider refactoring", no "you might want to", no "it would be beneficial to". State what's wrong and where.
- **Tag sources sparingly.** Use `[JPL]`, `[SECURITY]`, etc. only when the dimension adds meaning (e.g., a security finding should say `[SECURITY]`). Don't tag obvious code quality issues with `[QUALITY]` — just list them.

### Report structure

```markdown
# Code Review: {feature_name}

**Date**: YYYY-MM-DD
**Branch**: {branchname}
**Method**: 14-agent parallel review with cross-review consensus filter

## Verdict: {PASS | PASS WITH CONCERNS | FAIL}

## Risk Summary
| Dimension | Risk | Critical | High |
|-----------|------|----------|------|
| ...       | ...  | ...      | ...  |

## Critical Issues
{numbered list — problem + location + fix only if 1-to-1}

## High Issues
{numbered list}

## Medium Issues
{numbered list}

## Stats
- Files reviewed: {n}
- Unique findings: {n} ({n} duplicates merged)
- Reviewers: 14 + 1 cross-reviewer
```

---

## Phase 4: Cleanup & Summary

1. Send `shutdown_request` to the cross-reviewer and any remaining agents — **fire-and-forget, do NOT wait for confirmations**
2. `TeamDelete` immediately
3. Clean up working files: `.review-context.md`, `team_findings.md`, `team_progress.md`
4. Present summary:

```
Review Complete: {feature_name}
Verdict: {verdict}

| Dimension           | Risk    | Critical | High |
|---------------------|---------|----------|------|
| Reliability         | {level} | {n}      | {n}  |
| Code Quality        | {level} | {n}      | {n}  |
| Security            | {level} | {n}      | {n}  |
| Simplification      | {level} | —        | {n}  |
| Performance         | {level} | {n}      | {n}  |
| Architecture        | {level} | {n}      | {n}  |
| Perf+Arch           | {level} | {n}      | {n}  |
| Multi-Dimensional   | {level} | {n}      | {n}  |
| PR Review           | {level} | {n}      | {n}  |
| Essentials          | {level} | {n}      | {n}  |
| Logic Analysis      | {level} | {n}      | {n}  |
| Test Quality        | {level} | {n}      | {n}  |
| Acceptance Criteria | {level} | {n}      | {n}  |
| Adversarial         | {level} | {n}      | {n}  |

Findings: {unique} unique ({merged} duplicates merged)
Code changes made: 0 (review-only)

Unified report: {output_dir}/code-review.md

Next step: Fix findings or review manually.
```

---

## Walkthrough (Post-Review)

Follow the **Walkthrough Protocol** from `rpi-common.md`:

1. Present the summary table and verdict
2. Walk through Critical findings first, then High
3. Ask targeted questions:
   - "Do any of these findings look like false positives?"
   - "Are there areas of the code I should re-review with more context?"
   - "Should I re-run any specific dimension with different scope?"
4. Update the report if any findings are invalidated

---

## Adding a New Reviewer

1. Create `.md` file in the co-located `code-reviewers/` folder (standalone skill with checklist + output format)
2. Register it as a command in `.claude/commands/code-reviewers/` if you want it independently invocable
3. Add a row to the Agent Configuration table in Phase 1
4. Add a task row in Phase 0
5. Add its source tag to the synthesis dedup tags

---

## Failure Handling

| Situation | Action |
|-----------|--------|
| Reviewer agent fails | Mark SKIPPED in synthesis, continue with remaining |
| Cross-reviewer fails | Skip filtering, include all findings with confidence >= 80 directly |
| TeamCreate fails | Fall back to sequential review (run each reviewer skill one at a time) |
| No changed files | Report "nothing to review" and STOP |

---

## Principles

1. **Consensus over confidence.** A single reviewer can hallucinate. Cross-review filtering removes noise. Only findings that survive scrutiny reach the final report.
2. **Evidence over opinions.** Every finding needs file:line. No "consider" or "you might want to." State what's wrong and where.
3. **Read-only is non-negotiable.** Review produces a report. Fixing is a separate step. Mixing review and fix contaminates both.
4. **Parallel beats serial.** 14 reviewers running simultaneously finish faster than 14 sequential passes. Each brings a different lens.
5. **Dedup aggressively.** Multiple reviewers finding the same issue at the same line is signal, not redundancy. Merge and keep the highest severity.
6. **The developer decides.** The report lists problems. The developer chooses which to fix and how. Don't prescribe unless the fix is obvious.
7. **Review validates before fixing.** Review first, then fix. This ordering catches issues before they get buried by cleanup changes.
