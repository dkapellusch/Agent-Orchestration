#!/usr/bin/env python3
"""
Fill credentials into agent-browser form fields without bash escaping issues.

Usage:
    python3 credential-fill.py <domain> <username_ref> <password_ref> [submit_ref]
    python3 credential-fill.py example.okta.com @e2 @e3 @e4

This script:
1. Gets credentials from browser-passwords.py for the given domain
2. Calls agent-browser directly via subprocess (no shell escaping)
3. Fills username and password fields
4. Optionally clicks submit button
"""

import sys
import os
import json
import subprocess
from pathlib import Path


def get_credentials(domain: str) -> dict | None:
    """Get credentials using browser-passwords.py"""
    script_dir = Path(__file__).parent
    py_script = script_dir / "browser-passwords.py"

    try:
        result = subprocess.run(
            ["python3", str(py_script), domain],
            capture_output=True,
            text=True,
            timeout=120
        )

        if result.returncode != 0:
            return None

        data = json.loads(result.stdout)
        if "error" in data:
            print(f"[credential-fill] {data['error']}", file=sys.stderr)
            return None

        return data
    except Exception as e:
        print(f"[credential-fill] Error getting credentials: {e}", file=sys.stderr)
        return None


def fill_field(ref: str, value: str) -> bool:
    """Fill a field using agent-browser without shell escaping"""
    try:
        result = subprocess.run(
            ["agent-browser", "fill", ref, value],
            capture_output=True,
            text=True,
            timeout=30
        )
        return result.returncode == 0
    except Exception as e:
        print(f"[credential-fill] Error filling {ref}: {e}", file=sys.stderr)
        return False


def click_element(ref: str) -> bool:
    """Click an element using agent-browser"""
    try:
        result = subprocess.run(
            ["agent-browser", "click", ref],
            capture_output=True,
            text=True,
            timeout=30
        )
        return result.returncode == 0
    except Exception as e:
        print(f"[credential-fill] Error clicking {ref}: {e}", file=sys.stderr)
        return False


def main():
    if len(sys.argv) < 4:
        print("Usage: python3 credential-fill.py <domain> <username_ref> <password_ref> [submit_ref]")
        print("Example: python3 credential-fill.py example.okta.com @e2 @e3 @e4")
        sys.exit(1)

    domain = sys.argv[1]
    username_ref = sys.argv[2]
    password_ref = sys.argv[3]
    submit_ref = sys.argv[4] if len(sys.argv) > 4 else None

    print(f"[credential-fill] Getting credentials for {domain}...")
    creds = get_credentials(domain)

    if not creds:
        print("[credential-fill] Failed to get credentials")
        sys.exit(1)

    username = creds.get("username", "")
    password = creds.get("password", "")

    if not password:
        print("[credential-fill] No password found")
        sys.exit(1)

    print(f"[credential-fill] Found credentials for user: {username}")
    if username:
        print(f"[credential-fill] Filling username field {username_ref}")
        if not fill_field(username_ref, username):
            print("[credential-fill] Failed to fill username")
            sys.exit(1)

    print(f"[credential-fill] Filling password field {password_ref}")
    if not fill_field(password_ref, password):
        print("[credential-fill] Failed to fill password")
        sys.exit(1)

    if submit_ref:
        print(f"[credential-fill] Clicking submit: {submit_ref}")
        if not click_element(submit_ref):
            print("[credential-fill] Failed to click submit")
            sys.exit(1)

    print("[credential-fill] Done!")


if __name__ == "__main__":
    main()
