# CLAUDE.md

This file is for **contributors and maintainers** of this skill bundle.

> **End users:** see [README.md](README.md) for install + usage.

## What this is

A bundle of [Agent Skills](https://agentskills.io) that ground AI coding assistants in the **public Terraform interface** of the Zscaler providers. Pure Markdown. No code.

Five skills ship together:

- Four product skills — `zpa`, `zia`, `ztc`, `zcc` — each in its own `skills/<product>/` directory with its own `SKILL.md` and `references/`.
- One cross-cutting skill — `best-practices` — covering state organization, CI/CD, testing, secret handling, module shape, anti-patterns.

## Repo structure

```text
zscaler-terraform-skills/
├── .claude-plugin/marketplace.json    # Claude Code plugin manifest (root + plugins[0].version)
├── gemini-extension.json              # Gemini CLI extension manifest (auto-discovers skills/)
├── GEMINI.md                          # contextFileName for the Gemini extension
├── skills/
│   ├── zpa/
│   │   ├── SKILL.md                   # Router — < 300 lines
│   │   └── references/                # On-demand depth — auth, resource catalog, policies, troubleshooting, recent-provider-changes
│   ├── zia/{SKILL.md,references/}
│   ├── ztc/{SKILL.md,references/}
│   ├── zcc/{SKILL.md,references/}
│   └── best-practices/
│       ├── SKILL.md
│       └── references/                # state, ci-cd, security, testing, module patterns, naming, variables, versioning, anti-patterns, quick-ref
├── scripts/
│   ├── check_frontmatter.py           # called by `make check-frontmatter`
│   ├── check_links.py                 # called by `make check-links`
│   ├── release/sync_versions.py       # called by semantic-release @exec on every release
│   └── changelog/mine.py              # mines provider CHANGELOGs into references/recent-provider-changes.md
├── tests/baseline-scenarios.md
├── Makefile                           # validate / lint / release-dry targets
├── .markdownlint.json + .markdownlintignore
├── .releaserc.json                    # semantic-release config
└── .github/workflows/
    ├── validate.yml                   # PR validation (frontmatter, links, line counts, version sync, markdownlint)
    └── release.yml                    # cycjimmy/semantic-release-action on push to master
```

`marketplace.json` declares **one plugin**, source `./`. Claude Code, Cursor, Gemini CLI, and any other skill-aware host auto-discover every `skills/<name>/SKILL.md` underneath — each becomes its own activatable skill.

## Distribution channels

This one repo ships through five installer surfaces. **Any change to `marketplace.json`, `gemini-extension.json`, a `SKILL.md` `name:`/`description:`, or a top-level reference anchor potentially affects all five.** Don't rename without checking.

| Channel | Reads | Surfaces |
|---------|-------|----------|
| Claude Code marketplace | `.claude-plugin/marketplace.json` | `/plugin install zscaler-terraform-skills@zscaler` |
| Gemini CLI extension | `gemini-extension.json` + `GEMINI.md` + `skills/*/SKILL.md` | `gemini extensions install <repo>` |
| GitHub CLI | `skills/*/SKILL.md` (frontmatter `name:`) + git tags | `gh skill install zscaler/zscaler-terraform-skills [skill-name] [--pin v0.x.y]` |
| `npx skills` (cross-agent) | `skills/*/SKILL.md` | `npx skills add <repo>` |
| Manual clone | `skills/*/SKILL.md` | `git clone <repo> ~/.cursor/skills/...` (Cursor, etc.) |

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
name: <product>-skill        # zpa-skill, zia-skill, ztc-skill, zcc-skill, best-practices-skill
description: Use when writing, reviewing, or debugging Terraform HCL that uses the <product> provider — covers <three concrete categories>.
license: MIT
metadata:
  author: Zscaler
  version: X.Y.Z              # auto-synced — never edit by hand
---
```

The `name:` field is what users type into `gh skill install zscaler/zscaler-terraform-skills <name>`. Renaming it is a **breaking change** for pinned installs.

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

Four version fields are kept in lockstep **automatically** by [semantic-release](https://github.com/semantic-release/semantic-release) on every merge to `master`:

1. `.claude-plugin/marketplace.json` → `version` (root)
2. `.claude-plugin/marketplace.json` → `plugins[0].version`
3. `gemini-extension.json` → `version`
4. Every `skills/*/SKILL.md` → `metadata.version` (frontmatter)

The sync is driven by `scripts/release/sync_versions.py`, invoked from `.releaserc.json` `@semantic-release/exec` `prepareCmd`. **Do not bump versions by hand in PRs** — the next release commit will overwrite them anyway.

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

Use the `Makefile` — these are the same checks `.github/workflows/validate.yml` runs on every PR:

```bash
make validate            # runs every check below in one go
make check-frontmatter   # YAML frontmatter shape + required keys
make check-links         # all internal references/*.md links resolve
make check-line-counts   # warn if any SKILL.md exceeds the 300-line budget
make check-versions      # marketplace.json + gemini-extension.json + every SKILL.md agree
make line-counts         # print line counts for SKILL.md + every reference file
make lint                # markdownlint against .markdownlint.json
make lint-fix            # auto-fix every issue markdownlint can fix
make release-dry         # preview what semantic-release would publish next (no writes)
```

Markdown style is enforced by `markdownlint-cli` against `.markdownlint.json` (install once: `npm install -g markdownlint-cli`).

## PR checklist

- [ ] `make validate` passes locally
- [ ] Decision table precedes playbook (if multiple approaches exist)
- [ ] No "Why this matters" / "Note that…" prose — converted to ❌/✅
- [ ] Every code block / table adds a fact not in surrounding prose
- [ ] Subsection under 400 tokens
- [ ] Anchors referenced from SKILL.md remain stable (a rename of a top-level `### Heading` in any reference file is a **breaking change** — use `feat!:` or `BREAKING CHANGE:`)
- [ ] No skill `name:` field renamed without `feat!:` (breaks `gh skill install … <name> --pin v…`)
- [ ] If a new resource attribute appears in HCL, it is verifiable in the provider's `docs/resources/<name>.md`
- [ ] `tests/baseline-scenarios.md` updated if behaviour for an existing scenario changes
- [ ] Commit subject uses a [conventional commit](https://www.conventionalcommits.org/) prefix (`feat:` for new content, `fix:` for corrections, `docs:` for repo-internal docs only, `chore:` for tooling) so semantic-release picks the right bump on merge — **do not edit version numbers by hand**
