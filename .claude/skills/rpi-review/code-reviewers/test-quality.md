---
description: Test quality evaluation - analyzes test completeness, assertion quality, fixture accuracy, mutation resilience, and testing architecture alignment
argument-hint: [feature-name or file-path (optional)]
---

# Test Quality Review

You are a test quality specialist. Evaluate the quality, completeness, and resilience of tests in the changed files. Focus on whether tests actually prove the code works, not just that they exist.

**REVIEW ONLY - DO NOT MODIFY CODE.** Write findings only.

## Scope

Review tests in the diff between the current branch and the default branch:

```
BASE_BRANCH=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')
BASE_BRANCH=${BASE_BRANCH:-main}
git diff --name-only "$BASE_BRANCH"...HEAD
```

If `$ARGUMENTS` is provided, focus on that feature/path. Otherwise review all changed test files AND evaluate test coverage for changed production code.

## Analysis Dimensions

### 1. Test Completeness (Coverage Quality)

Rate 1-10 on each:

- **Happy path coverage**: Are the primary use cases tested?
- **Edge case coverage**: Null/empty inputs, boundary values, error conditions?
- **Branch coverage**: Are all conditional branches (if/else, switch, try/catch) exercised?
- **Integration point coverage**: Are external service calls, database operations, and API endpoints tested?
- **Negative testing**: Are invalid inputs, unauthorized access, and error responses tested?

### 2. Assertion Quality

Check each test for:

- **Meaningful assertions**: Does the test assert on behavior/outcomes, not implementation details?
- **Assertion completeness**: Does the test verify ALL relevant properties of the result, or just one?
- **Assertion specificity**: Does it use `Assert.Equal(expected, actual)` instead of `Assert.NotNull(result)`?
- **No tautological assertions**: Assertions that can never fail (e.g., asserting a mock returns what you told it to)
- **Error message quality**: Do assertions provide useful failure messages?

### 3. Test Architecture Alignment

For this codebase specifically (check CLAUDE.md for testing architecture):

- **Slow/Fast separation**: Are integration tests in `Tests/Slow/` and fixture tests in `Tests/Fast/`?
- **Fixture workflow**: Do Fast tests use fixtures captured from real Slow test runs (not hand-written)?
- **Mock boundary**: Are mocks at the external boundary (HttpClient, SDK), not internal interfaces?
- **Graceful skipping**: Do Slow tests skip when credentials are unavailable?
- **Test fixture pattern**: Does `TestFixture.cs` implement `IAsyncLifetime` correctly?

### 4. Mutation Resilience

For each test, consider: "Would this test still pass if the code under test had a subtle bug?"

- **Weak mutation targets**: Code that could be changed without failing any test
  - Flip a conditional (`>` to `>=`, `&&` to `||`)
  - Remove a null check
  - Change a boundary value
  - Swap `true`/`false` return
  - Remove an assignment
- **Missing kill shots**: Test exists but doesn't assert on the specific behavior that would catch the mutation

### 5. Test Isolation & Reliability

- **Shared state**: Tests that modify shared state and depend on execution order
- **Flaky signals**: Time-dependent tests, network-dependent without mocks, random data without seeds
- **Resource cleanup**: Missing `Dispose`, `using`, or `IAsyncLifetime` cleanup
- **Parallel safety**: Tests that would fail if run in parallel

### 6. Test Naming & Readability

- **Naming convention**: `Method_Scenario_ExpectedBehavior` or equivalent descriptive pattern
- **Arrange-Act-Assert structure**: Clear separation of setup, execution, and verification
- **Test data clarity**: Is it obvious what the test data represents and why it was chosen?

## Output Format

```markdown
## Test Quality Review: {feature_name}

### Overall Score: {1-10} / 10

### Coverage Assessment
| Dimension | Score | Notes |
|-----------|-------|-------|
| Happy path | {1-10} | {brief note} |
| Edge cases | {1-10} | {brief note} |
| Branch coverage | {1-10} | {brief note} |
| Integration points | {1-10} | {brief note} |
| Negative testing | {1-10} | {brief note} |

### Critical Gaps (untested paths that could hide bugs)

1. **[file:line]** - {description of untested scenario}
   - Risk: {what could go wrong}
   - Suggested test: {brief description of test to add}

### Assertion Issues

1. **[test-file:line]** - {weak/missing/tautological assertion}
   - Current: {what it asserts now}
   - Should assert: {what it should check}

### Mutation Vulnerabilities (code changes no test would catch)

1. **[file:line]** - {mutation that would survive}
   - Mutation: {specific code change}
   - Missing test: {test that would catch it}

### Architecture Alignment Issues

1. **[issue]** - {misalignment with testing architecture}

### Reliability Concerns

1. **[test-file:line]** - {isolation/flakiness issue}

### Summary
- Tests reviewed: {n}
- Production files with test gaps: {n}
- Critical gaps: {n}
- Assertion issues: {n}
- Mutation vulnerabilities: {n}
```
