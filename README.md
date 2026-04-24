# Zscaler Terraform Skills

<p align="center">
  <a href="https://www.terraform.io/">
    <img src="https://cdn.simpleicons.org/terraform/623CE4" alt="Terraform" height="60">
  </a>
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <a href="https://www.zscaler.com/">
    <img src="https://cdn.simpleicons.org/zscaler/00BCEB" alt="Zscaler" height="60">
  </a>
</p>

<p align="center">
  <a href="https://agentskills.io"><img src="https://img.shields.io/badge/Agent-Skill-5865F2" alt="Agent Skill"></a>
  <a href="https://www.terraform.io/"><img src="https://img.shields.io/badge/Terraform-1.6+-623CE4" alt="Terraform"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License"></a>
</p>

A bundle of agent skills that teach AI coding assistants (Claude Code, Cursor, Copilot, Gemini CLI, OpenCode, Codex, …) how to design and write correct Terraform HCL for the Zscaler providers. Five skills ship in this bundle:

| Skill                    | Scope                                                                                                                            |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| `zpa-skill`              | Zscaler Private Access (`zscaler/zpa`) — resource catalog, OneAPI / legacy / GOV / microtenant auth, policy rules, troubleshooting. |
| `zia-skill`              | Zscaler Internet Access (`zscaler/zia`) — resource catalog, rule ordering, activation lifecycle, troubleshooting.                |
| `ztc-skill`              | Zscaler Zero Trust Cloud (`zscaler/ztc`, formerly Cloud Branch Connector) — resource catalog, cloud-orchestrated objects, activation. |
| `zcc-skill`              | Zscaler Client Connector (`zscaler/zcc`) — resource catalog, singleton / existing-only patterns, env-var trap.                   |
| `best-practices-skill`   | Cross-cutting engineering discipline for any Zscaler-Terraform repo — state, CI/CD with the activation step, secrets, testing, modules, naming, anti-patterns. |

The four provider skills cover **provider correctness** (what attributes does this resource take, how does auth work, how do you avoid known API quirks). The best-practices skill covers **engineering discipline** (how do you structure the repo, how do you split state, how do you wire CI/CD, how do you handle secrets and testing). Install the provider skills you use plus the best-practices skill — they're designed to compose.

> **What this is not.** This repo does not help you *develop* the providers themselves (Go code, Plugin SDK, acceptance tests). It is for **end users writing HCL** that consumes the published `zscaler/*` providers. The canonical schema source for every `zpa_*`, `zia_*`, `ztc_*`, and `zcc_*` resource is the official Terraform Registry: <https://registry.terraform.io/providers/zscaler>.

## What these skills provide

### Provider correctness (zpa, zia, ztc, zcc)

- Resource catalog per provider with minimum-viable HCL grounded in the live Registry
- OneAPI vs legacy v3 vs GOV authentication patterns; multi-cloud vanity-domain handling
- Microtenant scoping (`microtenant_id`) for the ZPA resources that actually accept it
- Policy-rule operand structures (ZPA access policy, ZIA URL filtering, ZTC firewall) — the parts that aren't obvious from the schema
- Activation lifecycle: which products require it (ZIA, ZTC) and which don't (ZPA, ZCC)
- Known API quirks distilled from real customer support cases

### Engineering discipline (best-practices)

- State organization for multi-microtenant, multi-team Zscaler estates
- The Zscaler activation step in CI pipelines (frequently forgotten by base LLMs)
- Secret handling: OneAPI rotation, the `ZSCALER_*` vs `<product>_*` env-var trap, write-only / ephemeral variables (Terraform 1.11+)
- Module patterns sized to Zscaler API granularity, not generic AWS-shaped boilerplate
- Naming, variables, outputs, and 30+ documented anti-patterns specific to Zscaler resource graphs

### Testing strategy

- Three-layer test pyramid: `unit.tftest.hcl` (plan-only, no creds) → `mock.tftest.hcl` (`mock_provider`, Terraform 1.7+) → `integration.tftest.hcl` (sandbox tenant only)
- When to use `terraform test` vs Terratest for Zscaler workloads
- Sandbox-tenant guardrails — never run integration tests against production credentials

### CI/CD workflows

- GitHub Actions templates that include the activation step
- OIDC against Zidentity (preferred) vs long-lived OneAPI client secrets
- Drift detection, scheduled plans, PR-test/apply-on-merge gates with `terraform validate` + `terraform plan -out`

