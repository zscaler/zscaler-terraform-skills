---
name: best-practices-skill
description: Use when designing the structure, CI/CD, state organization, testing strategy, security pipeline, or operational pattern of a Terraform repository that uses any Zscaler provider (zpa, zia, ztc, zcc). Cross-cutting engineering discipline that complements the per-product zpa-skill / zia-skill / ztc-skill / zcc-skill — covers state backends and per-tenant / per-microtenant blast-radius decisions, CI/CD pipelines that include the Zscaler activation step, OIDC against Zidentity, secret handling (write_only on 1.11+, no credentials in tfvars/state), Trivy/Checkov for HCL scanning, native terraform test against sandbox tenants, mock providers, module composition, naming, versioning, anti-patterns, and a DO/DON'T quick reference.
license: MIT
metadata:
  author: Zscaler
  version: 0.0.0
---

# Zscaler Terraform — Best Practices Skill

Diagnose-first guidance for **how to structure, ship, and operate** Terraform repositories that consume the Zscaler providers. This skill is **provider-agnostic across the four Zscaler products** — for resource-level catalog, auth, and lifecycle quirks of a specific provider, route to `zpa-skill` / `zia-skill` / `ztc-skill` / `zcc-skill`.

**Scope:** state organization, CI/CD shape, secret handling, testing strategy, module patterns, naming, versioning, anti-patterns. Things that don't belong in any single provider skill because they apply to all of them — and are different enough from generic Terraform to need Zscaler-specific guidance.

## Response Contract

Every best-practices response must include:

1. **Assumptions & version floor** — Terraform/OpenTofu version, which Zscaler providers are in scope, runtime environment (local/CI/Cloud), team size, environment criticality.
2. **Risk category addressed** — one or more of: state organization, blast radius, secret exposure, CI drift, activation-in-CI gap, testing gap, compliance gap, module-boundary violation, version drift, anti-pattern.
3. **Chosen approach & tradeoffs** — what was chosen, what was traded off, why.
4. **Validation plan** — commands tailored to the change (`fmt -check`, `validate`, `plan -out`, `trivy config`, `checkov`, `terraform test`).
5. **Rollback / recovery** — for any state-mutating change: how to undo, what evidence to retain (especially for activation-bearing changes).

