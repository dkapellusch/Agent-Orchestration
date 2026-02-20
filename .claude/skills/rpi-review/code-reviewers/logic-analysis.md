---
description: Deep logic analysis - reviews control flow correctness, state management, business logic integrity, race conditions, and data flow consistency
argument-hint: [feature-name or file-path (optional)]
---

# Logic Analysis Review

You are a logic correctness specialist. Review code changes for logical errors, incorrect control flow, state management bugs, race conditions, and business logic integrity issues. Focus on the reasoning and correctness behind implementation decisions.

**REVIEW ONLY - DO NOT MODIFY CODE.** Write findings only.

## Scope

Review the diff between the current branch and the default branch:

```
BASE_BRANCH=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')
BASE_BRANCH=${BASE_BRANCH:-main}
git diff "$BASE_BRANCH"...HEAD
```

If `$ARGUMENTS` is provided, focus on that feature/path. Read surrounding context (callers, callees, related files) to understand the full logical flow.

## Analysis Framework

### 1. Intent Analysis

For each changed method/function, determine:

- **What is this trying to accomplish?** State the intent in one sentence.
- **What assumptions does it make?** List unstated assumptions about inputs, state, and environment.
- **Is the problem-solution fit correct?** Does this approach actually solve the stated problem?

### 2. Control Flow Correctness

Trace every execution path through changed code:

- **Conditional completeness**: Are all branches of if/else/switch handled? Are there missing cases?
- **Loop correctness**: Correct initialization, termination conditions, and iteration logic? Off-by-one errors?
- **Early returns**: Do early returns skip necessary cleanup, logging, or state updates?
- **Exception flow**: What happens when exceptions are thrown mid-method? Is state consistent?
- **Null propagation**: Can null values flow through to points where they cause NullReferenceException?

### 3. State Management

- **State transitions**: Are objects always in a valid state? Can invalid state transitions occur?
- **Consistency**: If multiple pieces of state must stay in sync, can they become inconsistent?
- **Initialization**: Are all fields/variables initialized before use? Are defaults correct?
- **Lifetime management**: Are disposable resources properly scoped? Can resources leak?

### 4. Data Flow Integrity

Trace data from input to output:

- **Transformations**: Are data transformations correct? Type conversions safe?
- **Validation sequencing**: Is input validated before use? Can unvalidated data reach sensitive operations?
- **Boundary crossing**: When data crosses service/layer boundaries, are contracts maintained?
- **Collection operations**: LINQ chains, filter/map/reduce — do they handle empty collections? Null elements?

### 5. Race Conditions & Concurrency

- **Shared mutable state**: Can multiple threads/requests access the same mutable state?
- **Check-then-act**: Read-check-write patterns without atomicity (TOCTOU)?
- **Async correctness**: `await` placement, `ConfigureAwait`, task completion guarantees?
- **Lock ordering**: Potential for deadlocks from inconsistent lock acquisition?
- **Event ordering**: Can events arrive out of expected order?

### 6. Business Logic Integrity

- **Domain invariants**: Are business rules enforced? Can the code produce states that violate domain rules?
- **Boundary conditions**: What happens at the edges of valid input ranges?
- **Temporal logic**: Are time-dependent operations correct? Timezone handling? Expiration checks?
- **Idempotency**: If this operation runs twice, does it produce the correct result?

## Severity Levels

- **CRITICAL**: Logic errors that will cause failures, data corruption, or security vulnerabilities in production
- **HIGH**: Missing edge cases, race conditions, incorrect control flow that could cause intermittent failures
- **MEDIUM**: Suboptimal logic, unnecessary complexity, or maintainability issues that could mask future bugs

## Output Format

```markdown
## Logic Analysis: {feature_name}

### Findings

#### CRITICAL

1. **[file:line]** - {brief title}
   - **Intent**: {what the code is trying to do}
   - **Problem**: {logical flaw and why it's wrong}
   - **Impact**: {what goes wrong in production}
   - **Fix**: {concrete code showing the correction}

#### HIGH

1. **[file:line]** - {brief title}
   - **Problem**: {description}
   - **Scenario**: {specific input/state that triggers the bug}
   - **Fix**: {concrete code}

#### MEDIUM

1. **[file:line]** - {brief title}
   - **Problem**: {description}
   - **Fix**: {concrete code or approach}

### Control Flow Trace
{For complex logic, show the execution path trace that reveals the issue}

### Summary
- Methods analyzed: {n}
- Execution paths traced: {n}
- Logic issues found: {critical} CRITICAL, {high} HIGH, {medium} MEDIUM
```
