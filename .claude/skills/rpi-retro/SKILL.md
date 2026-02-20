---
name: rpi-retro
description: End-of-workflow retrospective — reads session JSONL history and branch artifacts, dispatches a team to analyze mistakes, dead ends, convention gaps, and missing skills. Produces actionable updates to CLAUDE.md, memory files, and new skill proposals. Use after completing an RPI workflow (research → plan → implement → cleanup) or any significant multi-session effort.
---

# /rpi-retro — Workflow Retrospective & Continuous Improvement

This is time to be **introspective**. Step back from the code, the feature, the specific bug. Meta-analyze how we worked, not what we built. The retro exists to make the *next* workflow better — not to summarize *this* one.

The question is never "what code did we change?" It is always: **"What would we do differently next time, and what conventions or tools would make that automatic?"**

**Shared conventions**: See [`rpi-common.md`](../rpi-common.md) for path resolution, critical rules, and agent prompt boilerplate used across all RPI skills.

---

## Retro-Specific Rules

This retro applies an **industrial engineering lens** to the AI SDLC. The pipeline is: Research → Plan → Implement → Test → Cleanup. Defects injected early (bad research, incomplete plans) are exponentially more expensive downstream. Rework — work flowing backward in the pipeline — is waste. The retro's job is to find where defects entered, where rework cycles occurred, and what documentation or automation would eliminate them.

- **Process lens, always.** The retro analyzes the *workflow*, not the code. A bug that was found and fixed is not a finding. The finding is: why did our process let that bug get injected? What upstream convention, documentation, or automation was missing? The code is already shipped — the retro prevents the *class* of process failure from recurring.
- **Generalize away from specifics.** Findings must be abstracted to the level that helps *future* work, not tied to this feature's details. BAD: "TABLEAU-SITE-NAME in Key Vault had a space character." GOOD: "Missing convention for validating Key Vault values against local config before deployment." The specific bug won't recur — but the class of process gap will unless we document the general rule.
- **Rework is the primary signal.** Every time work flows backward (implementation → back to planning, testing → back to implementation) that is waste. Each backward flow must be traced to its root cause: what upstream artifact or documentation was missing or wrong?
- **Evidence over opinion.** Every finding must cite a specific moment from the session history or a specific artifact. "Agents struggled" is not a finding. "Agent A retried 3 times at turn 12 because CLAUDE.md didn't document the required flag for `dotnet test`" is. But cite the evidence to *support* the generalized finding, not as the finding itself.
- **Actionable or drop it.** A finding that doesn't lead to a CLAUDE.md change, memory entry, skill proposal, or workflow fix gets cut.
- **Don't relitigate decisions.** The retro looks at process and execution, not whether the feature was the right thing to build.
- **Don't describe the implementation.** The retro report is not a changelog or a summary of code changes. If a reader needs to know what files were modified, they should look at `git diff`. The retro describes *how the process could improve*.
- **Proportional response.** A one-time mistake gets a memory entry. A recurring pattern gets a CLAUDE.md rule. A repeated mechanical failure gets a skill. Match the fix to the frequency.

---

## Input

**`$ARGUMENTS`**: Optional session ID, focus area, or flags.

```bash
/rpi-retro                                    # retro on current branch (all sessions)
/rpi-retro "452987e9-..."                     # retro on specific session ID
/rpi-retro "focus on the agent failures"      # retro with narrowed focus
/rpi-retro --sessions 3                       # only the last N sessions on this branch
```

### Flags

| Flag | Effect | Default |
|------|--------|---------|
| `--sessions N` | Limit to last N session files (by modification time) | All sessions for this branch |
| `--output <path>` | Override output directory for retro artifacts | `ai-docs/{branchname}/retro/` |

---

## Phase 1: Gather Evidence

**Collect everything the team will analyze. No agents yet — just data gathering.**

### 1a: Resolve Paths

1. Get branch name: `git branch --show-current`
2. Resolve output directory using **Path Resolution Pattern** from `rpi-common.md`:
   - Default: `ai-docs/{branchname}/retro/`
   - Override: `--output <path>`
   - Create the directory if it doesn't exist
3. Locate session directory: `~/.claude/projects/{project-path}/`
   - The project path is derived from the working directory (dashes replace slashes)
   - If the directory doesn't exist or has no `.jsonl` files: error and **STOP**

### 1b: Identify Session Files

