#!/usr/bin/env python3
"""Claude Code statusline script that shows context + usage limits.

Reads JSON from stdin (provided by Claude Code), fetches usage data from
the Anthropic API with caching, and outputs a single-line statusline.
All async tasks (git branch, usage fetch) run in parallel.
"""

import asyncio
import json
import os
import sys
import time
import urllib.request
from datetime import datetime, timezone


CREDENTIALS_PATH = os.path.expanduser("~/.claude/.credentials.json")
CACHE_PATH = "/tmp/claude-usage-cache.json"
CACHE_TTL_SECONDS = 60
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"

_MODEL_COLORS = {"opus": 34, "sonnet": 32, "haiku": 33}
_BRANCH_PREFIXES = {
    "feature/": "(f)/",
    "fix/": "(x)/",
    "hotfix/": "(h)/",
}


# ---------------------------------------------------------------------------
# ANSI helpers
# ---------------------------------------------------------------------------

def _ansi(code: int, text: str) -> str:
    return f"\033[{code}m{text}\033[0m"


def _pct_color(pct: int) -> int:
    if pct <= 20:
        return 31
    return 33 if pct <= 50 else 32


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

def read_stdin():
    try:
        return json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        return {}


# ---------------------------------------------------------------------------
# Git branch
# ---------------------------------------------------------------------------

async def get_git_branch(cwd: str) -> str | None:
    try:
        proc = await asyncio.create_subprocess_exec(
            "git", "-C", cwd, "branch", "--show-current",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await proc.communicate()
        return stdout.decode().strip() or None
    except (OSError, FileNotFoundError):
        return None


# ---------------------------------------------------------------------------
# Usage fetch + cache
# ---------------------------------------------------------------------------

def _get_access_token() -> str | None:
    try:
        with open(CREDENTIALS_PATH) as f:
            creds = json.load(f)
        return creds.get("claudeAiOauth", {}).get("accessToken")
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        return None


async def _fetch_usage_http(token: str) -> dict | None:
    loop = asyncio.get_running_loop()

    def _fetch():
        req = urllib.request.Request(
            USAGE_URL,
            headers={
                "Authorization": f"Bearer {token}",
                "anthropic-beta": "oauth-2025-04-20",
            },
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read())

    try:
        return await loop.run_in_executor(None, _fetch)
    except Exception as e:
        print(f"usage fetch failed: {e}", file=sys.stderr)
        return None


def _read_cache() -> dict | None:
    try:
        with open(CACHE_PATH) as f:
            cache = json.load(f)
        if time.time() - cache.get("ts", 0) < CACHE_TTL_SECONDS:
            return cache.get("data")
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    return None


def _write_cache(data: dict) -> None:
    try:
        with open(CACHE_PATH, "w") as f:
            json.dump({"ts": time.time(), "data": data}, f)
    except OSError:
        pass


async def get_usage() -> dict | None:
    cached = _read_cache()
    if cached is not None:
        return cached
    token = _get_access_token()
    if not token:
        return None
    data = await _fetch_usage_http(token)
    if data is not None:
        _write_cache(data)
    return data


# ---------------------------------------------------------------------------
# Formatters
# ---------------------------------------------------------------------------

def fmt_window(data: dict, label: str) -> str | None:
    utilization = data.get("utilization")
    if utilization is None:
        return None
    remaining = max(100 - round(utilization), 0)
    return f"{label}:{_ansi(_pct_color(remaining), f'{remaining}%')}"


def fmt_extra_usage(extra: dict) -> str | None:
    if not extra or not extra.get("is_enabled"):
        return None
    used = extra.get("used_credits", 0)
    limit = extra.get("monthly_limit", 0)
    return f"${used / 100:.2f}/${limit / 100:.0f}"


def fmt_branch(branch: str) -> str:
    for prefix, short in _BRANCH_PREFIXES.items():
        if branch.startswith(prefix):
            branch = short + branch[len(prefix):]
            break
    if len(branch) > 20:
        branch = branch[:19] + "…"
    return _ansi(36, branch)


def fmt_cwd(raw_cwd: str) -> str:
    home = os.path.expanduser("~")
    path = ("~" + raw_cwd[len(home):]) if raw_cwd.startswith(home) else raw_cwd
    return path.rsplit("/", 1)[-1] or path


def fmt_model(model_name: str) -> str:
    name_lower = model_name.lower()
    for key, code in _MODEL_COLORS.items():
        if key in name_lower:
            return _ansi(code, model_name)
    return model_name


def fmt_ctx(ctx_window: dict) -> str | None:
    # Omit the last 22.5% (autocompact buffer) from effective limit.
    used_pct = ctx_window.get("used_percentage")
    if used_pct is None:
        return None
    remaining_pct = max(round((0.775 - used_pct / 100) / 0.775 * 100), 0)
    return f"ctx:{remaining_pct}%"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def _join(parts: list[str | None]) -> str:
    return " | ".join(p for p in parts if p)


async def main():
    ctx = read_stdin()
    raw_cwd = ctx.get("cwd", "")

    branch, usage = await asyncio.gather(
        get_git_branch(raw_cwd),
        get_usage(),
    )

    model_name = ctx.get("model", {}).get("display_name", "")
    cost = ctx.get("cost", {}).get("total_cost_usd")

    print(_join([
        fmt_cwd(raw_cwd),
        fmt_branch(branch) if branch else None,
        fmt_model(model_name) if model_name else None,
        fmt_ctx(ctx.get("context_window", {})),
        fmt_window(usage.get("five_hour", {}), "5h") if usage else None,
        fmt_window(usage.get("seven_day", {}), "7d") if usage else None,
        f"${cost:.2f}" if cost is not None else None,
        fmt_extra_usage(usage.get("extra_usage")) if usage else None,
        ctx.get("session_id") or None,
    ]))


if __name__ == "__main__":
    asyncio.run(main())
