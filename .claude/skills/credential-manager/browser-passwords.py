#!/usr/bin/env python3
"""
Extract passwords from Chromium-based browsers (Chrome, Arc, Edge, Brave) on macOS.

Usage:
    python3 browser-passwords.py <domain>
    python3 browser-passwords.py github.com
    python3 browser-passwords.py <domain> --verify  # Check if creds exist (no password output)
    python3 browser-passwords.py --list  # List all saved domains
    python3 browser-passwords.py <domain> --no-prompt  # Skip user confirmation
    python3 browser-passwords.py --clear-session  # Clear session approvals

Output (JSON):
    {"username": "user@example.com", "password": "secret123", "url": "https://example.com"}

Requirements:
    pip install pycryptodome

Security:
    - Requires user authentication via Keychain (Touch ID or password)
    - Prompts user for approval before returning each domain's credentials (per session)
    - Only accesses user's own credentials on their own machine
"""

import sys
import os
import json
import sqlite3
import tempfile
import shutil
import subprocess
import hashlib
from pathlib import Path

try:
    from Crypto.Cipher import AES
    from Crypto.Protocol.KDF import PBKDF2
    from Crypto.Hash import SHA1
    HAS_CRYPTO = True
except ImportError:
    HAS_CRYPTO = False


BROWSER_PATHS = {
    "arc": Path.home() / "Library/Application Support/Arc/User Data",
    "chrome": Path.home() / "Library/Application Support/Google/Chrome",
    "edge": Path.home() / "Library/Application Support/Microsoft Edge",
    "brave": Path.home() / "Library/Application Support/BraveSoftware/Brave-Browser",
    "chromium": Path.home() / "Library/Application Support/Chromium",
}

BROWSER_KEYCHAIN_SERVICES = {
    "arc": ("Arc Safe Storage", "Arc"),
    "chrome": ("Chrome Safe Storage", "Chrome"),
    "edge": ("Microsoft Edge Safe Storage", "Microsoft Edge"),
    "brave": ("Brave Safe Storage", "Brave"),
    "chromium": ("Chromium Safe Storage", "Chromium"),
}

SESSION_APPROVALS_FILE = Path(tempfile.gettempdir()) / "credential-manager-approvals.json"

_memory_approvals: dict[str, bool] = {}


def get_session_approvals() -> dict:
    """Load session approvals from temp file."""
    if SESSION_APPROVALS_FILE.exists():
        try:
            with open(SESSION_APPROVALS_FILE, 'r') as f:
                data = json.load(f)
                pid = data.get("session_pid")
                if pid == os.getppid():
                    return data.get("approvals", {})
        except Exception:
            pass
    return {}


def save_session_approval(domain: str, approved: bool) -> None:
    """Save approval decision for this session."""
    approvals = get_session_approvals()
    approvals[domain] = approved

    with open(SESSION_APPROVALS_FILE, 'w') as f:
        json.dump({
            "session_pid": os.getppid(),
            "approvals": approvals
        }, f)


def clear_session_approvals() -> None:
    """Clear all session approvals."""
    if SESSION_APPROVALS_FILE.exists():
        SESSION_APPROVALS_FILE.unlink()


def prompt_user_approval(domain: str, username: str, browser: str) -> bool:
    """Show macOS dialog asking user to approve credential access."""
    global _memory_approvals

    approval_key = f"{domain}:{username}"

    if approval_key in _memory_approvals:
        return _memory_approvals[approval_key]

    approvals = get_session_approvals()
    if approval_key in approvals:
        _memory_approvals[approval_key] = approvals[approval_key]
        return approvals[approval_key]

    masked_user = username[:3] + "***" + username[-10:] if len(username) > 13 else username

    script = f'''
        display dialog "Allow access to saved credentials?

Domain: {domain}
Username: {masked_user}

This approval is valid for the current session only." ¬
            buttons {{"Deny", "Allow Once", "Allow for Session"}} ¬
            default button "Allow Once" ¬
            cancel button "Deny" ¬
            with title "Credential Manager" ¬
            with icon caution
        return button returned of result
    '''

    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=60
        )

        if result.returncode != 0:
            _memory_approvals[approval_key] = False
            save_session_approval(approval_key, False)
            return False

        response = result.stdout.strip()

        if response == "Allow for Session":
            _memory_approvals[approval_key] = True
            save_session_approval(approval_key, True)
            return True
        elif response == "Allow Once":
            _memory_approvals[approval_key] = True
            return True
        else:
            _memory_approvals[approval_key] = False
            save_session_approval(approval_key, False)
            return False

    except subprocess.TimeoutExpired:
        return False
    except Exception:
        return False