Find all `.jsonl` files in the session directory **and its subdirectories**. Subagent sessions (spawned via the Task tool for teams, parallel work, etc.) are stored in subdirectories named after the parent session ID — not in the main session directory. Missing these means losing most of the workflow history.

**Search pattern:**
```bash
find ~/.claude/projects/{project-path}/ -name "*.jsonl" -type f
```

Sort all discovered files by modification time (newest first).

Apply filters:
- If `$ARGUMENTS` contains a UUID pattern (`[a-f0-9-]{36}`): use that session file **and** any `.jsonl` files in a subdirectory matching that UUID (these are its subagent sessions)
- If `--sessions N`: take the last N **top-level** session files, plus all subagent files nested under those sessions
- Otherwise: take all files

For each session file, record: `{id, path, size_bytes, modified_date, line_count, is_subagent}`.

Mark a file as `is_subagent: true` if it's nested inside a subdirectory (not directly in the session root). Record the parent session ID from the containing directory name.

If total size exceeds 2MB, warn: "Session history is large ({size}). Processing may take extra time. Consider using `--sessions N` to limit scope."

### 1c: Preprocess Session History

JSONL files contain raw API messages — thinking blocks, hook progress events, tool results with full file contents. Most of this is noise for a retro. **Extract only the signal.**

For each session file, use Bash with a Python script to extract a condensed timeline:

```python
# Extract from each JSONL line:
# - type=user: user message text (strip tool_results, keep text blocks)
# - type=assistant: text blocks + tool_use names/inputs (strip thinking blocks)
# - type=progress: skip entirely
# Output: a condensed markdown timeline per session
```

The preprocessing should produce a **session timeline** for each file:

```markdown
## Session: {session_id} ({date}) {[SUBAGENT of {parent_id}] if is_subagent}

### Turn 1
**User**: {message text}
**Assistant**: {text response}
  - Tool: {tool_name}({key_inputs})
  - Tool: {tool_name}({key_inputs})

### Turn 2
**User**: {message text}
**Assistant**: {text response}
  - Tool: {tool_name}({key_inputs})
  - Error: {any error in tool result}
...
```

**Subagent timelines**: Group subagent timelines under their parent session. This reveals the full workflow — what the orchestrator dispatched and what each subagent actually did (or failed to do).

