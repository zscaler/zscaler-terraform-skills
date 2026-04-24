#!/usr/bin/env python3
"""Verify every relative `references/*.md` link in SKILL.md and reference files resolves."""
from __future__ import annotations

import glob
import os
import re
import sys


PATTERN = re.compile(r"\[[^\]]*\]\((references/[^)#]+)(?:#[^)]*)?\)")


def main() -> int:
    paths = sorted(
        glob.glob("skills/*/SKILL.md") + glob.glob("skills/*/references/*.md")
    )
    broken: list[str] = []
    for path in paths:
        if "/references/" in path:
            skill_dir = path.split("/references/")[0]
        else:
            skill_dir = os.path.dirname(path)
        for match in PATTERN.findall(open(path).read()):
            target = os.path.join(skill_dir, match)
            if not os.path.isfile(target):
                broken.append(f"BROKEN  {path} -> {match}  (resolved: {target})")

    if broken:
        print("\n".join(broken))
        print(f"\n\033[31;01m{len(broken)} broken internal link(s).\033[0m")
        return 1

    print("\033[0;32mAll internal links resolve.\033[0m")
    return 0


if __name__ == "__main__":
    sys.exit(main())
