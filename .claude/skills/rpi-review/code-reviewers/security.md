---
description: "Security audit against OWASP Top 10, secrets detection, and defense-in-depth analysis"
argument-hint: "[file-or-directory]"
---

# Security Review

---

## Target

- `$ARGUMENTS`: File or directory to review (defaults to changed files on current branch vs default branch)

If no argument provided, get the changed files and full diff:
```bash
BASE_BRANCH=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')
BASE_BRANCH=${BASE_BRANCH:-main}
git diff --name-only "$BASE_BRANCH"...HEAD
git diff "$BASE_BRANCH"...HEAD
```

Read every target file before analysis.

---

## Review Checklist

### OWASP Top 10

| ID | Category | What to Look For |
|----|----------|-----------------|
| A01 | Broken Access Control | Missing `[Authorize]`, direct object references without ownership checks |
| A02 | Cryptographic Failures | Hardcoded secrets/keys/tokens, weak hashing (MD5/SHA1 for security) |
| A03 | Injection | SQL via string concat, command injection, XSS from unescaped output |
| A04 | Insecure Design | Missing rate limiting on auth, no CSRF protection |
| A05 | Security Misconfiguration | Debug mode in prod config, overly permissive CORS, verbose errors |
| A06 | Vulnerable Components | Known vulnerable NuGet/npm packages |
| A07 | Auth Failures | Session fixation, token expiration issues, insecure token storage |
| A08 | Data Integrity | Missing input validation, untrusted deserialization |
| A09 | Logging Failures | Passwords/tokens/PII in logs, missing audit logging |
| A10 | SSRF | Unvalidated URLs from user input |

### Additional Checks
- Secrets & credentials committed to source
- Race conditions in auth/authz code paths
- Resource exhaustion (unbounded uploads, missing pagination limits)
- ReDoS patterns in regex

---

## Severity Levels

- **CRITICAL**: Exploitable vulnerability, data breach risk
- **HIGH**: Significant security weakness
- **MEDIUM**: Defense-in-depth concern
- **LOW**: Best practice improvement

---

## Output Format

For each finding:

```
### SEC-{NNN}: {Title}

**Severity**: CRITICAL | HIGH | MEDIUM | LOW
**Category**: A01-A10 | secrets | concurrency | resource-exhaustion
**CWE**: CWE-XXX (if applicable)
**File**: path/to/file.cs:line

**Issue**: {What is wrong and why it's a security risk}

**Current**:
{code snippet}

**Recommended**:
{code snippet}

**Impact**: {What an attacker could do}
**Effort**: Quick | Medium | Large
```

---

## Summary

```
## Security Review Summary

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Access Control | | | | |
| Injection | | | | |
| Secrets | | | | |
| Auth | | | | |
| Config | | | | |
| Other | | | | |

**Overall Security Risk**: CRITICAL | HIGH | MEDIUM | LOW

### Top 5 Security Fixes (ranked by exploitability)
1. ...
2. ...
3. ...
4. ...
5. ...
```