**Key extraction rules:**
- User messages: extract `text` blocks only, skip `tool_result` blocks (they're responses to previous tool calls)
- Assistant messages: extract `text` blocks and `tool_use` blocks (name + abbreviated input). Skip `thinking` blocks entirely.
- For tool_use inputs: include only the first 200 chars of each input value to keep the timeline manageable
- Flag any tool_result that contains error indicators (`error`, `failed`, `exception`, `429`, `timeout`)
- Record `stop_reason` from assistant messages (especially `max_tokens` which indicates context exhaustion)

Write each session timeline to `ai-docs/{branchname}/retro/session-timelines.md`. Write the workflow context summary to `ai-docs/{branchname}/retro/workflow-context.md`. These become the input for the analysis agents and are preserved as retro artifacts.

**Never write working files to /tmp/.** All retro artifacts belong in `ai-docs/{branchname}/retro/` so they're versioned with the branch.

### 1d: Check Hook-Generated Struggle History

Check if `ai-docs/{branchname}/learnings.md` exists. This file is auto-populated by the `suggest-learn.js` stop hook whenever a session crosses struggle thresholds (tool errors, retry clusters, user rejections, user corrections).

If it exists:
1. Read it. Each entry has a timestamp, session ID, transcript path, classification, and metrics table.
2. **Cross-reference with session files from 1b.** Match session IDs from `learnings.md` to the JSONL files you discovered. Flag matched sessions as "hook-flagged" — these get priority analysis from the team in Phase 2.
3. **Include the struggle classifications in the workflow context.** When assembling `workflow-context.md`, add a section listing which sessions the hook flagged and why. This gives the analysis agents a head start — they know which sessions to scrutinize.
4. **Validate, don't trust blindly.** The hook's heuristics are coarse — e.g., 3 sequential `Read` calls trigger a "retry cluster" even when they're normal file scanning. The analysis agents should confirm whether flagged struggles were genuine.

If it doesn't exist, proceed normally — the hook only writes when thresholds are crossed.

### 1e: Inventory Branch Artifacts

List everything in `ai-docs/{branchname}/`:

```
ai-docs/{branchname}/
├── research.md          # codebase research output
├── spec.md               # implementation plan
├── retro/               # this skill's working files and output
│   ├── retro.md         # final retro report
│   ├── session-timelines.md  # preprocessed JSONL timelines
│   └── workflow-context.md   # assembled context for agents
└── {other artifacts}
```

Also collect:
- Current CLAUDE.md (project root + any feature CLAUDE.md files that were touched)
- Current memory files from `~/.claude/projects/{project-path}/memory/`
- Git log for this branch: `git log --oneline master..HEAD` (or appropriate base)
- List of files changed on this branch: `git diff --name-only master..HEAD`

---

## Phase 2: Dispatch Analysis Team

**Launch 4 agents in a single message. Each reads the session timeline(s) and artifacts through a different lens.**

### Agent A: Pipeline Flow Analyst

Maps the workflow against the expected pipeline (Research → Plan → Implement → Test → Cleanup) and identifies where defects were injected, where rework cycles occurred, and where time was wasted.

```
Task: "Pipeline flow analysis" | subagent_type: general-purpose
Prompt: |
  You are a Pipeline Flow Analyst applying an industrial engineering lens to an
  AI development workflow. The expected pipeline is: Research → Plan → Implement
  → Test → Cleanup. Your job: trace the actual flow, find where defects entered
  the pipeline, and identify every rework cycle (work flowing backward).

  **IMPORTANT: Process lens, not code lens.** A code bug that was found and fixed
  is not a finding. The finding is: which pipeline phase injected the defect?
  Did bad research lead to a flawed plan? Did the plan miss acceptance criteria
  that caused test failures? Did CLAUDE.md lack a convention that caused the
  agent to implement something wrong? Trace defects to their injection point.

  Session timeline(s): {path(s) to preprocessed timeline files}
  Branch artifacts: {list of ai-docs/{branch}/ files}
  Git log: {branch commit history}

  Read ALL session timelines and artifacts. Then analyze:

  1. **Pipeline Flow**: Map what actually happened to the expected pipeline phases.
     Did phases execute in order? Which phases were present? Summarize in 5-10
     bullet points, tagging each with its pipeline phase.

  2. **Rework Cycles**: Where did work flow backward in the pipeline? Look for:
     - Implementation → back to planning (plan was wrong or incomplete)
     - Testing → back to implementation (tests revealed defects)
     - Implementation → back to research (discovered missing knowledge mid-build)
     - Any phase repeated due to upstream failures
     For each: what triggered the backward flow, which upstream phase injected the
     defect, how many turns were wasted, what upstream artifact (research doc, plan,
     CLAUDE.md) should have prevented it.

  3. **Defect Injection Points**: For every mistake or correction in the workflow,
     trace it to the earliest pipeline phase where the defect could have been caught.
     A test failure caused by a missing acceptance criterion is a Plan defect, not a
     Test defect. An implementation error caused by undocumented conventions is a
     CLAUDE.md defect, not an Implementation defect.

  4. **Non-obvious Agent Mistakes**: What did agents get wrong that was NOT covered
     by CLAUDE.md or existing documentation? These are the undocumented "gotchas" —
     things a human familiar with the codebase would know but an agent doesn't.
     For each: what the agent assumed, what was actually true, what documentation
     would have prevented the mistake.

  5. **Bottlenecks & Idle Time**: What took disproportionately long? Where did
     agents idle waiting for something (rate limits, user input, blocked tasks)?
     What blocked other work from proceeding? For each: duration, cause, whether
     parallelization or a different approach would have helped.

  6. **Skipped Phases**: Were any pipeline phases missing or inadequate? Check for:
     - Research done but no plan generated
     - Implementation started without sufficient research
     - Tests written but never run to completion
     - Orchestrator dispatched agents but didn't follow through on results
     For each: what phase was expected, evidence it was skipped, downstream impact.

  7. **Interrupted Agents**: Were any subagents started but never completed?
     Look for: Task tool dispatches without corresponding completion messages,
     agents that produced partial output, agents killed by context exhaustion
     (max_tokens). Check subagent session timelines for incomplete work.

  8. **Efficiency Wins**: What went well? What pipeline patterns were notably
     effective? What should be preserved for future workflows?

  For EVERY finding: cite the session ID, turn number, and relevant context.

  Return a structured report with numbered findings in each category.
```

### Agent B: Convention Gap Analyzer

Identifies undocumented knowledge that agents needed but didn't have. Every user correction is evidence of a missing convention.

```
Task: "Convention gap analysis" | subagent_type: general-purpose
Prompt: |
  You are a Convention Gap Analyzer. Your job: find every moment where an agent
  lacked knowledge that CLAUDE.md should have provided. Every correction the user
  made is a missing convention. Every trial-and-error discovery is a documentation
  gap. Every violated pattern is an undocumented rule.

  **IMPORTANT: Process lens, not code lens.** Your findings must be convention
  and documentation improvements — CLAUDE.md additions, rule clarifications,
  missing guidance. Do NOT recommend code fixes. If a code bug revealed a
  documentation gap, describe the gap, not the bug.

  Session timeline(s): {path(s) to preprocessed timeline files}
  Project CLAUDE.md: {read and include content, or path}
  Feature CLAUDE.md files touched: {paths}
  Files changed on branch: {git diff --name-only output}

  Read ALL inputs. Then analyze:

  1. **User Corrections as Missing Conventions**: Find every instance where the user
     corrected an agent. Each correction = a rule that should exist in CLAUDE.md so no
     agent ever gets corrected on this again. For each: what the agent did wrong, what
     the user said, what CLAUDE.md rule would have prevented it.

  2. **Style/Naming/Architecture Violations**: Did agents violate naming conventions,
     folder structure rules, code style patterns, or architectural decisions? Look for:
     wrong file locations, wrong naming patterns, wrong abstraction levels, unnecessary
     complexity that the user had to simplify. For each: what the convention is (even if
     undocumented), how the agent violated it, proposed CLAUDE.md rule.

  3. **Tool & Command Usage Gaps**: Did agents use tools, commands, or flags incorrectly
     because CLAUDE.md didn't document the correct usage? Look for: wrong `dotnet test`
     flags, incorrect git commands, misconfigured build steps, wrong API invocations.
     For each: what was tried, what was correct, what CLAUDE.md should say.

  4. **Over-Engineering Corrections**: Did agents build something more complex than
     needed, and the user had to say "just do X simply"? These reveal missing
     zero-code patterns, config-only approaches, or simplicity conventions that
     CLAUDE.md should document. For each: what was over-engineered, what the simpler
     approach was, proposed CLAUDE.md rule.

  5. **Undocumented Zero-Code Patterns**: Did the workflow use config-only or
     convention-based approaches (like adding features via configuration without writing
     code, config binding behaviors, DI registration patterns) that aren't documented?
     These are especially easy to miss because no code file captures them.

  6. **Runtime Gotchas**: Did the workflow hit framework/runtime surprises that should
     be documented to prevent future agents from hitting the same issue? For each: what
     happened, what was expected, what the actual behavior was, proposed CLAUDE.md entry.

  For each finding:
  - What happened (cite session/turn)
  - What CLAUDE.md says (or doesn't say)
  - Proposed CLAUDE.md change (exact section and wording)

  Return findings grouped by: MUST-ADD, SHOULD-UPDATE, CONSIDER-ADDING.
```

### Agent C: Automation Candidate Analyzer

Identifies repeated mechanical failures and manual sequences that should become skills. Every time an agent fails at a tool invocation due to parameter complexity, or has to be walked through a multi-step sequence, that is an automation candidate.

```
Task: "Automation candidate analysis" | subagent_type: general-purpose
Prompt: |
  You are an Automation Candidate Analyzer. Find repeated mechanical failures
  and manual sequences that should be captured as reusable skills. Your focus:
  tool invocations agents failed at, multi-step sequences they had to be walked
  through, and build/test/deploy commands that failed due to unclear parameters.

  **IMPORTANT: Process lens, not code lens.** You are looking for skill and
  workflow improvements — automation opportunities, missing orchestration
  patterns, skill design gaps. Do NOT recommend code fixes or implementation
  changes. The question is always: "What skill or workflow change would make
  the next run smoother?"

  Session timeline(s): {path(s) to preprocessed timeline files}
  Existing skills: {list of .claude/skills/rpi-*/SKILL.md with name + description}
  Branch artifacts: {list of ai-docs/{branch}/ files}

  Read ALL inputs. Then analyze:

  1. **Repeated Tool/Command Failures**: Find tool invocations or commands that agents
     failed at repeatedly due to parameter complexity, unclear syntax, or wrong flags.
     Examples: wrong `dotnet test` filters, incorrect git commands, API calls with wrong
     parameters, build commands that needed specific flags. Each repeated failure with
     the same tool is a prime skill candidate — the skill encapsulates the correct
     invocation. For each: what was attempted, how many times it failed, what the
     correct invocation was, proposed skill that wraps it.

  2. **Walk-Through Sequences**: Where did the user have to walk an agent through a
     multi-step sequence step by step? If the user had to say "now do X, now do Y,
     now do Z" that sequence should be a skill. For each: the sequence of steps, how
     many turns it consumed, proposed skill that automates it.

  3. **Skill Gaps in Existing Skills**: Where did existing rpi-* skills fall short
     during this workflow? What capabilities were missing, what parameters were wrong,
     what edge cases weren't handled? For each: what was needed, which skill was closest,
     what specific change would close the gap.

  4. **Manual Orchestration Patterns**: Where did the user or orchestrator manually
     coordinate work that follows a repeatable template? Look for: agent dispatch
     patterns, recurring setup/teardown steps, repeated coordination between agents.

  5. **New Skill Proposals**: For each automation candidate above, propose a skill:
     - Name and trigger description
     - What mechanical failure or manual sequence it eliminates
     - Input/output
     - Why it's worth the investment (failure frequency × turns wasted per failure)

  For each finding: cite session/turn where the failure or manual sequence occurred.

  Return: improvements to existing skills, new skill proposals (ranked by
  failure frequency × time wasted).
```

### Agent D: Prevention Rule Extractor

For every mistake in the workflow, extracts the prevention rule: "What rule in CLAUDE.md or memory would have prevented this from ever happening?" The learning is never "here's what the bug was" — the learning is the upstream documentation that was missing.

```
Task: "Prevention rule extraction" | subagent_type: general-purpose
Prompt: |
  You are a Prevention Rule Extractor. For every mistake, correction, rework
  cycle, or wasted effort in this workflow, you extract the prevention rule:
  what should CLAUDE.md or memory say so that no agent ever makes this mistake
  again?

  **IMPORTANT: Process lens, not code lens.** Extract prevention rules — not
  code fixes or implementation details. A bug fix is evidence; the learning is
  the CLAUDE.md rule, memory entry, or convention that prevents the entire class
  of defect. Frame every learning as: "If CLAUDE.md had said X, the agent would
  not have done Y."

  Session timeline(s): {path(s) to preprocessed timeline files}
  Branch artifacts: {list of ai-docs/{branch}/ files with brief summary}
  Current memory files: {content of existing memory/*.md files, or "empty"}
  Project CLAUDE.md: {path — for deduplication}

  Read ALL inputs. Then extract prevention rules following these categories:

  | Category | Topic File | What Goes Here |
  |----------|-----------|----------------|
  | Prevention Rules | mistakes.md | For each mistake: the rule that prevents it. Format: "RULE: {what to do}. EVIDENCE: {what happened without this rule}." |
  | Debugging Strategies | debugging.md | Diagnostic approaches that worked — so agents try them first next time |
  | Workflow Patterns | patterns.md | Pipeline patterns that prevented rework — worth preserving |
  | Tool Invocations | tools.md | Correct command/flag/parameter patterns that agents got wrong initially |
  | User Preferences | preferences.md | Workflow choices stated or demonstrated by the user |
  | Architecture Decisions | decisions.md | Architectural choices and rationale — prevents agents from re-debating |
  | Codebase Gotchas | project.md | Undocumented behaviors agents hit — the "things a human would know" |
  | Config & Runtime | config-gotchas.md | Config binding surprises, framework quirks, hardcoded values that bit us |

  For each prevention rule:
  - Category and topic file
  - Title (short, imperative: "Always X before Y", "Never use X without Y")
  - Prevention rule (1-3 lines: what CLAUDE.md or memory should say)
  - Evidence (session/turn citation: what happened without this rule)
  - Whether this is LOCAL (project-specific) or GLOBAL (cross-project)
  - Upstream fix: should this be a CLAUDE.md rule (recurring) or memory entry (one-time)?

  Rules:
  - Only confirmed learnings — things that actually happened and were verified
  - Deduplicate against existing memory files and CLAUDE.md
  - Prevention rules for mistakes are highest-value — prioritize them
  - If a learning is already in CLAUDE.md, skip it
  - Frame as prevention, not description: "Always run dotnet test before claiming
    tests pass" not "Tests failed because agent didn't run dotnet test"

  Return: categorized prevention rules ready for memory file insertion, with
  recommendations on which should be escalated to CLAUDE.md rules.
```

**Wait for all 4 agents to complete.**

---

## Phase 3: Cross-Reference & Synthesize

**The orchestrator reads all 4 agent reports. Cross-references findings. Resolves conflicts.**

### 3a: Build the Findings Matrix

Create a unified list of all findings across agents. For each finding, note which agents reported it:

| # | Finding | Historian | Convention | Skill Gap | Learner | Consensus |
|---|---------|-----------|------------|-----------|---------|-----------|
| 1 | {finding} | Y/N | Y/N | Y/N | Y/N | N/4 |

### 3b: Classify and Prioritize

| Consensus | Priority | Action |
|-----------|----------|--------|
| 3-4 agents agree | **HIGH** | Definitely act on this |
| 2 agents agree | **MEDIUM** | Act if the evidence is clear |
| 1 agent only | **LOW** | Verify yourself, act only if confirmed |
| Contradiction | **RESOLVE** | Read the session timeline, determine which agent is right |

### 3c: Route Findings to Action Items

Each finding becomes exactly ONE of these action types. **Note: there is no "Code Fix" action type.** The retro never produces implementation tasks, bug patches, or code changes. If a finding is really "go fix this code," it belongs in a backlog or issue tracker, not here.

| Action Type | When | Output |
|-------------|------|--------|
| **CLAUDE.md Update** | Missing/wrong convention, repeated agent confusion | Proposed diff to CLAUDE.md |
| **Memory Entry** | Confirmed one-time learning, debugging insight | Entry for memory topic file |
| **Skill Proposal** | Recurring manual pattern worth automating | Skill spec (name, trigger, what it does) |
| **Workflow Fix** | Process issue, ordering problem, flag that should be default | Specific recommendation |
| **No Action** | Finding is correct but not actionable or too low frequency | Document in retro, don't act |

---

## Phase 4: Present for Approval

**Show the user everything BEFORE writing anything.**

```
Retrospective: {branch name}
Sessions analyzed: {N} ({date range})
Findings: {N} total ({H} high, {M} medium, {L} low priority)

CLAUDE.md Updates ({N}):
  [{priority}] {section}: {summary of change}
  [{priority}] {section}: {summary of change}

Memory Entries ({N}):
  [{priority}] {category}/{title}: {one-line summary}
  [{priority}] {category}/{title}: {one-line summary}

Skill Proposals ({N}):
  [{priority}] {skill-name}: {what it automates}
  [{priority}] {skill-name}: {what it automates}

Workflow Fixes ({N}):
  [{priority}] {recommendation}

No Action ({N}):
  {finding}: {why no action}

Apply these changes?
```

**Wait for user approval.** User can:
- Approve all
- Remove specific items
- Reprioritize items
- Add items they noticed
- Change action type (e.g., promote a memory entry to a CLAUDE.md rule)

---

## Phase 5: Apply Approved Changes

### 5a: Write Retro Report

Write the full retrospective to `{output_path}`.

**The retro report is NOT a changelog or implementation summary.** It describes process improvements, not code changes. A reader should understand what the *next* workflow will do differently — without needing to know what feature was built or what bugs were fixed.

```markdown
# Retrospective: {Branch Name}

**Date**: YYYY-MM-DD
**Branch**: {branchname}
**Sessions**: {N} sessions analyzed ({date range})
**Method**: 4-agent analysis (Pipeline Flow, Convention Gap, Automation, Prevention)

## Process Narrative

{5-10 bullets describing the *workflow* — what pipeline phases ran, where rework
occurred, where time was wasted. NOT what code was written or what the feature does.
Frame as: "The research phase missed X, causing rework during implementation."
NOT: "We added a Tableau config and fixed a 401 error."}

## Findings Summary

| Priority | CLAUDE.md | Memory | Skills | Workflow | No Action | Total |
|----------|-----------|--------|--------|----------|-----------|-------|
| High     | N | N | N | N | N | N |
| Medium   | N | N | N | N | N | N |
| Low      | N | N | N | N | N | N |

## CLAUDE.md Updates Applied

### {Generalized Convention Name}
**Priority**: {HIGH/MEDIUM/LOW}
**Process gap**: {what convention was missing and how it caused rework — generalized}
**Evidence**: Session {id}, Turn {N}
**Change**: {what was added/modified}

## Memory Entries Added

### {Category}: {Generalized Title}
{1-3 lines describing the general rule, not the specific instance}
- **Evidence**: Session {id}, Turn {N}
- **Scope**: LOCAL / GLOBAL

## Skill Proposals

### {skill-name}
**Trigger**: {when to use it}
**Automates**: {what manual work it replaces}
**Evidence**: Session {id}, Turn {N} — {why this would have helped}
**Estimated value**: {frequency × time saved}
**Status**: Proposed — not yet implemented

## Workflow Improvements

### {Generalized Recommendation}
**Process gap**: {what went wrong at the process level}
**Fix**: {what to do differently — applicable to any future workflow}

## Efficiency Wins

{What process patterns worked well — worth preserving for future workflows}

## Metrics

- Total turns across sessions: ~{N}
- Estimated wasted turns (mistakes + dead ends): ~{N} ({pct}%)
- Findings actioned: {N}/{total}
- Process improvement areas: {list}
```

### 5b: Apply CLAUDE.md Updates

For each approved CLAUDE.md update:
1. Read the current CLAUDE.md
2. Apply the edit using the Edit tool
3. Verify the edit was applied correctly

**Do NOT rewrite CLAUDE.md from scratch.** Make targeted edits only.

### 5c: Apply Memory Entries

For each approved memory entry:
1. Determine target: local (`~/.claude/projects/{project-path}/memory/`) or global (`~/.claude/memory/`)
2. Follow this write process:
   - Read existing topic file (if any)
   - Append under a date header
   - Update MEMORY.md index
3. Keep MEMORY.md under 200 lines

### 5d: Draft Skill Proposals

For each approved skill proposal:
- Write a brief spec to `ai-docs/{branchname}/skill-proposals/{skill-name}.md`
- Do NOT create the actual SKILL.md — that's a separate implementation task
- The proposal captures: name, trigger, what it does, input/output, evidence

---

## Phase 6: Report

**The report must be introspective and process-focused.** Do NOT summarize what code was changed, what bugs were fixed, or what the feature does. Summarize what *process improvements* were made and what the *next workflow* will do differently.

```
/rpi-retro complete: {branch}

Sessions: {N} analyzed ({date range})
Findings: {total} ({H} high, {M} medium, {L} low)

Applied:
  CLAUDE.md:  {N} updates applied
  Memory:     {N} entries added ({L} local, {G} global)
  Skills:     {N} proposals written to ai-docs/{branch}/skill-proposals/
  Workflow:   {N} recommendations documented

Retro report: {output_path}

Process takeaways (what we'd do differently next time):
  - {generalized process improvement, not specific to this feature}
  - {generalized process improvement}
  - {generalized process improvement}

Wasted effort: ~{N} turns ({pct}% of total)
Top improvement: {single most impactful process change}
```

---

## JSONL Preprocessing Reference

The session JSONL files follow this structure:

```jsonl
{"type": "user",      "message": {"role": "user",      "content": [{"type": "text", "text": "..."}]}, ...}
{"type": "assistant", "message": {"role": "assistant",  "content": [{"type": "thinking", ...}, {"type": "text", "text": "..."}, {"type": "tool_use", "name": "...", "input": {...}}]}, ...}
{"type": "progress",  "data": {"type": "hook_progress", ...}, ...}
```

### Extraction Script Template

```python
import json, sys, os, glob

def extract_timeline(jsonl_path):
    """Extract a human-readable timeline from a Claude Code JSONL session file."""
    timeline = []
    turn = 0

    with open(jsonl_path) as f:
        for line in f:
            obj = json.loads(line)
            msg_type = obj.get("type", "")

            if msg_type == "progress":
                continue  # Skip hook events

            message = obj.get("message", {})
            content = message.get("content", [])

            if msg_type == "user":
                texts = []
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        texts.append(block["text"][:500])
                if texts:
                    turn += 1
                    timeline.append(f"\n### Turn {turn}")
                    timeline.append(f"**User**: {' '.join(texts)}")

            elif msg_type == "assistant":
                parts = []
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    btype = block.get("type", "")
                    if btype == "text":
                        parts.append(f"**Assistant**: {block['text'][:500]}")
                    elif btype == "tool_use":
                        name = block.get("name", "?")
                        inp = block.get("input", {})
                        # Abbreviate input values
                        brief = {k: str(v)[:200] for k, v in inp.items()}
                        parts.append(f"  - Tool: `{name}`({brief})")
                    # Skip thinking blocks

                stop = message.get("stop_reason", "")
                if stop == "max_tokens":
                    parts.append("  - **WARNING**: Hit max_tokens (context exhaustion)")

                if parts:
                    timeline.append("\n".join(parts))

    return "\n".join(timeline)

def find_all_sessions(session_dir):
    """Find all JSONL files including subagent sessions in subdirectories."""
    sessions = []
    # Top-level session files
    for path in sorted(glob.glob(os.path.join(session_dir, "*.jsonl"))):
        session_id = os.path.basename(path).replace(".jsonl", "")
        sessions.append({"id": session_id, "path": path, "is_subagent": False})
    # Subagent session files (in {session-id}/ subdirectories)
    for path in sorted(glob.glob(os.path.join(session_dir, "*", "*.jsonl"))):
        session_id = os.path.basename(path).replace(".jsonl", "")
        parent_dir = os.path.basename(os.path.dirname(path))
        sessions.append({"id": session_id, "path": path, "is_subagent": True, "parent": parent_dir})
    return sessions

if __name__ == "__main__":
    for path in sys.argv[1:]:
        if os.path.isdir(path):
            # Directory mode: find all sessions including subagents
            for session in find_all_sessions(path):
                label = f"[SUBAGENT of {session['parent']}] " if session.get("is_subagent") else ""
                print(f"## Session: {session['id']} {label}\n")
                print(extract_timeline(session["path"]))
                print("\n---\n")
        else:
            session_id = os.path.basename(path).replace(".jsonl", "")
            print(f"## Session: {session_id}\n")
            print(extract_timeline(path))
            print("\n---\n")
```

### Handling Large Sessions

If a session timeline exceeds ~50KB after preprocessing:
1. Split into chunks of ~30 turns each
2. Dispatch a summarizer agent per chunk (haiku model for speed)
3. Each summarizer produces a 1-page summary with key events, errors, and corrections
4. Feed summaries (not raw timelines) to the analysis team

---

## Failure Handling

| Situation | Action | Max Retries |
|-----------|--------|-------------|
| No JSONL files found | Search subdirectories too — subagent sessions are nested. If still none: error with path, STOP. | 1 |
| JSONL too large (>5MB total) | Warn user, suggest `--sessions N` | 0 |
| Preprocessing fails | Fall back to raw Read of first/last 500 lines per file | 1 |
| Agent can't access timeline | Check temp file paths, retry with inline content | 1 |
| No findings from agents | Report "clean workflow" — still write the retro report | 0 |
| CLAUDE.md edit conflicts | Present the conflict, let user resolve | 0 |
| Subagent sessions not found | Check `{session-id}/` subdirectories. If the main session used Task tool but no subagent JSONLs exist, note the gap in the retro report. | 1 |

---

## Principles

1. **Introspection, not narration.** The retro is a meta-analysis of how we worked, not a summary of what we built. Never describe code changes, bug fixes, or feature details. Always describe process gaps, missing conventions, and workflow improvements.
2. **Generalize or discard.** Every finding must be abstracted to a level that helps future work on *any* feature, not just this one. If a finding only makes sense in the context of this specific feature, it's not a retro finding — it's a changelog entry.
3. **Retrospectives compound.** Each retro makes the next workflow better. Skip the retro and you repeat the same mistakes. The 20 minutes spent here saves hours next time.
4. **Process, not blame.** The retro analyzes what the system (agents, skills, conventions) could do better — not what the user "should have done."
5. **Proportional fixes.** One-time issues get memory entries. Recurring issues get CLAUDE.md rules. Workflow gaps get skill proposals. Don't over-engineer fixes for flukes.
6. **Evidence-based only.** If it didn't happen in the session history, it's not a finding. Speculation belongs in brainstorming, not retros. But cite evidence to support the generalized finding — the evidence is not the finding itself.
7. **Close the loop.** Research → Plan → Implement → Cleanup → Learn → **Retro**. The retro feeds back into the conventions and skills that make the next cycle faster.