### Security & secrets

- OneAPI client rotation strategy and per-environment scoping (sandbox vs production tenants)
- Write-only / ephemeral variables for `client_secret` handling (Terraform 1.11+)
- The provider env-var trap that silently authenticates against the wrong namespace

### Quick reference

- Decision tables for the most common HCL questions (`count` vs `for_each`, module split, state split, OneAPI vs legacy)
- ❌/✅ rules covering the most common Zscaler-Terraform mistakes

## Why a skill?

Base LLMs hallucinate against non-AWS/Azure/GCP providers — they invent ZPA attribute names, miss required fields, get policy-rule operand structures wrong, and skip the Zscaler-specific activation step in CI. These skills ground the model in:

- The exact resources each provider exposes, with canonical minimum-viable HCL.
- Provider-config + auth (OneAPI vs legacy, env vars, multi-cloud).
- Policy-rule semantics that aren't obvious from the schema (operands, ordering, conditional fields).
- Known API quirks distilled from real customer support cases.
- Engineering discipline that's specifically different from generic Terraform: per-microtenant state organization, the activation step in CI, OIDC against Zidentity, the `ZSCALER_*` vs `<product>_*` env-var trap.

## Install

### Quick install (any agent)

```bash
npx skills add https://github.com/zscaler/zscaler-terraform-skills
```

### Per-host

<details>
<summary>Claude Code</summary>

```bash
/plugin marketplace add zscaler/zscaler-terraform-skills
/plugin install zscaler-terraform-skills@zscaler
```

</details>

<details>
<summary>Cursor</summary>

```bash
git clone https://github.com/zscaler/zscaler-terraform-skills.git ~/.cursor/skills/zscaler-terraform-skills
```

Cursor auto-discovers any `skills/<name>/SKILL.md` underneath.

</details>

<details>
<summary>Gemini CLI</summary>

Install as a Gemini CLI extension (recommended — auto-discovers all five skills via the `skills/` directory):

```bash
gemini extensions install https://github.com/zscaler/zscaler-terraform-skills --consent --auto-update
```

- `--consent` — acknowledge the standard third-party-extension warning non-interactively.
- `--auto-update` — pull in the next semantic-release tag automatically (recommended for skill content that ships frequently).

Update / uninstall:

```bash
gemini extensions update zscaler-terraform-skills      # only needed if --auto-update is off
gemini extensions uninstall zscaler-terraform-skills
```

If you'd rather not use the extension subsystem, clone the repo into one of Gemini CLI's skill discovery tiers instead:

```bash
git clone https://github.com/zscaler/zscaler-terraform-skills ~/.gemini/skills/zscaler-terraform-skills
```

</details>

## How it works

This is one **plugin** with five **skills**:

```text
zscaler-terraform-skills/
├── .claude-plugin/marketplace.json
├── skills/
│   ├── zpa/                  # Router for ZPA HCL questions
│   │   ├── SKILL.md
│   │   └── references/       # On-demand depth
│   ├── zia/SKILL.md          # Router for ZIA HCL questions
│   ├── ztc/SKILL.md          # Router for ZTC HCL questions
│   ├── zcc/SKILL.md          # Router for ZCC HCL questions
│   └── best-practices/       # Router for cross-cutting engineering questions
│       ├── SKILL.md
│       └── references/       # state, ci-cd, security, testing, quick-ref, …
└── tests/baseline-scenarios.md
```

Each `SKILL.md` has a YAML `description` that triggers it. The agent picks the right skill based on the question — *"Create a ZPA application segment for finance.example.com"* loads `zpa-skill`; *"How should I split state for a multi-microtenant ZPA setup?"* loads `best-practices-skill`. The two compose: the best-practices skill cross-references the provider skills for resource-level details, and the provider skills cross-reference the best-practices skill for engineering questions.

Every router follows the same shape:

1. **Capture context** (provider version, auth mode, microtenant, OneAPI vs legacy, environment criticality).
2. **Diagnose intent** via a routing table.
3. **Load only the matching reference** under `references/`.
4. **Emit answer** ending with the Response Contract (assumptions, risk, validation, rollback).

## Verify install

After install, try:

```text
"Create a ZPA application segment that exposes crm.example.com on TCP 443 to a SCIM group called Engineering."
```

