# CLAUDE.md

This file is for **contributors and maintainers** of this skill bundle.

> **End users:** see [README.md](README.md) for install + usage.

## What this is

A bundle of [Agent Skills](https://agentskills.io) that ground AI coding assistants in the **public Terraform interface** of the Zscaler providers. Pure Markdown. No code.

Each product (ZPA, ZIA, ZTC, ZCC) lives in its own `skills/<product>/` directory with its own `SKILL.md` and `references/`.

## Repo structure

```text
zscaler-terraform-skills/
├── .claude-plugin/marketplace.json   # One plugin, four auto-discovered skills
├── skills/
│   ├── zpa/
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── auth-and-providers.md
│   │       ├── resource-catalog.md
│   │       ├── policy-rules.md
│   │       └── troubleshooting.md
│   ├── zia/SKILL.md
│   ├── ztc/SKILL.md
│   └── zcc/SKILL.md
├── tests/baseline-scenarios.md
└── .github/workflows/validate.yml
```

The marketplace declares **one plugin**, source `./`. Claude Code (and other skill-aware hosts) auto-discover every `skills/<name>/SKILL.md` underneath — each becomes its own activatable skill.

## Authoring rules — LLM consumption

These rules optimize for the **primary reader: an LLM retrieving facts**, not a human reading end-to-end. They are **mandatory** for every PR.

1. **Decision table before playbook.** If a topic has multiple valid approaches, open with `Goal | Use | Tradeoff`. Never bury branching in prose.
2. **Cut human scaffolding.** No "Why this matters" paragraphs, no before/after diffs that just restate phase steps.
3. **Compress prose to ❌/✅ rules.** Rewrite "You should…", "Note that…", "Keep in mind…" as terse imperative bullets. One fact per bullet.
4. **Every artifact earns its tokens.** Code blocks, tables, examples must add a fact not in surrounding prose.
5. **Anchor stability.** SKILL.md routes to specific `#anchor` headings in references. You may rewrite a subsection internally; do not rename top-level `### Heading` anchors that SKILL.md links to.
6. **Retrieval-first ordering** within a section: (a) decision table, (b) default procedure, (c) alternatives, (d) ❌/✅ gotchas. Rationale ≤ 1 opening sentence.

**Token budget per reference subsection:** under 400 tokens (~1,600 chars). If larger, split or compress.

**SKILL.md target:** under 300 lines.

## Per-skill content checklist

Each `skills/<product>/SKILL.md` MUST include:

| Section                       | Why                                                                       |
| ----------------------------- | ------------------------------------------------------------------------- |
| Frontmatter                   | `name`, `description` (triggering), `license`, `metadata.version`.        |
| Response Contract             | Assumptions, provider version floor, risk, chosen remediation, validation, rollback. |
| Workflow                      | Capture context → Diagnose → Load reference → Propose → Validate → Emit.  |
| Diagnose Before You Generate  | Routing table from failure category → reference anchor.                   |
| Capture-context fields        | Provider version, auth mode, microtenant_id (ZPA), customer ID, cloud.    |
| Reference index               | One bullet per `references/*.md`.                                         |

## Frontmatter contract

```yaml
---
name: <product>-skill        # zpa-skill, zia-skill, ztc-skill, zcc-skill
description: Use when writing, reviewing, or debugging Terraform HCL that uses the <product> provider — covers <three concrete categories>.
license: MIT
metadata:
  author: Zscaler
  version: X.Y.Z
---
```

The `description` is what triggers skill activation. Make it concrete and unambiguous: name the provider, name the categories. Keep it < 1024 chars.

## Source-of-truth rules

When you write or update a reference page:

| Topic               | Source you must check first                                                              |
| ------------------- | ---------------------------------------------------------------------------------------- |
| Resource attributes | The provider's `docs/resources/<name>.md` and `docs/data-sources/<name>.md`              |
| Example HCL         | The provider's `examples/<resource_name>/*.tf`                                           |
| Auth & provider     | The provider's `docs/index.md`                                                           |
| Provider version    | The provider's `<provider>/common/version.go` or `version/version.go`                    |
| Known API quirks    | The provider's `.cursor/rules/troubleshoot-*-provider.md` (rewrite for end-user audience) |
| Recent changes      | The provider's `CHANGELOG.md`                                                            |

**Never invent attribute names.** If you can't find it in the provider's `docs/` or `examples/`, it does not exist — open an issue against the provider, not this skill.

## Versioning

`marketplace.json` (root + `plugins[0].version`) and every `skills/*/SKILL.md` `metadata.version` are kept in sync **automatically** by [semantic-release](https://github.com/semantic-release/semantic-release) on every merge to `master`. **Do not bump versions by hand in PRs.**

Pick the right [conventional commit](https://www.conventionalcommits.org/) prefix and the right release ships:

| Commit subject prefix | Effect | When to use |
|-----------------------|--------|-------------|
| `feat: …`             | Minor bump | New skill, new reference file, new capability area, **any content addition that ships to users** |
| `fix: …`              | Patch bump | Wrong attribute name, broken link, factual error, anchor mismatch |
| `perf: …`             | Patch bump | Compression / token-budget rewrite that preserves facts |
| `refactor: …`         | No release | Pure restructure with no user-visible content change |
| `docs: …`             | No release | Repo-internal docs only (this file, README, CHANGELOG cleanup) — **do not use for skill content; use `feat:` / `fix:` instead** |
| `chore: …` / `style: …` / `test: …` / `ci: …` / `build: …` | No release | Tooling, formatting, validation, workflow changes |
| `feat!: …` or `BREAKING CHANGE:` in body | Major bump | Anchor rename that breaks `SKILL.md` cross-links, removed reference file, renamed skill |

Configuration: [`.releaserc.json`](.releaserc.json). Workflow: [`.github/workflows/release.yml`](.github/workflows/release.yml).

Preview the next release locally before opening a PR:

```bash
make release-dry          # or: npx semantic-release --dry-run --no-ci
```

## Local validation

```bash
# SKILL.md line count target: < 300
wc -l skills/*/SKILL.md

# Frontmatter sanity (requires pyyaml)
python3 -c "
import yaml, glob
for path in glob.glob('skills/*/SKILL.md'):
    parts = open(path).read().split('---', 2)
    fm = yaml.safe_load(parts[1])
    missing = {'name', 'description', 'license', 'metadata'} - set(fm.keys())
    print(path, 'OK' if not missing else f'MISSING {missing}')
"

# Broken intra-reference links
for skill in skills/*/; do
  cd "$skill"
  grep -hoP '\[.*?\]\(references/.*?\.md.*?\)' SKILL.md references/*.md 2>/dev/null | \
    sed 's/.*(//' | sed 's/).*//' | sed 's/#.*//' | sort -u | \
    while read -r link; do [ ! -f "$link" ] && echo "BROKEN in $skill: $link"; done
  cd - >/dev/null
done
```

CI runs equivalent checks in `.github/workflows/validate.yml`.

## PR checklist

- [ ] Decision table precedes playbook (if multiple approaches exist)
- [ ] No "Why this matters" / "Note that…" prose — converted to ❌/✅
- [ ] Every code block / table adds a fact not in surrounding prose
- [ ] Subsection under 400 tokens
- [ ] Anchors referenced from SKILL.md remain stable
- [ ] If a new resource attribute appears in HCL, it is verifiable in the provider's `docs/resources/<name>.md`
- [ ] `tests/baseline-scenarios.md` updated if behaviour for an existing scenario changes
- [ ] Commit subject uses a [conventional commit](https://www.conventionalcommits.org/) prefix (`feat:` / `fix:` / `docs(skill):` / `chore:` / etc.) so semantic-release picks the right bump on merge — **do not edit version numbers by hand**
