---
name: rpi-cleanup
description: Post-implementation cleanup — runs all available linters, formatters, and static analyzers, then dispatches parallel audit agents to find dead ends, hardcoded strings, convention violations, and AI slop. Consensus-verified findings get fixed. Produces production-grade code.
---

# /rpi-cleanup — Post-Implementation Cleanup & De-Slop

Implementation is BFS through a problem space. You explore paths, backtrack, try alternatives. The result works but carries dead ends: unused imports, hardcoded strings, debugging leftovers, verbose patterns, convention drift. This skill roots them out.

Run every automated tool the project has. Then dispatch agents to find what tools can't. Fix everything. Verify the code is production-grade.

---

## Critical Rules

- **You are the orchestrator. You do not write code.** Delegate all fixes to agents.
- **Tools first, agents second.** Automated tools are fast and objective. Run them before spending agent tokens on things a formatter could fix.
- **Consensus required for agent findings.** Two agents independently audit. A finding enters the fix list only if both agents report it, or you verify it against project conventions yourself.
- **Every fix must pass tests.** Run the test suite after each fix batch. If a fix breaks tests, revert it. ALL tests must pass before and after cleanup — no exceptions.
- **Don't gold-plate.** Fix what's wrong. Don't "improve" working code that meets conventions.
- **The spec is the scope boundary.** Only clean up files created or modified by the implementation.

---

## Input

**`$ARGUMENTS`**: Optional path to the spec or plan file. Used to scope which files to audit.

```bash
/rpi-cleanup                                    # defaults to ai-docs/{branchName}/spec.md
/rpi-cleanup "ai-docs/my-feature/spec.md"        # explicit path
```

**Default**: If `$ARGUMENTS` is empty, derive from branch: `ai-docs/{branchName}/spec.md`. If that doesn't exist, warn but continue — scope to all uncommitted changes instead.

---

## Phase 1: Load Context & Scope

### 1a: Read Inputs

1. Read the spec/plan file (if it exists) — extract the list of files created/modified
2. Run `git diff --name-only` against the branch base to get the actual changed files
3. Read CLAUDE.md / README.md in the project root and any affected feature folders
4. Read `.editorconfig` if it exists
5. Identify the language(s) from file extensions (`.cs`, `.ts`, `.py`, `.go`, `.rs`, etc.)

### 1b: Discover & Record Available Tools

**Probe the environment for every tool that could help.** Run each check command — if it succeeds, record it. Skip gracefully if not. Only probe tools relevant to the detected language(s).

| Category | Tool | Check | Languages |
|----------|------|-------|-----------|
| **Format** | `dotnet format` | `dotnet format --version` | C# |
| | `prettier` | `npx prettier --version` | JS/TS/CSS/HTML/JSON |
| | `black` | `black --version` | Python |
| | `ruff format` | `ruff --version` | Python |
| | `gofmt` | `gofmt -h` | Go |
| | `rustfmt` | `rustfmt --version` | Rust |
| **Lint/Fix** | `dotnet jb cleanupcode` | `dotnet jb --version` | C# |
| | `eslint --fix` | `npx eslint --version` | JS/TS |
| | `biome check --fix` | `npx biome --version` | JS/TS/JSON |
| | `ruff check --fix` | `ruff --version` | Python |
| | `cargo clippy --fix` | `cargo clippy --version` | Rust |
| **Build/Type** | `dotnet build` | (always for .NET) | C# |
| | `tsc --noEmit` | `npx tsc --version` | TypeScript |
| | `mypy` | `mypy --version` | Python |
| | `go vet` | `go vet --help` | Go |
| | `cargo check` | `cargo check --help` | Rust |
| **Inspect** | `dotnet jb inspectcode` | (same as cleanupcode) | C# |
| | `eslint` (report only) | (same as above) | JS/TS |
| | `ruff check` (report only) | (same as above) | Python |
| | `pylint` | `pylint --version` | Python |
| | `golangci-lint` | `golangci-lint --version` | Go |
| | `shellcheck` | `shellcheck --version` | Shell |
| | `hadolint` | `hadolint --version` | Dockerfile |
| **Security** | `npm audit` | `npm audit --json` | JS/TS |
| | `bandit` | `bandit --version` | Python |
| | `trivy` | `trivy --version` | Any |
| | `cargo audit` | `cargo audit --version` | Rust |
| **Test** | `dotnet test` | (always for .NET) | C# |
| | `npm test` / `jest` / `vitest` | Check `package.json` | JS/TS |
| | `pytest` | `pytest --version` | Python |
| | `go test` | `go test --help` | Go |
| | `cargo test` | `cargo test --help` | Rust |