def get_encryption_key(browser: str) -> bytes | None:
    """Get the encryption key from macOS Keychain."""
    keychain_info = BROWSER_KEYCHAIN_SERVICES.get(browser)
    if not keychain_info:
        return None

    service_name, account_name = keychain_info

    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-s", service_name, "-a", account_name, "-w"],
            capture_output=True,
            text=True,
            timeout=15
        )
        if result.returncode != 0:
            return None

        passphrase = result.stdout.strip()
        if not passphrase:
            return None

        key = PBKDF2(
            passphrase.encode('utf-8'),
            b'saltysalt',
            dkLen=16,
            count=1003,
            hmac_hash_module=SHA1
        )
        return key
    except subprocess.TimeoutExpired:
        print(f"[browser-passwords] Keychain access timed out for {browser}. Run manually to authenticate.", file=sys.stderr)
        return None
    except Exception:
        return None


def decrypt_password(encrypted: bytes, key: bytes) -> str | None:
    """Decrypt a Chromium-encrypted password."""
    if not encrypted:
        return None

    if encrypted[:3] != b'v10':
        return encrypted.decode('utf-8', errors='ignore')

    try:
        iv = b' ' * 16
        cipher = AES.new(key, AES.MODE_CBC, iv)
        decrypted = cipher.decrypt(encrypted[3:])

        padding_len = decrypted[-1]
        if padding_len > 16:
            return None
        return decrypted[:-padding_len].decode('utf-8')
    except Exception:
        return None


def find_profile_paths(browser_path: Path) -> list[Path]:
    """Find all profile directories with Login Data."""
    profiles = []

    default_login = browser_path / "Default" / "Login Data"
    if default_login.exists():
        profiles.append(default_login)

    for profile_dir in browser_path.glob("Profile *"):
        login_data = profile_dir / "Login Data"
        if login_data.exists():
            profiles.append(login_data)

    return profiles


def extract_passwords(domain: str | None = None, list_domains: bool = False, require_approval: bool = True) -> list[dict]:
    """Extract passwords from all available browsers."""
    if not HAS_CRYPTO:
        print(json.dumps({"error": "pycryptodome not installed. Run: pip install pycryptodome"}))
        sys.exit(1)

    results = []

    for browser, base_path in BROWSER_PATHS.items():
        if not base_path.exists():
            continue

        key = get_encryption_key(browser)
        if not key:
            continue

        for login_data_path in find_profile_paths(base_path):
            try:
                with tempfile.NamedTemporaryFile(delete=False, suffix='.db') as tmp:
                    tmp_path = tmp.name

                shutil.copy(login_data_path, tmp_path)

                conn = sqlite3.connect(tmp_path)
                cursor = conn.cursor()

                if list_domains:
                    cursor.execute(
                        "SELECT DISTINCT origin_url FROM logins WHERE blacklisted_by_user = 0"
                    )
                    for row in cursor.fetchall():
                        url = row[0]
                        results.append({"url": url, "browser": browser})
                elif domain:
                    cursor.execute(
                        "SELECT origin_url, username_value, password_value FROM logins "
                        "WHERE blacklisted_by_user = 0 AND origin_url LIKE ?",
                        (f"%{domain}%",)
                    )
                    for row in cursor.fetchall():
                        url, username, encrypted_password = row
                        password = decrypt_password(encrypted_password, key)
                        if password and username:
                            if require_approval:
                                if not prompt_user_approval(domain, username, browser):
                                    continue
                            results.append({
                                "url": url,
                                "username": username,
                                "password": password,
                                "browser": browser
                            })

                conn.close()
                os.unlink(tmp_path)

            except Exception as e:
                if 'tmp_path' in locals() and os.path.exists(tmp_path):
                    os.unlink(tmp_path)
                continue

    return results


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 browser-passwords.py <domain>")
        print("       python3 browser-passwords.py <domain> --verify")
        print("       python3 browser-passwords.py <domain> --no-prompt")
        print("       python3 browser-passwords.py --list")
        print("       python3 browser-passwords.py --clear-session")
        sys.exit(1)

    args = sys.argv[1:]
    no_prompt = "--no-prompt" in args
    verify_only = "--verify" in args
    if no_prompt:
        args.remove("--no-prompt")
    if verify_only:
        args.remove("--verify")

    if not args:
        print("Usage: python3 browser-passwords.py <domain>")
        sys.exit(1)

    arg = args[0]

    if arg == "--list":
        results = extract_passwords(list_domains=True, require_approval=False)
        seen = set()
        unique = []
        for r in results:
            if r["url"] not in seen:
                seen.add(r["url"])
                unique.append(r)
        print(json.dumps(unique, indent=2))
    elif arg == "--clear-session":
        clear_session_approvals()
        print(json.dumps({"status": "Session approvals cleared"}))
    else:
        results = extract_passwords(domain=arg, require_approval=not no_prompt)
        if results:
            if verify_only:
                result = results[0].copy()
                result["password"] = "********"
                print(json.dumps(result))
            else:
                print(json.dumps(results[0]))
        else:
            print(json.dumps({"error": f"No credentials found for {arg} (or access denied)"}))
            sys.exit(1)


if __name__ == "__main__":
    main()