The agent should: name the provider version floor (`~> 4.0`), pick `zpa_application_segment`, wire `segment_group_id` + `server_groups`, and finish with a `terraform validate` + `terraform plan -out` validation block.

## Quick start examples

Provider-specific (load `zpa-skill` / `zia-skill` / `ztc-skill` / `zcc-skill`):

- `"Create a ZPA access policy that allows Engineering SCIM group to a CRM application segment from posture-compliant devices."`
- `"Set up ZPA provider authentication using OneAPI client credentials with environment variables."`
- `"Why does my ZPA policy rule keep showing drift on the conditions block after every refresh?"`
- `"Add a ZIA URL filtering rule that blocks gambling categories for the Sales department, ordered after the existing predefined rules."`
- `"Wire the ZIA activation step into my GitHub Actions apply job."`

Cross-cutting (load `best-practices-skill`):

- `"How should I split Terraform state for a ZPA + ZIA setup with three microtenants and two teams?"`
- `"Write me a GitHub Actions pipeline for ZIA that PR-tests, applies on merge, and includes the activation step."`
- `"What's the right pattern for OIDC against Zidentity from a CI workflow instead of long-lived client secrets?"`
- ``"Show me how to test a ZIA URL filtering module with `terraform test` against a sandbox tenant."``
- ``"Quick: do I use `count` or `for_each` for a list of ZPA application segments, and why?"``

## What it covers

### Provider skills (zpa, zia, ztc, zcc)

Each provider skill ships a `SKILL.md` router plus a focused set of references:

| Skill | References |
|-------|-----------|
| `zpa-skill` | `auth-and-providers.md`, `resource-catalog.md`, `policy-rules.md`, `troubleshooting.md`, `recent-provider-changes.md` |
| `zia-skill` | `auth-and-providers.md`, `resource-catalog.md`, `rules-and-ordering.md`, `activation.md`, `troubleshooting.md`, `recent-provider-changes.md` |
| `ztc-skill` | `auth-and-providers.md`, `resource-catalog.md`, `rules-and-ordering.md`, `troubleshooting.md`, `recent-provider-changes.md` |
| `zcc-skill` | `auth-and-providers.md`, `resource-catalog.md`, `troubleshooting.md`, `recent-provider-changes.md` |

`recent-provider-changes.md` is regenerated by `scripts/changelog/mine.py` from each provider's upstream `CHANGELOG.md`, filtered to surface only HCL-visible changes (new resources, attribute additions, breaking renames). Internal SDK bumps and refactors are dropped.

### Testing strategy

A three-layer pyramid documented in `skills/best-practices/references/testing-and-validation.md`:

| Layer | File | Terraform | Credentials | What it verifies |
|-------|------|-----------|-------------|------------------|
| **Unit** | `tests/unit.tftest.hcl` | 1.6+ | none | Variable validation, `locals` math, plan-only sanity |
| **Mock wiring** | `tests/mock.tftest.hcl` | 1.7+ | none | Module output wiring and resource-attribute propagation via `mock_provider` |
| **Integration** | `tests/integration.tftest.hcl` | 1.6+ | sandbox tenant only | Real Zscaler API acceptance — never against production |

The skill also covers when `terraform test` is enough vs when Terratest (Go) makes sense for Zscaler workloads, and the activation-step gotchas in tests for ZIA / ZTC modules.

### CI/CD workflows

`skills/best-practices/references/ci-cd-zscaler.md` covers Zscaler-specific CI patterns that generic Terraform CI templates miss:

- **The activation step.** ZIA and ZTC require an explicit activation API call after every successful apply or the configuration sits inactive on the tenant. The reference shows how to wire it into both GitHub Actions and GitLab CI.
- **OIDC against Zidentity** as a replacement for long-lived OneAPI client secrets in CI runners.
- **Per-environment workflow split** (sandbox-on-PR, prod-on-merge-with-approval).
- **Drift detection** scheduled plans against the Zscaler tenants.

### State management

`skills/best-practices/references/state-management.md` covers state organization scaled to Zscaler estates:

- Per-microtenant state files vs single state with `for_each` over microtenants
- Splitting state across `zpa-platform / zpa-policies / zia-policies / ztc-rules` for blast-radius isolation
- Backend choice + locking for Zscaler workflows
- `terraform_remote_state` and `moved {}` block patterns for safe refactors

