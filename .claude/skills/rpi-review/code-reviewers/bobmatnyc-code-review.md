---
description: "Performance + Architectural code review with quantitative metrics (adapted from bobmatnyc/ai-code-review)"
argument-hint: "[file-or-directory]"
---

# Code Review: Performance + Architecture Analysis

Adapted from [bobmatnyc/ai-code-review](https://github.com/bobmatnyc/ai-code-review) prompt templates (`performance-review.hbs`, `architectural-review.hbs`).

---

## Target

- `$ARGUMENTS`: File or directory to review (defaults to changed files on current branch vs default branch)

If no argument provided, get the changed files:
```bash
BASE_BRANCH=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')
BASE_BRANCH=${BASE_BRANCH:-main}
git diff --name-only "$BASE_BRANCH"...HEAD
```

Read every target file before analysis.

---

## Part 1: Performance Analysis

You are an expert performance engineer. Perform a systematic performance analysis using quantitative metrics.

### 1.1 Algorithmic Complexity Analysis
- Analyze time complexity (Big O notation) for key algorithms
- Evaluate space complexity and memory usage patterns
- Identify inefficient data structure choices (List where HashSet would be O(1))
- Flag computational bottlenecks in hot paths

### 1.2 Resource Utilization Assessment
- Memory allocation patterns: unnecessary allocations, boxing, LINQ in loops
- I/O operations efficiency: batching opportunities, buffering
- Resource pooling: HttpClient via IHttpClientFactory, connection pooling
- IDisposable/IAsyncDisposable cleanup on all code paths (including exceptions)

### 1.3 Concurrency & Async Patterns
- `async void` outside event handlers
- Sync-over-async: `.Result`, `.Wait()`, `.GetAwaiter().GetResult()`
- Missing `CancellationToken` propagation
- Lock contention and synchronization bottlenecks
- `ConcurrentDictionary.GetOrAdd` with async factory delegate

### 1.4 Data Access & I/O Optimization
- N+1 query detection (database calls inside loops)
- Multiple enumeration of `IEnumerable<T>` / `IQueryable<T>`
- `Count() > 0` instead of `Any()`
- Missing caching for frequently accessed data
- Serialization/deserialization overhead in critical paths

### 1.5 Scalability Characteristics
- Horizontal scaling readiness (stateless design)
- Resource limits and behavior at boundaries
- Graceful degradation under stress

---

## Part 2: Architectural Analysis

You are a senior software architect. Evaluate system design using SOLID principles and coupling metrics.

### 2.1 SOLID Principles Evaluation
- **Single Responsibility**: Each class/module has one reason to change
- **Open/Closed**: Open for extension, closed for modification
- **Liskov Substitution**: Derived classes are substitutable for base classes
- **Interface Segregation**: Focused interfaces, not god-interfaces
- **Dependency Inversion**: Depend on abstractions, not concretions

### 2.2 Coupling & Cohesion
- Afferent coupling (Ca): How many things depend on this
- Efferent coupling (Ce): How many things this depends on
- Circular dependencies between features/modules
- Cross-feature boundary violations (feature A directly accessing internals of feature B)
- Layer violations (controller calling repository directly, skipping service layer)

### 2.3 Design Pattern Analysis
- Appropriate use of design patterns (not over-engineered)
- Missing patterns that would improve design
- Pattern misuse or anti-patterns
- Consistency with existing codebase patterns

### 2.4 Dependency Architecture
- DI service lifetime correctness (scoped-in-singleton violations)
- Dependency direction alignment (dependencies flow inward)
- Feature registration pattern compliance (IFeature, extension methods)
- Reinventing existing utilities vs reusing shared code

### 2.5 Error Handling Architecture
- Error handling strategy consistency across the codebase
- Error propagation and recovery patterns
- Resilience patterns (circuit breaker, retry, timeout) on external calls
- Fallback behavior when dependencies are unavailable

---

## Output Format

For each finding, provide:

```
### [PERF-001 | ARCH-001] Title

**Severity**: CRITICAL | HIGH | MEDIUM | LOW
**Confidence**: HIGH | MEDIUM | LOW
**File**: path/to/file.cs:line
**Category**: algorithmic | memory | concurrency | io | coupling | solid | pattern | resilience

**Issue**: What is wrong and why it matters

**Current**:
{code snippet showing the problem}

**Recommended**:
{code snippet showing the fix}

**Impact**: Quantitative when possible (e.g., "O(n^2) -> O(n)", "eliminates N+1 query", "reduces coupling from 12 to 3")
**Effort**: Quick | Medium | Large
```

---

## Summary

End with:

```
## Performance + Architecture Review Summary

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Algorithmic | | | | |
| Memory/Resource | | | | |
| Concurrency | | | | |
| Data Access | | | | |
| SOLID Violations | | | | |
| Coupling | | | | |
| Design Patterns | | | | |
| Resilience | | | | |

**Overall Performance Risk**: CRITICAL | HIGH | MEDIUM | LOW
**Overall Architecture Risk**: CRITICAL | HIGH | MEDIUM | LOW

### Top 3 Performance Fixes (by impact)
1. ...
2. ...
3. ...

### Top 3 Architecture Fixes (by impact)
1. ...
2. ...
3. ...
```

---

## Attribution

Based on prompt templates from [bobmatnyc/ai-code-review](https://github.com/bobmatnyc/ai-code-review) (MIT License).
