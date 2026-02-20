---
description: "15-point architecture review covering SOLID, coupling, patterns, scalability, and extensibility (adapted from qdhenry/Claude-Command-Suite)"
argument-hint: "[file-or-directory]"
---

# Architecture Review

Adapted from [qdhenry/Claude-Command-Suite](https://github.com/qdhenry/Claude-Command-Suite) (`team/architecture-review.md`).

---

## Target

- `$ARGUMENTS`: File or directory to review (defaults to changed files on current branch vs default branch)

If no argument provided, get the changed files:
```bash
BASE_BRANCH=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')
BASE_BRANCH=${BASE_BRANCH:-main}
git diff --name-only "$BASE_BRANCH"...HEAD
```

Read every target file AND the project's CLAUDE.md / AGENTS.md for conventions before analysis.

---

## 1. High-Level Architecture Analysis
- Map out the overall system architecture and components
- Identify architectural patterns in use (vertical slice, Clean Architecture, etc.)
- Review module boundaries and separation of concerns
- Analyze the application's layered structure

## 2. Design Patterns Assessment
- Identify design patterns used throughout the changed code
- Check for proper implementation of patterns expected by the project (IFeature, primary constructors, record types)
- Look for anti-patterns and code smells
- Assess pattern consistency across the application

## 3. Dependency Management
- Review dependency injection and inversion of control
- Analyze coupling between modules and components
- Check for circular dependencies
- Assess dependency direction and adherence to dependency rule
- **DI lifetime correctness**: Scoped services injected into Singletons, Transient IDisposables

## 4. Data Flow Architecture
- Trace data flow through the application
- Review state management patterns
- Analyze data persistence and storage strategies
- Check for proper data validation and transformation at system boundaries

## 5. Component Architecture
- Review component design and responsibilities
- Check for single responsibility principle adherence
- Analyze component composition and reusability
- Assess interface design and abstraction levels
- Check for cross-feature boundary violations

## 6. Error Handling Architecture
- Review error handling strategy and consistency
- Check for proper error propagation and recovery
- Analyze logging and monitoring integration
- Assess resilience and fault tolerance patterns (circuit breaker, retry, timeout)
- Check for graceful degradation when dependencies are unavailable

## 7. Scalability Assessment
- Analyze horizontal and vertical scaling capabilities
- Review caching strategies and implementation
- Check for stateless design where appropriate
- Assess performance bottlenecks and scaling limitations

## 8. Security Architecture
- Review security boundaries and trust zones
- Check authentication and authorization architecture
- Analyze data protection and privacy measures
- Assess security pattern implementation (defense in depth)

## 9. Testing Architecture
- Review test structure and organization (Fast/Slow/E2E tiers)
- Check for testability in design (DI, interfaces at boundaries)
- Analyze mocking strategy (mock at boundary, not own interfaces)
- Assess test coverage across architectural layers

## 10. Configuration Management
- Review configuration handling and environment management
- Check for proper separation of config from code
- Analyze feature flags and runtime configuration
- Assess secrets management (KeyVault, env vars, not hardcoded)

## 11. API Contract Design
- Review API endpoint naming consistency
- Check response shape consistency across endpoints
- Assess error response format standardization
- Review pagination and filtering patterns
- Check for backward compatibility of changes

## 12. Observability Architecture
- Are new code paths instrumented with structured logging?
- Is distributed tracing context propagated through new service calls?
- Are health checks covering new components?
- Can production issues in this code be diagnosed from logs alone?

## 13. Resilience Patterns
- Are external service calls wrapped in resilience policies?
- Circuit breaker, retry with backoff, timeout on HttpClient calls?
- Idempotency of retried operations?
- Bulkhead isolation between failure domains?

## 14. Backward Compatibility
- Do changes break existing API consumers?
- Serialization format changes (renamed/removed properties on DTOs)?
- Configuration schema changes?
- Database migration reversibility?

## 15. Recommendations
- Provide specific architectural improvements
- Suggest refactoring strategies for problem areas
- Recommend patterns and practices for better design
- Create a prioritized roadmap for architectural evolution

---

## Output Format

For each finding:

```
### ARCH-{NNN}: {Title}

**Severity**: CRITICAL | HIGH | MEDIUM | LOW
**Category**: solid | coupling | pattern | dependency | resilience | scalability | compatibility | observability
**File**: path/to/file.cs:line

**Issue**: {What is wrong and why it matters architecturally}

**Current**:
{code snippet or diagram showing the problem}

**Recommended**:
{code snippet or diagram showing the fix}

**Impact**: {What breaks if this isn't fixed, what improves if it is}
**Effort**: Quick (<1hr) | Medium (1-4hr) | Large (>4hr)
```

---

## Summary

```
## Architecture Review Summary

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| SOLID Violations | | | | |
| Coupling & Boundaries | | | | |
| Design Patterns | | | | |
| DI & Dependencies | | | | |
| Resilience | | | | |
| Scalability | | | | |
| Backward Compatibility | | | | |
| Observability | | | | |
| Error Handling | | | | |

**Overall Architecture Risk**: CRITICAL | HIGH | MEDIUM | LOW

### Top 5 Architecture Improvements (ranked by impact)
1. ...
2. ...
3. ...
4. ...
5. ...
```

Focus on actionable insights with specific examples and clear rationale. Every recommendation should trace back to a concrete risk or improvement.

---

## Attribution

Based on [qdhenry/Claude-Command-Suite](https://github.com/qdhenry/Claude-Command-Suite) (MIT License).