### Security & secrets

`skills/best-practices/references/security-and-compliance.md` covers:

- OneAPI client rotation strategy and per-environment scoping
- The `ZSCALER_*` vs `<product>_*` env-var trap (most common ZCC / ZPA auth confusion)
- Write-only (`*_wo`) and ephemeral variables for `client_secret` handling on Terraform 1.11+
- Trivy / Checkov scanning hooked into the Zscaler workflow

### Patterns and anti-patterns

- `coding-practices.md` — `count` vs `for_each` vs `dynamic`, `locals`, dynamic blocks (with the ZPA policy-operand example), variable validation, dependency management
- `module-patterns.md` — module shapes, required files, boundaries (no mixed providers per module), composition, examples directory structure
- `naming-conventions.md` — Terraform resource addresses vs Zscaler portal names, naming patterns per resource type
- `variables-and-outputs.md` — typed variables with `optional()`, validation blocks, sensitive handling, output design for `for_each` collections
- `versioning.md` — provider/Terraform constraints, lockfile discipline, module SemVer, `moved {}` blocks for safe renames, OneAPI migration strategy
- `anti-patterns.md` — quick-index of 30+ Zscaler-Terraform anti-patterns, cross-linked to the file that explains the right pattern

## Why these skills

**Sources:**

- The four published Zscaler provider repos: [`terraform-provider-zpa`](https://github.com/zscaler/terraform-provider-zpa), [`terraform-provider-zia`](https://github.com/zscaler/terraform-provider-zia), [`terraform-provider-ztc`](https://github.com/zscaler/terraform-provider-ztc), `terraform-provider-zcc`
- De-identified customer support patterns from real Zscaler-Terraform engagements
- Engineering discipline patterns from [terraform-best-practices.com](https://www.terraform-best-practices.com/) adapted to Zscaler API granularity

**Version-specific guidance:**

- Terraform 1.6+ (`terraform test` framework)
- Terraform 1.7+ (`mock_provider` for offline testing)
- Terraform 1.11+ (`write_only` / ephemeral variables for secret handling)
- Provider versions explicitly tracked: ZPA `~> 4.0`, ZIA `~> 4.0`, ZTC `~> 1.0`, ZCC (forthcoming)

**Decision frameworks** — the skills don't just teach "what" but "when and why" for: state split granularity, microtenant scoping, OneAPI vs legacy, activation step strategy, test-layer choice, module boundaries.

## Requirements

- A skill-aware AI host: Claude Code, Cursor, Copilot, Gemini CLI, OpenCode, Codex, or any [Agent Skills](https://agentskills.io)-compatible tool
- Terraform 1.6+ or OpenTofu 1.8+ (1.7+ recommended for `mock_provider` tests; 1.11+ for `write_only` / ephemeral variables)
- Zscaler tenant credentials (OneAPI client preferred, legacy v3 supported)
- For OneAPI: Zidentity migration completed on the target tenant
- Optional: a sandbox tenant for integration tests; an OIDC issuer (e.g. GitHub Actions) for CI-against-Zidentity

## Local development

A `Makefile` ships with the targets used by CI. Run them locally before opening a PR:

```bash
make help              # Show all targets
make validate          # Run every check below in one go (mirrors CI)
make check-frontmatter # Validate YAML frontmatter in every SKILL.md
make check-links       # Verify every internal references/*.md link resolves
make check-line-counts # Warn if any SKILL.md exceeds the 300-line budget
make check-versions    # Verify marketplace.json and every SKILL.md agree
make line-counts       # Print line counts for every SKILL.md and reference
make lint              # Lint all markdown via markdownlint (uses .markdownlint.json)
make lint-fix          # Auto-fix every issue markdownlint can fix
make release-dry       # Preview what semantic-release would publish next (no writes)
```

Markdown style is enforced by [`markdownlint-cli`](https://github.com/igorshubovych/markdownlint-cli) against the rules in `.markdownlint.json`. Install once with `npm install -g markdownlint-cli`. CI runs the same check on every PR via `DavidAnson/markdownlint-cli2-action`.

## Releases

Releases are fully automated by [semantic-release](https://github.com/semantic-release/semantic-release). The release workflow runs on every merge to `master`, parses the [conventional commit](https://www.conventionalcommits.org/) messages since the last tag, and decides the next version, the CHANGELOG entry, and the GitHub release notes from them.

**You never bump versions by hand.** Just write conventional commits and merge.

| Commit subject prefix | Effect |
|-----------------------|--------|
| `feat: …`             | Minor bump (e.g. `0.1.0` → `0.2.0`) — **use for new skill content / new reference files / new capability areas** |
| `fix: …`              | Patch bump (e.g. `0.1.0` → `0.1.1`) — **use for factual corrections, wrong attribute names, broken links** |
| `perf: …`             | Patch bump |
| `docs: …` / `refactor: …` / `chore: …` / `style: …` / `test: …` / `ci: …` / `build: …` | No release |
| `feat!: …` or any commit body containing `BREAKING CHANGE:` | Major bump (anchor renames, removed reference files) |

> Skill content changes are the product, so use `feat:` / `fix:`. `docs:` is for repo-internal docs (README, CLAUDE.md) that don't ship to skill consumers.

What semantic-release does on every release:

1. Computes the next version from commits since the last tag.
2. Runs `python3 scripts/release/sync_versions.py <next_version>` to write the new version into `.claude-plugin/marketplace.json` and every `skills/*/SKILL.md` frontmatter.
3. Prepends a categorized entry to `CHANGELOG.md`.
4. Commits the version files + changelog back to `master` as `chore(release): X.Y.Z [skip ci]`.
5. Creates an annotated `vX.Y.Z` git tag.
6. Publishes a GitHub Release with the generated notes.

Preview the next release locally without publishing (semantic-release and its plugins are pulled on demand via `npx` — no `package.json` is checked in):

```bash
make release-dry
```

Configuration lives in [`.releaserc.json`](.releaserc.json) and the workflow in [`.github/workflows/release.yml`](.github/workflows/release.yml), which uses [`cycjimmy/semantic-release-action`](https://github.com/cycjimmy/semantic-release-action) to install plugins inline.

## Contributing

See [CLAUDE.md](CLAUDE.md) for the LLM-consumption authoring rules and content structure. PRs that add or change skill content must include a before/after baseline scenario in `tests/baseline-scenarios.md`. Bug reports and feature requests via GitHub Issues.

## Related resources

### Zscaler official

- [Zscaler Provider Registry](https://registry.terraform.io/providers/zscaler) — canonical schema for every `zpa_*`, `zia_*`, `ztc_*`, `zcc_*` resource
- [`zscaler/terraform-provider-zpa`](https://github.com/zscaler/terraform-provider-zpa)
- [`zscaler/terraform-provider-zia`](https://github.com/zscaler/terraform-provider-zia)
- [`zscaler/terraform-provider-ztc`](https://github.com/zscaler/terraform-provider-ztc)
- [Zscaler Help Center](https://help.zscaler.com/)
- [Zscaler OneAPI / Zidentity overview](https://help.zscaler.com/oneapi/about-oneapi)

### Terraform & OpenTofu

- [Terraform Language documentation](https://developer.hashicorp.com/terraform/docs)
- [Terraform Testing (`terraform test`)](https://developer.hashicorp.com/terraform/language/tests)
- [Mock Providers](https://developer.hashicorp.com/terraform/language/tests/mocking)
- [OpenTofu documentation](https://opentofu.org/docs/)
- [HashiCorp Recommended Practices](https://developer.hashicorp.com/terraform/cloud-docs/recommended-practices)

### Community

- [terraform-best-practices.com](https://terraform-best-practices.com) — the engineering-discipline foundation we extend for Zscaler
- [Awesome Terraform](https://github.com/shuaibiyy/awesome-tf)
- [Terratest](https://terratest.gruntwork.io/docs/) — Go testing framework, reference for when `terraform test` isn't enough

### Development tools

- [pre-commit-terraform](https://github.com/antonbabenko/pre-commit-terraform) — pre-commit hooks for Terraform
- [terraform-docs](https://terraform-docs.io/) — generate documentation from modules
- [terraform-switcher](https://github.com/warrensbox/terraform-switcher) — Terraform version manager
- [TFLint](https://github.com/terraform-linters/tflint) — Terraform linter
- [Trivy](https://github.com/aquasecurity/trivy) — IaC security scanner
- [Checkov](https://www.checkov.io/) — IaC policy-as-code scanner

## License

MIT — see [LICENSE](LICENSE).
