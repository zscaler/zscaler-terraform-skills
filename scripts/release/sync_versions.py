#!/usr/bin/env python3
"""Synchronize the version across .claude-plugin/marketplace.json, gemini-extension.json,
and every skills/*/SKILL.md.

Usage:
    python scripts/release/sync_versions.py 0.3.0
    python scripts/release/sync_versions.py --check     # exit 1 if any file is out of sync (no writes)
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MARKETPLACE = REPO_ROOT / ".claude-plugin" / "marketplace.json"
GEMINI_EXTENSION = REPO_ROOT / "gemini-extension.json"
SKILLS_GLOB = "skills/*/SKILL.md"

VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")
FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---", re.DOTALL)
SKILL_VERSION_RE = re.compile(r"^(\s*version:\s*)(\d+\.\d+\.\d+)\s*$", re.MULTILINE)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("version", nargs="?", help="Target SemVer version (e.g. 0.3.0)")
    g.add_argument("--check", action="store_true", help="Verify all versions in sync; exit 1 if not")
    return p.parse_args()


def read_marketplace_version() -> str:
    data = json.loads(MARKETPLACE.read_text())
    root_v = data["version"]
    plugin_v = data["plugins"][0]["version"]
    if root_v != plugin_v:
        raise SystemExit(
            f"marketplace.json: root version ({root_v}) != plugins[0].version ({plugin_v})"
        )
    return root_v


def read_gemini_extension_version() -> str:
    data = json.loads(GEMINI_EXTENSION.read_text())
    return data["version"]


def read_skill_versions() -> dict[Path, str]:
    out: dict[Path, str] = {}
    for path in sorted(REPO_ROOT.glob(SKILLS_GLOB)):
        text = path.read_text()
        m = FRONTMATTER_RE.match(text)
        if not m:
            raise SystemExit(f"{path}: no YAML frontmatter")
        fm = m.group(1)
        vm = SKILL_VERSION_RE.search(fm)
        if not vm:
            raise SystemExit(f"{path}: no `version:` line in metadata frontmatter")
        out[path] = vm.group(2)
    return out


def check() -> int:
    plugin_version = read_marketplace_version()
    skill_versions = read_skill_versions()
    gemini_version = read_gemini_extension_version()
    bad = [(p, v) for p, v in skill_versions.items() if v != plugin_version]
    if gemini_version != plugin_version:
        bad.append((GEMINI_EXTENSION, gemini_version))
    if not bad:
        print(f"OK — all versions at {plugin_version}")
        return 0
    print(f"Plugin version is {plugin_version}, but:")
    for p, v in bad:
        print(f"  {p.relative_to(REPO_ROOT)}: {v}")
    return 1


def write_marketplace(new_version: str) -> None:
    data = json.loads(MARKETPLACE.read_text())
    data["version"] = new_version
    for plugin in data["plugins"]:
        plugin["version"] = new_version
    MARKETPLACE.write_text(json.dumps(data, indent=2) + "\n")


def write_gemini_extension(new_version: str) -> None:
    data = json.loads(GEMINI_EXTENSION.read_text())
    data["version"] = new_version
    GEMINI_EXTENSION.write_text(json.dumps(data, indent=2) + "\n")


def write_skill(path: Path, new_version: str) -> None:
    text = path.read_text()
    m = FRONTMATTER_RE.match(text)
    fm = m.group(1)
    new_fm = SKILL_VERSION_RE.sub(rf"\g<1>{new_version}", fm)
    path.write_text(text.replace(fm, new_fm, 1))


def bump(new_version: str) -> int:
    if not VERSION_RE.match(new_version):
        raise SystemExit(f"not a valid SemVer x.y.z: {new_version!r}")
    write_marketplace(new_version)
    write_gemini_extension(new_version)
    for path in REPO_ROOT.glob(SKILLS_GLOB):
        write_skill(path, new_version)
    print(f"Synced all versions -> {new_version}")
    return 0


def main() -> int:
    args = parse_args()
    if args.check:
        return check()
    return bump(args.version)


if __name__ == "__main__":
    sys.exit(main())
