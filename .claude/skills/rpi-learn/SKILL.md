---
name: rpi-learn
description: Reflect on the current conversation and extract learnings — captures patterns, mistakes, solutions, and conventions into persistent memory files. Use at the end of a work session, after fixing a tricky bug, or whenever you want Claude to remember something. Triggers on "learn from this", "what did we learn", "save learnings", "update memory", or at session end.
---

# /rpi-learn — Conversational Reflection & Memory Capture

Review what happened in this conversation. Extract what's worth remembering. Persist it so future sessions benefit. Nothing speculative — only things that actually happened and were confirmed.

---

## Critical Rules

- **Only capture confirmed learnings.** If something was attempted but not verified, it's a hypothesis, not a learning. Label it as such.
- **Evidence required.** Every learning must trace to something that happened in the conversation — a bug fixed, a pattern discovered, a mistake corrected, a command that worked.
- **Don't duplicate CLAUDE.md.** If a convention is already documented in CLAUDE.md, don't re-document it in memory. Only capture NEW discoveries.
- **Compress aggressively.** Each learning should be 1-3 lines. Details go in topic files, not MEMORY.md.
- **Categorize, don't dump.** Every learning goes into a specific topic file. MEMORY.md is the index.
- **Never delete existing memories without cause.** Append or update — only remove if a memory is proven wrong.
- **User controls what's saved.** Present findings for approval before writing.

---

## Input

**`$ARGUMENTS`**: Optional focus area, explicit instruction, or flags.

```bash
/rpi-learn                                # reflect on entire conversation (project memory)
/rpi-learn "the Snowflake debugging"      # focus on specific topic
/rpi-learn "remember: always use bun"     # explicit memory save
/rpi-learn --global                       # save learnings to ~/.claude/ (all projects)
/rpi-learn --global "remember: use haiku for research agents"
```

### Flags

| Flag | Effect |
|------|--------|
| `--global` | Write to `~/.claude/memory/` (user-level, applies to ALL projects) instead of the project auto-memory directory |
| *(default)* | Write to `~/.claude/projects/{project}/memory/` (project-level, applies to THIS project only) |

**When to use `--global`**: Preferences that apply everywhere — tool habits, communication style, general agent strategies. If it's about YOUR workflow (not this codebase), use `--global`.

**When to use default (local)**: Codebase-specific knowledge — project patterns, debugging insights, architecture decisions, feature conventions. If it's about THIS project, keep it local.

---

## Phase 1: Scan the Conversation

Review the full conversation history. Build a raw list of candidate learnings.

### Pre-Scan: Check Struggle History

Before scanning the conversation, check for a hook-generated learnings file:

1. Get branch name: `git branch --show-current`
2. Check if `ai-docs/{branchName}/learnings.md` exists
3. If it exists, read it. Each entry contains:
   - Timestamp and session ID
   - Transcript path (for deep-diving into specific sessions)
   - Struggle classification (tool-errors, retry-clusters, user-rejections, user-corrections)
   - Metrics table with counts and struggled tool names

Use this as a **prioritization signal**: sessions flagged with struggles are higher-value targets for learning extraction. The classifications tell you WHERE to look — e.g., "retry-clusters (3 clusters)" means agents repeated the same tool call without progress; "user-rejections (4 rejections)" means the user had to cancel agent actions.

If transcript paths are listed, dispatch a background agent to read and summarize the flagged transcripts. Cross-reference what the hook detected with what actually happened — the hook's heuristics are coarse (e.g., 3 sequential `Read` calls count as a "retry cluster" even when they're normal), so validate before treating metrics as ground truth.

### What to Look For

Scan for these signal types (in priority order):

| Signal | What It Means | Example |
|--------|--------------|---------|
| **Mistake corrected** | Something went wrong and was fixed | Wrong mock strategy, incorrect API call, bad file path |
| **Unexpected behavior** | Reality differed from expectation | API returned different format, test needed different setup |
| **Pattern discovered** | A reusable approach was found | "This codebase uses X pattern for Y" |
| **Tool/command that worked** | A specific command solved a problem | `dotnet test --filter` syntax, git worktree command |
| **Convention confirmed** | A project rule was encountered in practice | Naming pattern, folder structure, test organization |
| **Debugging insight** | Root cause of a tricky issue | "The 429 was caused by 8 parallel agents hitting rate limits" |
| **User preference stated** | User explicitly said how they want things done | "Always use haiku for research agents" |
| **Decision made** | An architectural or design choice was settled | "We chose SQLite over Postgres for local memory" |

### What to Skip

- Things that are already in CLAUDE.md
- Generic knowledge not specific to this project/user
- Unfinished work or open questions (unless labeled as such)
- Speculative improvements that weren't tested

### If `$ARGUMENTS` Specifies a Focus

Narrow the scan to the relevant portion of the conversation. Still capture other high-signal learnings if they're clearly important, but prioritize the focus area.

### If `$ARGUMENTS` Is an Explicit Save