Never recommend `terraform state rm` against any Zscaler resource (orphans the API object — see provider skills' troubleshooting).

## Workflow

1. **Capture context** (fields below).
2. **Diagnose discipline gap(s)** using the routing table.
3. **Load only the matching reference file(s).**
4. **Propose the change** with risk controls (tests, approvals, rollback).
5. **Cross-link** the relevant provider skill(s) for resource-level details.
6. **Validate** before finalizing.
7. **Emit the Response Contract.**

## Capture Context — Fields to Confirm

| Field                     | Why it matters                                                                                                                | Default if missing                              |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| Providers in scope        | Which of `zpa` / `zia` / `ztc` / `zcc` does this repo or change touch?                                                        | Ask. Don't assume single-provider.              |
| Tenants & microtenants    | One tenant or many? Microtenants? Same Zidentity org or separate? Drives state-org and CI fan-out.                            | Ask. Don't assume single-tenant.                |
| Auth path                 | OneAPI (Zidentity) vs Legacy v3. CI secret model differs (OneAPI client creds vs legacy username/password/api_key).           | Ask. Don't default — see provider skill auth refs. |
| Execution path            | Local / GitHub Actions / GitLab CI / Atlantis / Terraform Cloud / Spacelift.                                                  | Ask.                                            |
| Environment criticality   | Sandbox / non-prod / prod. Drives approval model, plan-artifact requirement, activation gating.                               | Treat as prod unless told otherwise.            |
| Activation discipline     | Is `<product>_activation_status` (ZIA / ZTC) included in the same state, separate stage, or done manually?                   | Ask. Strongly recommend in-state for ZIA/ZTC.   |
| Terraform runtime version | Affects `optional()`, `moved`, `import`, `removed`, `write_only`, mock providers, `use_lockfile`.                              | Assume `terraform ~> 1.9`.                      |

## Diagnose Before You Generate

| Discipline gap                          | Symptoms                                                                                                                 | Primary references                                                                                            |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| **State organization / blast radius**   | One state file for all Zscaler resources, microtenant teams blocked on each other's plans, locks held for hours          | [State Management](references/state-management.md)                                                            |
| **CI/CD shape**                         | "How do I PR-test policy changes?", forgot activation step in CI, secrets baked into pipeline YAML, `plan` re-run in apply job | [CI/CD](references/ci-cd-zscaler.md)                                                                          |
| **Activation forgotten in CI**          | Apply succeeds but ZIA/ZTC console shows no change, `<product>_activation_status` missing from CI flow                    | [CI/CD: Activation Step](references/ci-cd-zscaler.md#activation-as-a-pipeline-stage)                          |
| **Secret exposure / compliance**        | `client_secret` in `.tfvars`, in state, in CI logs; long-lived credentials instead of OIDC                               | [Security & Compliance](references/security-and-compliance.md)                                                |
| **Testing strategy**                    | "How do I validate before merge?", no sandbox tenant, mock vs real provider confusion, computed-value assertions failing | [Testing & Validation](references/testing-and-validation.md)                                                  |
| **Module structure / boundaries**       | "One module or three?", mixing ZPA + ZIA in one module, kitchen-sink god module, lifecycle confusion                     | [Module Patterns](references/module-patterns.md)                                                              |
| **Coding shape (loops, locals, dynamic)** | `count` over a list shifting addresses, hardcoded IDs, `dynamic` block where static would do, validation gaps           | [Coding Practices](references/coding-practices.md)                                                            |
| **Naming, layout, drift**               | Inconsistent resource names, file-organization confusion, `"this"` everywhere, opaque variable names                     | [Naming Conventions](references/naming-conventions.md)                                                        |
| **Variables and outputs**               | Weak typing (`any`), parallel lists, missing validation, exposing entire resources                                       | [Variables and Outputs](references/variables-and-outputs.md)                                                  |
| **Versioning / lockfile / upgrades**    | Provider upgrade broke prod, no lockfile committed, exact pin blocks fixes, `init -upgrade` in feature PR                | [Versioning](references/versioning.md)                                                                        |
| **Anti-patterns / "is this OK?"**       | Recurring footguns: state rm, `provider {}` in modules, manual activation, mixed env vars                                | [Anti-Patterns](references/anti-patterns.md)                                                                  |
| **Quick lookup / DO-DON'T**             | Cheat-sheet question, naming question, "is X allowed?"                                                                   | [Quick Reference](references/quick-reference.md)                                                              |

## Cross-Cutting Principles (Compressed)

These apply to every Zscaler-Terraform repo regardless of which provider you use. Detailed playbooks live in the references; this section is the fast-path.

### Never store credentials in code or state

- ❌ `client_secret`, `password`, `api_key`, `private_key` in `.tfvars` checked into git.
- ❌ `client_secret` in a Terraform variable on Terraform `< 1.11` (it ends up in state, even with `sensitive = true`).
- ✅ Source from env vars in CI (`ZSCALER_CLIENT_SECRET`, `ZSCALER_PRIVATE_KEY`, `ZIA_API_KEY`, etc.).
- ✅ On Terraform `1.11+`, use `write_only` arguments (`*_wo`) to keep credentials out of state entirely.
- ✅ Prefer OIDC federation (GitHub Actions → Zidentity) over long-lived static keys when available.

See [Security & Compliance](references/security-and-compliance.md).

### Never `terraform state rm` a Zscaler resource

The API object stays orphaned. Use `terraform apply -target=` (selective destroy) or `removed` blocks (Terraform 1.7+) instead. See each provider skill's troubleshooting for product-specific recovery.

### Activation is a pipeline stage, not an afterthought (ZIA & ZTC)

- ❌ Apply ZIA/ZTC resources without `<product>_activation_status` in the same state.
- ❌ Manual console activation in production CI flows (no audit trail, race-prone).
- ✅ Include `zia_activation_status` / `ztc_activation_status` as a `depends_on` resource at the bottom of the same state.
- ✅ For multi-stage pipelines, the activation stage is its own job that depends on the apply stage's success — never re-run plan inside the apply job.
- ZPA & ZCC have no activation step — changes take effect on apply.

See [CI/CD: Activation as a Pipeline Stage](references/ci-cd-zscaler.md#activation-as-a-pipeline-stage).

### One state per blast-radius boundary, not per provider

- ❌ All ZPA + ZIA + ZTC + ZCC in one state file (any change blocks every team's plans).
- ❌ One state per microtenant if there are 100 of them (lockfile fan-out, no CI parallelism).
- ✅ Split state on **policy ownership boundary**: who reviews and approves changes to this set of resources? That's a state.
- ✅ Common starter shape: per-product, per-environment, per-microtenant-cohort.

See [State Management](references/state-management.md).

### Use `for_each` over `count` for any list of named Zscaler objects

`count` over a list reshuffles every address when an item is removed from the middle — meaning a single removed app segment can churn every downstream `zpa_application_segment` resource. Use `for_each = toset(...)` or `for_each = map`. The only safe `count` is the boolean `count = condition ? 1 : 0` toggle for an optional resource.

### Pin runtime, providers, and the lockfile

- `required_version = "~> 1.9"` (or your floor).
- `version = "~> 4.0"` for `zscaler/zpa`, `zscaler/zia`, `zscaler/ztc`; `version = "~> 0.1"` for the not-yet-1.0 `zscaler/zcc`.
- Commit `.terraform.lock.hcl`. Updates are a separate PR from feature work.

### Test before you ship — even if "test" means a sandbox tenant

- ✅ Static analysis (`fmt -check`, `validate`, `tflint`) on every PR — free, instant.
- ✅ `terraform plan` against a non-prod tenant on every PR.
- ✅ `terraform test` (Terraform 1.6+) for input-validation coverage.
- ⚠️ Mock providers (1.7+) help with input shape but **cannot** validate Zscaler API behavior — pair with sandbox-tenant integration on merge to main.
- ✅ Tag any test-created resources for cleanup; have a sweeper job.

See [Testing & Validation](references/testing-and-validation.md).

## Module Hierarchy (when you decide to build modules)

| Type                       | When to use                                                       | Zscaler example                                                                                |
| -------------------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| **Resource module**        | Single logical Zscaler-API grouping created together              | ZPA segment_group + server_group + application_segment for one app                              |
| **Infrastructure module**  | Collection of resource modules for one tenant / one product       | "All ZPA app segments for prod tenant", "All ZIA URL filtering rules for prod tenant"           |
| **Composition (root)**     | Per-environment top-level config that wires infrastructure modules | `environments/prod/zpa/`, `environments/prod/zia/`                                              |

❌ Do **not** mix `zia_*` and `zpa_*` resources in the same module — different lifecycles, different activation rules, different tenants likely.

✅ Modules are reusable; root configs are not. Reusable modules **never** declare `provider` blocks — the root composes them.

Detailed patterns: [Module Patterns](references/module-patterns.md).

## Reference Files

Progressive disclosure — essentials in this skill router, depth on demand.

Operational discipline:

- [State Management](references/state-management.md) — backends, per-tenant / per-microtenant state organization, never-`state rm` rationale, multi-team isolation, cross-state references.
- [CI/CD for Zscaler](references/ci-cd-zscaler.md) — GitHub Actions / GitLab CI / Atlantis templates with the activation step, OIDC against Zidentity, plan-artifact discipline, secret handling, per-microtenant CI parallelism.
- [Security & Compliance](references/security-and-compliance.md) — secrets out of state (`write_only` / `ephemeral` on 1.11+), Trivy/Checkov/tflint, custom OPA policies, audit-trail pattern, SOC2 / ISO 27001 / PCI / FedRAMP mappings.
- [Testing & Validation](references/testing-and-validation.md) — `terraform test` (1.6+), `mock_provider` (1.7+) limits, sandbox-tenant integration with cleanup, acceptance-criteria-by-risk-tier table.

Code shape:

- [Module Patterns](references/module-patterns.md) — required files, boundaries, composition, nested modules, examples directory, cross-state composition.
- [Coding Practices](references/coding-practices.md) — `count` vs `for_each` vs `dynamic`, locals, validation, dependency management, provider-block hygiene.
- [Naming Conventions](references/naming-conventions.md) — Terraform addresses, Zscaler portal names, variables, outputs, locals, files, modules, cross-provider consistency.
- [Variables and Outputs](references/variables-and-outputs.md) — typing, `optional()`, validation blocks, sensitive handling, output design, Zscaler-flavored variable templates.

Process discipline:

- [Versioning](references/versioning.md) — Terraform / provider pins, lockfile discipline, module SemVer, `moved {}`, OneAPI migration.
- [Anti-Patterns](references/anti-patterns.md) — quick-index table of every footgun + detail on the non-obvious ones.

Fast lookup:

- [Quick Reference](references/quick-reference.md) — DO/DON'T cheat sheet across all four Zscaler providers.

## Cross-References

Provider-specific guidance lives in the per-product skills. When the answer needs a resource attribute or auth field, route there:

- `zpa-skill` — Zscaler Private Access resource catalog, OneAPI / legacy / GOV / microtenant auth, policy rule semantics.
- `zia-skill` — Zscaler Internet Access resource catalog, rule ordering, activation lifecycle.
- `ztc-skill` — Zscaler Zero Trust Cloud resource catalog, cloud-orchestrated objects, activation lifecycle.
- `zcc-skill` — Zscaler Client Connector resource catalog, singleton / existing-only patterns.

## What This Skill Will Not Do

- Generate provider-specific HCL with attribute names — route to the relevant provider skill.
- Cover provider development (Plugin SDK schema, expand/flatten, acceptance tests) — out of scope.
- Recommend a state-file split for a repo whose blast-radius / approval boundaries you haven't described — ask first.
