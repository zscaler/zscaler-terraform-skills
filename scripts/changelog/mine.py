#!/usr/bin/env python3
"""Mine each provider's CHANGELOG.md and write a 'Recent Provider Changes' reference page per skill.

For each (skill, provider) pair, fetch the upstream CHANGELOG.md, parse the top N versions,
and emit a curated reference page listing newly added resources/attributes and bug fixes
that affect HCL users (provider-internal refactors are filtered out).

Sources can be local checkouts (set ZSCALER_PROVIDERS_DIR) or fetched over HTTPS.

Usage:
    python scripts/changelog/mine.py
    python scripts/changelog/mine.py --skill zia --top 8
    ZSCALER_PROVIDERS_DIR=~/code/zscaler python scripts/changelog/mine.py
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import sys
import urllib.request
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parents[2]

# (skill_name, provider_repo_basename, raw URL of CHANGELOG.md)
PROVIDERS: list[tuple[str, str, str]] = [
    ("zpa", "terraform-provider-zpa",
     "https://raw.githubusercontent.com/zscaler/terraform-provider-zpa/master/CHANGELOG.md"),
    ("zia", "terraform-provider-zia",
     "https://raw.githubusercontent.com/zscaler/terraform-provider-zia/master/CHANGELOG.md"),
    ("ztc", "terraform-provider-ztc",
     "https://raw.githubusercontent.com/zscaler/terraform-provider-ztc/master/CHANGELOG.md"),
    # ZCC: not yet published; the scheduled workflow will start picking it up once
    # https://github.com/zscaler/terraform-provider-zcc is public.
    ("zcc", "terraform-provider-zcc",
     "https://raw.githubusercontent.com/zscaler/terraform-provider-zcc/master/CHANGELOG.md"),
]

VERSION_RE = re.compile(r"^##\s+v?(\d+\.\d+\.\d+)\s*\(([^)]+)\).*$")
SECTION_RE = re.compile(r"^###\s+(.+?)\s*$")
ENTRY_RE = re.compile(r"^-\s+(.*)$")

# Heuristic: surface entries that mention HCL-visible artifacts.
USER_FACING_HINTS = re.compile(
    r"\b("
    r"resource|data\s+source|attribute|field|argument|"
    r"zpa_[a-z_]+|zia_[a-z_]+|ztc_[a-z_]+|zcc_[a-z_]+|"
    r"validation|deprecat|breaking|"
    r"added\s+support|added\s+new|now\s+supports|"
    r"removed\s+(?!.*internal)|"
    r"renamed|moved\s+from"
    r")\b",
    re.IGNORECASE,
)


def fetch_changelog(provider_repo: str, url: str) -> str:
    local_root = os.environ.get("ZSCALER_PROVIDERS_DIR")
    if local_root:
        local = Path(local_root).expanduser() / provider_repo / "CHANGELOG.md"
        if local.exists():
            print(f"  using local: {local}")
            return local.read_text()
    print(f"  fetching: {url}")
    with urllib.request.urlopen(url, timeout=20) as resp:
        return resp.read().decode("utf-8")


def parse_versions(text: str) -> list[dict]:
    """Yield list of {version, date, sections: {name: [entries]}} top-down."""
    versions: list[dict] = []
    current: dict | None = None
    current_section: str | None = None
    for raw in text.splitlines():
        line = raw.rstrip()
        m = VERSION_RE.match(line)
        if m:
            if current:
                versions.append(current)
            current = {"version": m.group(1), "date": m.group(2).strip(), "sections": {}}
            current_section = None
            continue
        if current is None:
            continue
        m = SECTION_RE.match(line)
        if m:
            current_section = m.group(1).strip()
            current["sections"].setdefault(current_section, [])
            continue
        m = ENTRY_RE.match(line)
        if m and current_section:
            current["sections"][current_section].append(m.group(1).strip())
    if current:
        versions.append(current)
    return versions


def filter_user_facing(entries: Iterable[str]) -> list[str]:
    out: list[str] = []
    for e in entries:
        # Drop internal-only lines (SDK upgrades, library bumps, refactors that don't affect HCL)
        if re.search(r"^\s*upgraded\s+(sdk|go-jose|go\b)", e, re.IGNORECASE):
            continue
        if re.search(r"\b(refactor|internal|cleanup|gofmt|vendor)\b", e, re.IGNORECASE) \
                and not USER_FACING_HINTS.search(e):
            continue
        # Keep entries that mention an HCL-visible thing OR are clearly enhancement/breaking
        if USER_FACING_HINTS.search(e):
            out.append(e)
    return out


def render_page(skill: str, provider_repo: str, versions: list[dict], top_n: int) -> str:
    today = dt.date.today().isoformat()
    title = {
        "zpa": "ZPA — Recent Provider Changes",
        "zia": "ZIA — Recent Provider Changes",
        "ztc": "ZTC — Recent Provider Changes",
        "zcc": "ZCC — Recent Provider Changes",
    }.get(skill, f"{skill.upper()} — Recent Provider Changes")

    lines: list[str] = [
        f"# {title}",
        "",
        f"*Auto-generated from `{provider_repo}/CHANGELOG.md` — last updated {today}.*",
        "",
        (
            "Curated subset of recent provider releases that affect HCL users. "
            "Internal SDK bumps, library upgrades, and pure refactors are filtered out. "
            "Always cross-reference the full upstream changelog at "
            f"<https://github.com/zscaler/{provider_repo}/blob/master/CHANGELOG.md>."
        ),
        "",
    ]

    shown = 0
    for v in versions:
        if shown >= top_n:
            break
        kept_sections: dict[str, list[str]] = {}
        for sec_name, entries in v["sections"].items():
            kept = filter_user_facing(entries)
            if kept:
                kept_sections[sec_name] = kept
        if not kept_sections:
            continue
        shown += 1
        lines.append(f"## v{v['version']} — {v['date']}")
        lines.append("")
        for sec_name, kept in kept_sections.items():
            lines.append(f"### {sec_name}")
            lines.append("")
            for e in kept:
                lines.append(f"- {e}")
            lines.append("")

    if shown == 0:
        lines.append("_No user-facing changes detected in the last few releases._")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--skill", help="Only mine for this skill (zpa | zia | …)")
    p.add_argument("--top", type=int, default=10, help="How many recent versions to include")
    p.add_argument("--dry-run", action="store_true")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    failures = 0
    for skill, provider_repo, url in PROVIDERS:
        if args.skill and args.skill != skill:
            continue
        print(f"[{skill}] mining {provider_repo}")
        try:
            text = fetch_changelog(provider_repo, url)
        except Exception as e:
            print(f"  FAILED to fetch: {e}", file=sys.stderr)
            failures += 1
            continue
        versions = parse_versions(text)
        if not versions:
            print(f"  no versions parsed", file=sys.stderr)
            failures += 1
            continue
        page = render_page(skill, provider_repo, versions, args.top)
        out = REPO_ROOT / "skills" / skill / "references" / "recent-provider-changes.md"
        if args.dry_run:
            print(f"  would write {out.relative_to(REPO_ROOT)} ({len(page)} bytes)")
            continue
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(page)
        print(f"  wrote {out.relative_to(REPO_ROOT)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
