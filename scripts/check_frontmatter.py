#!/usr/bin/env python3
"""Validate YAML frontmatter in every skills/*/SKILL.md.

Mirrors the `validate.yml` GitHub Actions workflow so contributors can run the same checks locally.
"""
from __future__ import annotations

import glob
import sys

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


REQUIRED_KEYS = {"name", "description", "license", "metadata"}
REQUIRED_METADATA = {"author", "version"}
DESCRIPTION_PREFIX = "Use when"
DESCRIPTION_MAX_LEN = 1024


def main() -> int:
    failed = False
    for path in sorted(glob.glob("skills/*/SKILL.md")):
        content = open(path).read()
        parts = content.split("---", 2)
        if len(parts) < 3:
            print(f"FAIL  {path}: missing YAML frontmatter")
            failed = True
            continue

        fm = yaml.safe_load(parts[1]) or {}

        missing = REQUIRED_KEYS - set(fm)
        if missing:
            print(f"FAIL  {path}: missing top-level keys {sorted(missing)}")
            failed = True

        meta = fm.get("metadata") or {}
        missing_meta = REQUIRED_METADATA - set(meta)
        if missing_meta:
            print(f"FAIL  {path}: missing metadata keys {sorted(missing_meta)}")
            failed = True

        desc = fm.get("description", "")
        if not desc.startswith(DESCRIPTION_PREFIX):
            print(f'FAIL  {path}: description must start with "{DESCRIPTION_PREFIX} ..."')
            failed = True
        if len(desc) > DESCRIPTION_MAX_LEN:
            print(f"FAIL  {path}: description > {DESCRIPTION_MAX_LEN} chars ({len(desc)})")
            failed = True

        if not failed:
            print(f"  ok  {path}  ({len(desc)} chars)")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
