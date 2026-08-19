#!/usr/bin/env python3
"""Read Cursor Models / Other Models usage into a local cache.

Uses the already-signed-in Cursor session on this Mac:

  POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage
  GET  https://cursor.com/api/usage-summary

Token stays in memory. It is only sent to api2.cursor.sh / cursor.com.

  cursor-usage.py refresh
  cursor-usage.py refresh --force
  cursor-usage.py refresh --dry-run

Cache defaults to ~/Library/Caches/PoolBar/. Override with POOLBAR_CACHE_DIR.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sqlite3
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request

CACHE_DIR = os.environ.get("POOLBAR_CACHE_DIR") or os.path.expanduser(
    "~/Library/Caches/PoolBar"
)
CACHE = os.path.join(CACHE_DIR, "cursor-usage.json")
RAW = os.path.join(CACHE_DIR, "cursor-usage-raw.json")
STATE_DB = os.path.expanduser(
    "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
)
KEYCHAIN_SERVICE = "cursor-access-token"
API2 = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
SUMMARY = "https://cursor.com/api/usage-summary"
TTL_SECONDS = 300
SSL_CTX = ssl.create_default_context()
USER_AGENT = "PoolBar/1.0"


def _strip_token(raw):
    if not raw:
        return None
    raw = raw.strip().strip('"').strip("'")
    return raw or None


def _token_from_state_db():
    if not os.path.isfile(STATE_DB):
        return None, None
    uris = (f"file:{STATE_DB}?mode=ro", f"file:{STATE_DB}?mode=ro&immutable=1")
    for uri in uris:
        try:
            conn = sqlite3.connect(uri, uri=True, timeout=5)
            try:
                row = conn.execute(
                    "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken'"
                ).fetchone()
                mem = conn.execute(
                    "SELECT value FROM ItemTable WHERE key='cursorAuth/stripeMembershipType'"
                ).fetchone()
            finally:
                conn.close()
            token = _strip_token(row[0] if row else None)
            membership = _strip_token(mem[0] if mem else None)
            return token, membership
        except sqlite3.Error:
            continue
    return None, None


def _token_from_keychain():
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    return _strip_token(out.stdout)


def jwt_sub(token):
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        data = json.loads(base64.urlsafe_b64decode(payload))
        return data.get("sub")
    except (IndexError, ValueError, json.JSONDecodeError):
        return None


def get_token():
    token, membership = _token_from_state_db()
    if not token:
        token = _token_from_keychain()
        membership = membership or None
    return token, membership


def _ms_epoch(v):
    if v is None:
        return None
    if isinstance(v, str) and v.isdigit():
        n = int(v)
        return n / 1000.0 if n > 10_000_000_000 else float(n)
    if isinstance(v, (int, float)):
        n = float(v)
        return n / 1000.0 if n > 10_000_000_000 else n
    if isinstance(v, str):
        try:
            base = v.replace("Z", "").split(".")[0]
            return time.mktime(time.strptime(base[:19], "%Y-%m-%dT%H:%M:%S")) - time.timezone
        except (ValueError, OverflowError):
            return None
    return None


def _http_json(method, url, headers, body=None, timeout=25):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method)
    for k, v in headers.items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else {}
        except ValueError:
            parsed = {"_http_body": raw[:500]}
        return e.code, parsed


def parse_period(data):
    """Percent fields from this endpoint are already percents. Do not multiply by 100."""
    if not isinstance(data, dict):
        return None
    plan = data.get("planUsage") or {}
    if not isinstance(plan, dict):
        return None
    auto = plan.get("autoPercentUsed")
    api = plan.get("apiPercentUsed")
    if not isinstance(auto, (int, float)) and not isinstance(api, (int, float)):
        return None
    return {
        "billing_cycle_start": _ms_epoch(data.get("billingCycleStart")),
        "billing_cycle_end": _ms_epoch(data.get("billingCycleEnd")),
        "auto_percent": float(auto) if isinstance(auto, (int, float)) else None,
        "api_percent": float(api) if isinstance(api, (int, float)) else None,
        "spend_cents": plan.get("totalSpend"),
        "limit_cents": plan.get("limit"),
        "display_auto": data.get("autoModelSelectedDisplayMessage"),
        "display_api": data.get("namedModelSelectedDisplayMessage"),
    }


def parse_summary(data):
    if not isinstance(data, dict):
        return {}
    ind = (data.get("individualUsage") or {}).get("plan") or {}
    od = (data.get("individualUsage") or {}).get("onDemand") or {}
    out = {
        "membership": data.get("membershipType"),
        "on_demand_enabled": bool(od.get("enabled")),
        "on_demand_used": od.get("used"),
        "on_demand_limit": od.get("limit"),
    }
    if isinstance(ind, dict):
        if ind.get("limit") is not None:
            out["summary_limit_cents"] = ind.get("limit")
        if isinstance(ind.get("autoPercentUsed"), (int, float)):
            out.setdefault("auto_percent", float(ind["autoPercentUsed"]))
        if isinstance(ind.get("apiPercentUsed"), (int, float)):
            out.setdefault("api_percent", float(ind["apiPercentUsed"]))
    return out


def cache_age():
    try:
        with open(CACHE) as fh:
            rec = json.load(fh)
        return time.time() - float(rec.get("captured_at", 0)), rec
    except (OSError, ValueError, TypeError):
        return None, None


def write_cache(parsed, extra, raw):
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    rec = {
        "captured_at": time.time(),
        "captured_at_iso": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "source": "api2.GetCurrentPeriodUsage",
        "membership": extra.get("membership"),
        "billing_cycle_start": parsed.get("billing_cycle_start"),
        "billing_cycle_end": parsed.get("billing_cycle_end"),
        "cursor_models": {
            "used_percent": parsed.get("auto_percent"),
            "field": "autoPercentUsed",
            "list_price_cents": parsed.get("spend_cents"),
        },
        "cursor_api": {
            "used_percent": parsed.get("api_percent"),
            "field": "apiPercentUsed",
            "included_limit_cents": parsed.get("limit_cents") or extra.get("summary_limit_cents"),
            "on_demand_enabled": extra.get("on_demand_enabled"),
            "on_demand_used": extra.get("on_demand_used"),
            "on_demand_limit": extra.get("on_demand_limit"),
        },
        "display_auto": parsed.get("display_auto"),
        "display_api": parsed.get("display_api"),
    }
    tmp = CACHE + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(rec, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, CACHE)
    tmpr = RAW + ".tmp"
    with open(tmpr, "w") as fh:
        json.dump(raw, fh, ensure_ascii=False, indent=2)
    os.replace(tmpr, RAW)
    return rec


def cmd_refresh(args):
    if not args.force:
        age, rec = cache_age()
        if age is not None and age < TTL_SECONDS and rec and rec.get("cursor_models"):
            print(f"cache still fresh ({age:.0f}s). pass --force to refresh")
            return 0

    token, membership = get_token()
    if not token:
        print("No Cursor session token found.", file=sys.stderr)
        print(f"  looked in: {STATE_DB}  key cursorAuth/accessToken", file=sys.stderr)
        print(f"             keychain service '{KEYCHAIN_SERVICE}'", file=sys.stderr)
        print("  Sign in to Cursor, then refresh again.", file=sys.stderr)
        return 2
    print(f"got session token (len {len(token)}, not printed)")

    if args.dry_run:
        print("--dry-run: stopping before any network call")
        return 0

    st, period = _http_json(
        "POST",
        API2,
        {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
            "User-Agent": USER_AGENT,
        },
        {},
    )
    if st != 200:
        hint = {
            401: "session expired — sign in to Cursor again",
            403: "this account cannot read dashboard usage",
            404: "endpoint changed",
        }.get(st, "")
        print(f"GetCurrentPeriodUsage HTTP {st}. {hint}", file=sys.stderr)
        os.makedirs(os.path.dirname(RAW), exist_ok=True)
        with open(RAW, "w") as fh:
            json.dump({"http": st, "body": period}, fh, ensure_ascii=False, indent=2)
        return 3

    parsed = parse_period(period)
    if not parsed:
        print("response missing autoPercentUsed / apiPercentUsed", file=sys.stderr)
        os.makedirs(os.path.dirname(RAW), exist_ok=True)
        with open(RAW, "w") as fh:
            json.dump(period, fh, ensure_ascii=False, indent=2)
        return 4

    extra = {"membership": membership}
    sub = jwt_sub(token)
    if sub:
        cookie = f"WorkosCursorSessionToken={sub}%3A%3A{token}"
        st2, summary = _http_json(
            "GET",
            SUMMARY,
            {
                "Cookie": cookie,
                "Origin": "https://cursor.com",
                "User-Agent": USER_AGENT,
            },
        )
        if st2 == 200:
            extra.update(parse_summary(summary))
            raw_all = {"period": period, "summary": summary}
        else:
            raw_all = {"period": period, "summary_http": st2, "summary": summary}
    else:
        raw_all = {"period": period}

    rec = write_cache(parsed, extra, raw_all)
    print(f"wrote {CACHE}")
    models = rec["cursor_models"]["used_percent"]
    api = rec["cursor_api"]["used_percent"]
    plan = rec.get("membership") or "?"
    print(f"  plan {plan}")
    print(f"  Cursor Models  {models if models is not None else '?'}%")
    print(f"  Other Models   {api if api is not None else '?'}%")
    return 0


def main():
    ap = argparse.ArgumentParser(description="Read Cursor usage pools into a local cache")
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("refresh", help="fetch usage and write cache")
    r.add_argument("--force", action="store_true")
    r.add_argument("--dry-run", action="store_true")
    r.set_defaults(func=cmd_refresh)
    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