Also check for project-specific tooling:
- `scripts/` folder, `package.json` scripts, `Makefile` / `Taskfile.yml` / `justfile` targets
- `.githooks/`, `.husky/`, `.pre-commit-config.yaml`
- `tox.ini`, `setup.cfg`, `pyproject.toml`, `.config/dotnet-tools.json`

### 1c: Establish Baseline

Run the project's test suite on the affected area. **If tests fail BEFORE cleanup: STOP.** Report failures. Cleanup requires a passing baseline.

---

## Phase 2: Run Automated Tools

**Run every tool recorded in Phase 1b. Capture all output.**

Execute in this order using the discovered tools:

1. **Format** — Run all discovered formatters. Safe — changes whitespace/style only.
2. **Lint/Fix** — Run fixers that go beyond formatting (organize imports, simplify expressions, remove redundancy).
3. **Build/Type** — Build the project, capture ALL warnings. Don't fail on them.
4. **Inspect** — Run static analyzers in report-only mode. Capture findings grouped by severity.
5. **Security** — Run any available security scanners.
6. **Project-specific** — Run any project-specific quality targets discovered in Phase 1b.

Assemble all output into a single findings summary:

```
Automated Tool Findings:
  Format:    {tools run} — {N} files modified
  Lint/Fix:  {tools run} — {N} files modified
  Warnings:  {N} build/type warnings (file:line list)
  Inspect:   {N} issues by severity
  Security:  {N} findings
```

---

## Phase 3: Agent-Based Code Audit

**Two agents independently audit the changed files. Dispatch both in a single message.**

### Agent A: Dead End Hunter

```
Task: "Dead end audit" | subagent_type: general-purpose
Prompt: |
  You are auditing code that was just implemented. Implementation is like BFS —
  the developer explored paths, backtracked, tried alternatives. Your job is to
  find the dead ends left behind.

  Changed files: {file list from Phase 1}
  spec/Plan: {plan file path}
  Project conventions: {CLAUDE.md content}

  For each file, read it completely and look for:

  1. **Dead code**: Unused variables, methods, imports, parameters, types.
  2. **Debugging artifacts**: Print statements, TODO/FIXME/HACK comments,
     commented-out code, temporary workarounds.
  3. **Hardcoded strings**: Magic strings that should be in constants, config,
     or environment variables.
  4. **Scope creep**: Code that doesn't trace to any requirement in the spec.
  5. **Copy-paste artifacts**: Duplicated blocks, placeholder names not updated.
  6. **Over-engineering**: Abstractions for single-use code, unnecessary
     interfaces, premature generalization.

  For every finding: file:line, category, severity (MUST-FIX / SHOULD-FIX /
  SUGGESTION), specific fix, and evidence (code snippet).

  No opinions about "improvements" — only things that are WRONG or UNNECESSARY.
```

### Agent B: Convention Enforcer

```
Task: "Convention audit" | subagent_type: general-purpose
Prompt: |
  You are auditing code against this project's specific conventions.

  Changed files: {file list from Phase 1}
  Project conventions (CLAUDE.md / README.md): {content}
  EditorConfig rules: {.editorconfig content if exists}
  Automated tool findings: {Phase 2 findings summary}

  For each file, read it completely and check:

  1. **Naming**: Do classes, methods, variables, files follow documented patterns?
  2. **Structure**: Are files in the right folders per project conventions?
  3. **Language idioms**: Does the code follow idiomatic style for its language?
     Defer to CLAUDE.md / .editorconfig over general best practices.
  4. **Documentation**: Does it match project conventions? Any WHAT-comments
     that should be removed?
  5. **Module registration**: Does it follow the project's DI / registration pattern?
  6. **Test conventions**: Locations, naming, categories, mock strategy correct?
  7. **Constants / config**: Reused strings extracted? No magic numbers?
  8. **Pattern match**: Compare against the closest similar feature. Note divergence.

  For every finding: file:line, convention violated (cite CLAUDE.md section),
  severity (MUST-FIX / SHOULD-FIX / SUGGESTION), what it should be, and evidence.

  Only flag actual convention violations — not style preferences.
```

