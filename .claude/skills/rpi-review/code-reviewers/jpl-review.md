---
description: Analyze codebase for Power of Ten violations and critical issues
argument-hint: [language] [file-or-directory]
allowed-tools:
  - Bash
  - FileWrite
  - FileRead
---

# Code Audit - Power of Ten Analysis

Perform a comprehensive security and reliability audit of the codebase using NASA/JPL's Power of Ten principles adapted for modern languages.

## Arguments

- `$1` (required): Language (`typescript`, `javascript`, `csharp`, `go`, or `all`)
- `$2` (optional): Specific file or directory to analyze (defaults to current directory)

## Analysis Instructions

You are conducting a critical code audit based on NASA/JPL's Power of Ten rules for safety-critical software, adapted for modern languages. Your goal is to identify and flag violations that could lead to:

- Runtime crashes or undefined behavior
- Security vulnerabilities
- Resource leaks (memory, file handles, connections)
- Concurrency issues and race conditions
- Maintenance and scalability problems

### Step 1: Determine Target and Scope

1. Read the language argument: `$1`
2. Determine target path: `$2` (or current directory if not specified)
3. Use bash to identify relevant files:
   - TypeScript/JavaScript: `*.ts`, `*.tsx`, `*.js`, `*.jsx`
   - C#: `*.cs`
   - Go: `*.go`
   - all: scan for all supported file types

**Example bash command:**
```bash
!find . -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) | head -50
```

### Step 2: Analyze Each File

For each file, systematically check for violations in these categories:

#### Critical Violations (Must Fix)

**Control Flow Issues:**
- Unbounded recursion
- Complex nested callbacks (>3 levels deep)
- Missing error boundaries in async code
- Improper exception handling (empty catch blocks)

**Loop & Iteration Issues:**
- Unbounded loops without timeout mechanisms
- Missing termination conditions
- Iteration over untrusted data without size limits

**Memory & Resource Issues:**
- Resource leaks (unclosed files, connections, event listeners)
- Large allocations in hot paths
- Missing cleanup in destructors/dispose patterns

**Concurrency Issues:**
- Race conditions in shared state
- Missing synchronization primitives
- Unhandled promise rejections
- Deadlock-prone patterns

**Input Validation Issues:**
- Missing null/undefined checks
- No validation on external inputs (APIs, user data)
- Type assertions without runtime validation

#### High Priority Violations

**Error Handling:**
- Functions that can fail without returning errors/throwing
- Silent error swallowing
- Missing error propagation

**Function Complexity:**
- Functions exceeding 50-60 lines
- Cyclomatic complexity >10
- Multiple responsibilities in single function

**Type Safety:**
- Excessive use of `any`/`dynamic`/`interface{}`
- Unsafe type casts without validation
- Missing type annotations on public APIs

**Scope & Encapsulation:**
- Variables with broader scope than necessary
- Mutable global/package-level state
- Public fields that should be private

#### Medium Priority Violations

**Code Quality:**
- Long files (>300-500 lines)
- Inconsistent error handling patterns
- Missing documentation on public APIs
- Disabled linter rules without justification

### Step 3: Generate Report

Create a structured report with:

1. **Executive Summary**
   - Total files analyzed
   - Critical issues count
   - High priority issues count
   - Risk assessment (Critical/High/Medium/Low)

2. **Critical Issues (Severity: CRITICAL)**
   ```
   [CRITICAL] Violation Type
   File: path/to/file.ts:line:column
   Issue: Detailed description
   Code Snippet: (relevant lines)
   Recommendation: Specific fix
   Impact: Why this is critical
   ```

3. **High Priority Issues (Severity: HIGH)**
   (Same format as above)

4. **Medium Priority Issues (Severity: MEDIUM)**
   (Same format as above)

5. **Language-Specific Recommendations**
   - Linting tools to enable
   - Static analysis tools recommended
   - Testing requirements

6. **Action Items**
   - Prioritized list of fixes
   - Estimated effort for each category
   - Suggested refactoring approach

### Step 4: Create Detailed Report File

Save the complete analysis to `power-of-ten-audit-report.md` in the project root using FileWrite.

### Step 5: Summary

Provide a concise terminal output summary:
- Number of critical issues requiring immediate attention
- Number of high priority issues
- Top 3 most important fixes
- Link to the detailed report file

## Language-Specific Focus Areas

### TypeScript/JavaScript
- Promise handling and async/await patterns
- Closure memory leaks
- Event listener cleanup
- `any` type usage
- Missing null checks

### C#
- `IDisposable` implementation
- Async void methods
- Nullable reference types
- Exception handling patterns
- Resource cleanup

### Go
- Goroutine leaks
- Channel operations without timeout
- Error handling (ignored errors)
- Race conditions
- Context propagation

## Validation Rules

Before starting analysis:
1. Verify target directory/file exists
2. Confirm language matches file extensions found
3. Estimate file count (warn if >100 files)
4. Check for existing audit reports

## Example Usage

```bash
# Analyze TypeScript code in current directory
/jpl-review typescript

# Analyze specific Go package
/jpl-review go ./internal/api

# Analyze all supported languages
/jpl-review all

# Analyze specific file
/jpl-review csharp ./Services/PaymentService.cs
```

## Success Criteria

Your audit is complete when you have:
1. Analyzed all relevant files in scope
2. Identified and categorized all violations by severity
3. Generated detailed report file with actionable recommendations
4. Provided executive summary with key findings
5. Listed prioritized action items for remediation

## Important Notes

- Focus on violations that impact safety, security, and reliability
- Provide specific code locations (file:line:column)
- Include code snippets for context
- Offer concrete, actionable fixes
- Prioritize based on actual risk, not just rule violations
- Consider the project's specific context when assessing severity