Format: "remember: {thing to remember}"

Skip the full scan. Directly capture the explicit instruction as a user preference. Go straight to Phase 3.

---

## Phase 1.5: Prune Stale Memories

Run automatically on every invocation. Scan existing memory files for entries that should be removed.

### Pruning Criteria

| Type | Rule |
|------|------|
| **Date-stale** | Session date older than 60 days with no evidence of being referenced or reconfirmed |
| **Contradicted** | Conflicts with a newer entry or current CLAUDE.md content |
| **Duplicated** | Says the same thing as another entry, or overlaps with CLAUDE.md |
| **Obsolete** | References files, features, or patterns that no longer exist in the codebase |

### Process

1. Read all existing topic files in the memory directory
2. For each entry, evaluate against the four criteria above
3. Build a list of pruning candidates with the reason for each
4. Carry this list forward to Phase 3 (presented alongside new learnings for approval)

If no pruning candidates are found, skip this section in Phase 3. If `$ARGUMENTS` is "prune" — skip the conversation scan (Phase 1) and only run this phase, then jump to Phase 3.

---

## Phase 2: Categorize & Compress

Take the raw list from Phase 1. Categorize each learning into one of these memory types:

### Memory Categories

| Category | Topic File | What Goes Here |
|----------|-----------|----------------|
| **Mistakes & Fixes** | `mistakes.md` | Errors made, root causes, how they were fixed, how to prevent recurrence |
| **Debugging** | `debugging.md` | Diagnostic approaches that worked, tricky issues and their root causes |
| **Patterns** | `patterns.md` | Reusable approaches, architectural patterns, code conventions discovered |
| **Tools & Commands** | `tools.md` | Commands, flags, syntax that worked for specific tasks |
| **User Preferences** | `preferences.md` | How the user wants things done, workflow choices, communication style |
| **Decisions** | `decisions.md` | Architectural/design choices made and their rationale |
| **Project Knowledge** | `project.md` | Codebase-specific facts: key files, gotchas, undocumented behaviors |

### Compression Format

Each learning follows this template:

```markdown
### {Short descriptive title}
{1-3 line description of what was learned}
- **Context**: {What we were doing when this came up}
- **Evidence**: {What confirmed this — test result, error message, user statement}
```

For mistakes, add:
```markdown
- **Root cause**: {Why it happened}
- **Prevention**: {How to avoid it next time}
```

### Deduplication

Read existing topic files (if they exist). If a learning is already captured:
- **Same learning, more detail** → Update the existing entry
- **Same learning, same detail** → Skip it
- **Contradicts existing** → Flag for user review

---

## Phase 3: Present for Approval

Show the user what will be saved BEFORE writing anything.

```
Learnings from this session:

📁 mistakes.md ({N} new)
  - {title}: {one-line summary}

📁 debugging.md ({N} new)
  - {title}: {one-line summary}

📁 patterns.md ({N} new, {M} updated)
  - {title}: {one-line summary}

📁 tools.md ({N} new)
  - {title}: {one-line summary}

📁 preferences.md ({N} new)
  - {title}: {one-line summary}

📁 MEMORY.md index updates:
  - {lines to add/update}

🗑️ Stale memories to prune:
  - [{topic-file}.md] "{title}" — reason: {stale/contradicted/duplicate/obsolete}
  - [{topic-file}.md] "{title}" — reason: {stale/contradicted/duplicate/obsolete}

Skipped ({N}):
  - {reason}: {what was skipped}

Save these learnings and apply pruning?
```

Wait for user approval. User can:
- Approve all
- Remove specific items
- Add items they noticed
- Rephrase items

---

## Phase 4: Write to Memory

### Step 1: Determine Memory Location

**If `--global` flag is present:**

```
~/.claude/memory/
├── MEMORY.md              # Global index (loaded every session, all projects)
├── mistakes.md            # Cross-project errors and fixes
├── tools.md               # Commands and syntax that work everywhere
├── preferences.md         # User workflow preferences (all projects)
└── strategies.md          # General agent strategies and approaches
```

Target: `~/.claude/memory/`. Create the directory if it doesn't exist.

Global memories are for things that transcend any single project — tool preferences, agent interaction patterns, general debugging strategies, communication style.

**If default (no flag):**

```
~/.claude/projects/{project-path}/memory/
├── MEMORY.md              # Project index (loaded every session for THIS project)
├── mistakes.md            # Errors and their fixes
├── debugging.md           # Diagnostic insights
├── patterns.md            # Reusable approaches
├── tools.md               # Commands and syntax
├── preferences.md         # Project-specific workflow preferences
├── decisions.md           # Architectural choices
└── project.md             # Codebase-specific knowledge
```

Resolve the actual path by finding the auto-memory directory for the current project:

```bash
# The auto-memory directory for this project (derived from working directory path)
# Pattern: ~/.claude/projects/{path-with-dashes}/memory/
```

If the directory doesn't exist, create it at the standard auto-memory location for the current project.