**Wait for both agents to complete.**

---

## Phase 4: Consensus & Triage

**Cross-reference all sources. Build a prioritized fix list.**

For each finding, check how many sources reported it:

| Consensus | Classification | Action |
|-----------|---------------|--------|
| 3/3 (tools + both agents) | **MUST-FIX** | Fix immediately |
| 2/3 (any two sources) | **SHOULD-FIX** | Fix unless risky |
| 1/3 (tools only) | **AUTO-FIXED** | Already handled by Phase 2 |
| 1/3 (single agent only) | **VERIFY** | Read the code yourself. Accept only if confirmed. |
| Contradiction | **RESOLVE** | Read the code. Pick the correct interpretation. |

**Present fix plan to user before proceeding:**

```
Cleanup Scope: {N} files

Already applied: {N} format fixes, {M} lint fixes
MUST-FIX:   {N} — {summary}
SHOULD-FIX: {N} — {summary}
Verified:   {N} — {summary}
Rejected:   {N}

Proceed with fixes?
```

Wait for approval.

---

## Phase 5: Fix

**Group fixes by file. Dispatch one agent per file or related group.**

```
Task: "Fix: {file or group}" | subagent_type: general-purpose
Prompt: |
  Fix the following issues in {file path(s)}.
  Project conventions: {relevant CLAUDE.md sections}

  Fixes: {numbered list with exact line numbers and descriptions}

  Rules:
  1. Read file(s) completely before changing anything.
  2. Apply ONLY listed fixes. Do not "improve" adjacent code.
  3. Match existing style exactly.
  4. If a fix would change behavior, flag it — don't apply it.
  5. Verify the project still builds after fixes.

  Return: files changed, fixes applied, fixes skipped (with reason), build status.
```

After each batch: build + run tests. If tests fail, revert the batch. If a batch fails twice, skip it and document as "manual review needed."

---

## Phase 6: Verify & Report

1. **Re-run Phase 2 tools** — formatters should produce no changes, build should have no new warnings
2. **Run full test suite** — all tests must pass, not just feature tests
3. **Review `git diff`** — every change must trace to a Phase 4 finding

```
/rpi-cleanup complete: {feature}

Scope: {N} files audited
Tools: {list of tools that ran}

Automated: {N} format + {M} lint fixes applied
Agent findings: {N} consensus, {M} verified solo, {P} rejected
Fixes: {N} MUST-FIX, {M} SHOULD-FIX applied | {P} skipped

Verification: Build PASS | Tests {N} passed, 0 failed | Format clean
Manual review needed: {list, or "None"}

Ready for review.
```

---

## Failure Handling

| Situation | Action | Max Retries |
|-----------|--------|-------------|
| Tests fail before cleanup | **STOP.** Report failures. | 0 |
| Tool not available | Skip it. Note in report. | 0 |
| Fix breaks tests or build | Revert batch. Try individual fixes. | 2 |
| Agent finding unconfirmed | Reject it. | 0 |
| Max retries exhausted | Document as "manual review needed." | — |

---

## Principles

1. **Tools are objective, agents are opinionated.** A tool warning is a fact; an agent suggestion is a hypothesis. Run tools first, require agent consensus.
2. **Implementation leaves dead ends.** BFS through a problem space means exploring and backtracking. This skill removes the exploration artifacts and leaves only the solution.
3. **Convention compliance is binary.** Conventions are defined in CLAUDE.md and .editorconfig, not in the agent's preferences.
4. **Use what's available.** Every project has different tooling. Discover what's installed, run everything relevant, skip what's missing.
