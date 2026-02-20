---
description: "11-point performance audit across algorithms, database, network, memory, and async patterns (adapted from qdhenry/Claude-Command-Suite)"
argument-hint: "[file-or-directory]"
---

# Performance Audit

Adapted from [qdhenry/Claude-Command-Suite](https://github.com/qdhenry/Claude-Command-Suite) (`performance/performance-audit.md`).

---

## Target

- `$ARGUMENTS`: File or directory to audit (defaults to changed files on current branch vs default branch)

If no argument provided, get the changed files:
```bash
BASE_BRANCH=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')
BASE_BRANCH=${BASE_BRANCH:-main}
git diff --name-only "$BASE_BRANCH"...HEAD
```

Read every target file before analysis.

---

## 1. Technology Stack Analysis
- Identify the primary language, framework, and runtime environment
- Review build tools and optimization configurations
- Check for performance monitoring tools already in place (Serilog, OpenTelemetry, etc.)

## 2. Code Performance Analysis
- Identify inefficient algorithms and data structures
- Look for nested loops and O(n^2) operations
- Check for unnecessary computations and redundant operations
- Review memory allocation patterns and potential leaks
- Flag LINQ in hot paths (boxing, closures, multiple enumeration)

## 3. Database Performance
- Analyze database queries for efficiency
- Check for missing indexes and slow queries
- Review connection pooling and database configuration
- Identify N+1 query problems and excessive database calls
- Check for Entity Framework anti-patterns (tracking when not needed, client-side evaluation)

## 4. Network Performance
- Review API call patterns and caching strategies
- Check for unnecessary network requests
- Analyze payload sizes and compression
- Check for missing retry policies and circuit breakers on external calls
- Review timeout configurations

## 5. Asynchronous Operations
- Review async/await usage patterns
- Flag sync-over-async: `.Result`, `.Wait()`, `.GetAwaiter().GetResult()`
- Flag `async void` outside event handlers
- Check for blocking operations in async paths
- Check `CancellationToken` propagation through call chains
- Identify opportunities for parallel execution (`Task.WhenAll`)

## 6. Memory Usage
- Check for memory leaks and excessive memory consumption
- Review IDisposable/IAsyncDisposable implementation and `using` patterns
- Analyze object lifecycle and cleanup on ALL code paths (including exceptions)
- Identify large objects and unnecessary data retention
- Check for HttpClient created per-request instead of via IHttpClientFactory

## 7. Resource Pooling & Connection Management
- Database connection pool sizing
- HttpClient lifecycle management
- Thread pool configuration appropriateness
- Semaphore and rate limiter usage

## 8. Caching Strategy
- Evaluate existing caching and cache hit rates
- Identify hot data that should be cached
- Review cache eviction policies
- Check for cache stampede vulnerability
- Assess distributed vs in-memory caching needs

## 9. Serialization & Data Transfer
- Review JSON serialization settings (System.Text.Json vs Newtonsoft)
- Check for unnecessary serialization in hot paths
- Evaluate data transfer object sizes
- Check for streaming opportunities on large payloads

## 10. Performance Monitoring
- Check existing performance metrics and monitoring
- Identify key performance indicators to track
- Review alerting and performance thresholds
- Suggest performance testing strategies

## 11. Optimization Recommendations
- Prioritize optimizations by impact and effort
- Provide specific code examples and alternatives
- Suggest architectural improvements for scalability
- Recommend appropriate performance tools and libraries

---

## Output Format

For each finding:

```
### PERF-{NNN}: {Title}

**Severity**: CRITICAL | HIGH | MEDIUM | LOW
**Category**: algorithm | database | network | async | memory | caching | serialization
**File**: path/to/file.cs:line
**Impact**: {Quantitative: e.g., "O(n^2) -> O(n log n)", "eliminates 50 queries per request"}

**Issue**: {What is wrong}

**Current**:
{code snippet}

**Recommended**:
{code snippet}

**Effort**: Quick (<1hr) | Medium (1-4hr) | Large (>4hr)
```

---

## Summary

```
## Performance Audit Summary

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Algorithms & Data Structures | | | | |
| Database | | | | |
| Network & I/O | | | | |
| Async Patterns | | | | |
| Memory & Resources | | | | |
| Caching | | | | |
| Serialization | | | | |

**Overall Performance Risk**: CRITICAL | HIGH | MEDIUM | LOW

### Top 5 Optimizations (ranked by impact / effort)
1. ...
2. ...
3. ...
4. ...
5. ...
```

Include specific file paths, line numbers, and measurable metrics where possible. Focus on high-impact, low-effort optimizations first.

---

## Attribution

Based on [qdhenry/Claude-Command-Suite](https://github.com/qdhenry/Claude-Command-Suite) (MIT License).