### Routing Rules

When categorizing learnings, apply these routing rules if `--global` is NOT set (default local mode):

| Learning Type | Stays Local | Suggest `--global` Instead |
|--------------|-------------|---------------------------|
| Codebase patterns, conventions | Yes | - |
| Debugging insights for this project | Yes | - |
| Architecture decisions | Yes | - |
| Feature-specific knowledge | Yes | - |
| General tool preferences ("use haiku for X") | - | Yes |
| Communication style preferences | - | Yes |
| Cross-project agent strategies | - | Yes |
| User workflow habits (not project-specific) | - | Yes |

If a learning would be better as global, note it in the approval step: "This looks like a global preference. Want me to save it to `~/.claude/memory/` instead? Re-run with `--global`."

### Step 2: Write Topic Files

For each category with new learnings:

1. **Read the existing topic file** (if it exists)
2. **Append new learnings** at the end, under a date header:
   ```markdown
   ## Session: YYYY-MM-DD

   ### {Learning title}
   ...
   ```
3. **Update existing entries** if the new learning adds detail to a previous one
4. **Create the file** if it doesn't exist yet, with a header:
   ```markdown
   # {Category}: {Project Name}

   Learnings captured from development sessions.

   ## Session: YYYY-MM-DD

   ### {First learning}
   ...
   ```

### Step 3: Update MEMORY.md Index

MEMORY.md is the index that loads every session. Keep it under 200 lines.

**Structure**:
```markdown
# Project Memory

## Quick Reference
- {Most important facts — build commands, key conventions, critical gotchas}

## Recent Learnings
- [{date}] {one-line summary} → see {topic-file}.md

## Topic Files
- `mistakes.md` — {N} entries
- `debugging.md` — {N} entries
- `patterns.md` — {N} entries
- `tools.md` — {N} entries
- `preferences.md` — {N} entries
- `decisions.md` — {N} entries
- `project.md` — {N} entries
```

**Rules for MEMORY.md**:
- Only the most important learnings get a line in Quick Reference
- Recent Learnings is a rolling log — move old entries to "Archived" or remove when topic file has the detail
- If approaching 200 lines, compress: merge similar items, remove redundancy, move details to topic files

### Step 4: Apply Pruning

For each approved pruning candidate:

1. Read the topic file containing the stale entry
2. Remove the entry (the `### {title}` heading and its content, up to the next heading or end of section)
3. If removing the entry leaves an empty `## Session: YYYY-MM-DD` section, remove that section header too
4. Write the updated file

### Step 5: Verify

Read back what was written. Confirm:
- [ ] Topic files have the full new learnings
- [ ] Pruned entries are removed
- [ ] MEMORY.md index is under 200 lines
- [ ] No duplicates introduced
- [ ] Existing content was not accidentally deleted

---

## Phase 6: Report

```
/rpi-learn complete

Saved {N} learnings across {M} topic files:
  mistakes.md:    {N} new entries
  debugging.md:   {N} new entries
  patterns.md:    {N} new, {M} updated
  tools.md:       {N} new entries
  preferences.md: {N} new entries
  decisions.md:   {N} new entries
  project.md:     {N} new entries

Pruned {P} stale entries:
  - [{topic-file}.md] "{title}" — {reason}

MEMORY.md: {current line count}/200 lines

Skipped: {N} (already known or unconfirmed)

These learnings will be available in future sessions.
```

---

## Special Modes

### Explicit Save Mode

When `$ARGUMENTS` starts with "remember:" — skip the conversation scan:

1. Parse the instruction after "remember:"
2. Categorize it (usually `preferences.md` or `project.md`)
3. Write directly (still show user what will be saved)

### Mistake Focus Mode

When `$ARGUMENTS` mentions "mistakes" or "errors" — prioritize the mistake scan:

1. Find every instance where something went wrong in the conversation
2. For each: identify root cause, fix applied, prevention strategy
3. Write to `mistakes.md` with prevention rules
4. If a prevention rule is general enough, suggest adding it to CLAUDE.md

### Prune-Only Mode

When `$ARGUMENTS` is "cleanup" or "prune":

1. Skip Phase 1 (conversation scan) — go directly to Phase 1.5 (Prune Stale Memories)
2. Present pruning candidates for approval (Phase 3, pruning section only)
3. Remove approved entries and update MEMORY.md index

---

## Principles

1. **Memory is a token budget.** Every line in MEMORY.md costs tokens every session. Earn that space by being concise and high-signal.
2. **Confirmed over speculative.** Only persist what actually happened and was verified. Hypotheses get labeled as such.
3. **Compress, don't hoard.** Three lines that capture the essence beat thirty lines of raw transcript.
4. **Mistakes are the highest-value memories.** A prevented repeat mistake saves more time than any other type of learning.
5. **The user owns their memory.** Always present before writing. Never silently modify memory files.
6. **Compound improvement.** Each session's learnings make future sessions better. The goal is an agent that gets smarter about THIS project over time.
