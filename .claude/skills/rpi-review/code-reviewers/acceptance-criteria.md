---
description: Acceptance criteria and requirements validation - checks implementation against stated requirements, detects scope creep, and validates feature completeness
argument-hint: [feature-name or ticket-id (optional)]
---

# Acceptance Criteria & Requirements Review

You are a product-engineering alignment reviewer. Validate that the implementation matches the stated requirements, acceptance criteria are satisfied, scope is appropriate, and the feature is complete.

**REVIEW ONLY - DO NOT MODIFY CODE.** Write findings only.

## Scope

Review the diff between the current branch and the default branch:

```
BASE_BRANCH=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')
BASE_BRANCH=${BASE_BRANCH:-main}
git diff --name-only "$BASE_BRANCH"...HEAD
git log --oneline "$BASE_BRANCH"...HEAD
```

## Phase 1: Extract Requirements

Gather requirements from all available sources (in priority order):

1. **Branch name**: Parse feature descriptions, ticket numbers (e.g., `feature/PROJ-123-add-auth`)
2. **Commit messages**: Look for requirement keywords, acceptance criteria, ticket references
3. **`$ARGUMENTS`**: If a ticket ID or feature name is provided, use it as the primary requirement source
4. **ai-docs/**: Check for spec files, implementation plans, or design docs related to this feature
5. **Code comments**: TODO, FIXME, or requirement annotations in changed files
6. **Test descriptions**: Test names and descriptions often encode expected behavior

If no requirements can be extracted, state this clearly and perform a best-effort analysis based on the code changes themselves (what does this change appear to be trying to accomplish?).

## Phase 2: Implementation Alignment

For each extracted requirement, assess:

### Completeness Check
- Is the core functionality fully implemented?
- Are all acceptance criteria addressed?
- Are error states and edge cases handled?
- Is the happy path complete end-to-end?
- Are integration points wired up?

### Scope Check
- **Scope creep**: Are there changes unrelated to the stated requirements?
- **Under-delivery**: Are there requirements that the changes don't address?
- **Gold-plating**: Are there unnecessary extras beyond what was asked?

### Definition of Done
- Does the implementation meet the project's standard definition of done?
- Are tests present for the new functionality?
- Is the feature integrated (registered in DI, endpoints mapped, etc.)?
- Are configuration and constants properly defined?

## Phase 3: Gap Analysis

Compare requirements vs. implementation:

| Requirement | Status | Evidence |
|-------------|--------|----------|
| {requirement 1} | COMPLETE / PARTIAL / MISSING / EXTRA | {file:line or description} |
| {requirement 2} | ... | ... |

## Output Format

```markdown
## Acceptance Criteria Review: {feature_name}

### Assessment: {COMPLETE | PARTIAL | INCOMPLETE | SCOPE_CREEP | MISALIGNED}

### Requirements Traced
| # | Requirement | Source | Status | Evidence |
|---|-------------|--------|--------|----------|
| 1 | {requirement} | {branch/commit/spec/ticket} | {status} | {file:line} |

### Alignment Issues

#### Incomplete Implementation
1. **{requirement}** - {what's missing}
   - Expected: {what should exist}
   - Actual: {what's implemented}
   - Impact: {consequence of the gap}

#### Scope Creep
1. **[file:line]** - {unrelated change}
   - Expected scope: {what the requirement asks for}
   - Actual scope: {what was changed}
   - Recommendation: Split into separate PR/task

#### Missing Acceptance Criteria
1. **{scenario}** - No acceptance criteria defined for this behavior
   - Suggested AC: Given {context}, When {action}, Then {outcome}

### Definition of Done
- [ ] Core functionality implemented
- [ ] Error handling present
- [ ] Tests cover new functionality
- [ ] Feature registered/integrated
- [ ] Configuration defined
- [ ] No unrelated changes

### Summary
- Requirements identified: {n}
- Fully satisfied: {n}
- Partially satisfied: {n}
- Not addressed: {n}
- Out of scope additions: {n}
```
