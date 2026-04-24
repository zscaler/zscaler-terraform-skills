# Zscaler Terraform Skills

Five Anthropic-format Agent Skills (`SKILL.md`) bundled as a Gemini CLI extension. Four are per-product (`zpa`, `zia`, `ztc`, `zcc`); one is cross-cutting engineering discipline (`best-practices`). Skills auto-activate based on description match with the user's request.

## Skill Routing

Pick the skill whose `description:` matches the request. Most prompts trigger exactly one product skill plus `best-practices` for cross-cutting concerns (state, CI/CD, testing, secrets).

| Trigger phrase in user request | Skill |
|--------------------------------|-------|
| "ZPA", "private access", `zpa_*` resources, application segments, segment groups, app connector groups, ZPA policy access rules, microtenants | `skills/zpa/SKILL.md` |
| "ZIA", "internet access", `zia_*` resources, URL filtering, firewall, DLP, SSL inspection, sandbox, cloud app control | `skills/zia/SKILL.md` |
| "ZTC", "Cloud Branch Connector", `ztc_*` resources, edge connector groups, traffic forwarding rules, ZIA forwarding gateways | `skills/ztc/SKILL.md` |
| "ZCC", "Client Connector", `zcc_*` resources, trusted networks, forwarding profiles, failopen policy, web app service | `skills/zcc/SKILL.md` |
| State organization, multi-tenant layout, CI/CD, `terraform test`, `mock_provider`, secrets handling, module composition, anti-patterns | `skills/best-practices/SKILL.md` |

## Hard Rules (apply to every skill)

- **Canonical source of truth is the Terraform Registry.** Resource and data-source schemas, attributes, and examples come from `https://registry.terraform.io/providers/zscaler/{zpa|zia|ztc|zcc}/latest/docs`. Do **not** invent attribute names. If you cannot find an attribute in the Registry, it does not exist.
- **Never embed secrets in HCL or `tfvars`.** Use `ZSCALER_*` (OneAPI) or product-specific env vars. Use `write_only` and `ephemeral` variables on Terraform 1.11+ for credential inputs.
- **Activation is mandatory for ZIA and ZTC** on any resource create / update / delete. Pure data-source workflows skip activation. ZPA and ZCC do **not** require activation.
- **Microtenant scoping (`microtenant_id`) is ZPA-only**, and only on resources whose schema actually accepts it. Do not add `microtenant_id` to ZIA / ZTC / ZCC resources.
- **OneAPI is the modern auth path** (`use_legacy = false`, the default). Legacy v3 / v2 auth exists for backward compatibility — only use it when the user explicitly asks.
- **Cloud values are provider-specific.** ZPA cloud strings (`PRODUCTION`, `BETA`, `GOV`, `GOVUS`, `PREVIEW`, `ZPATWO`) differ from ZIA's vanity-domain pattern. The product skill documents the exact values.

## Auth Quick-Reference

OneAPI (modern, recommended):

```hcl
provider "zpa" {
  client_id     = var.zscaler_client_id
  client_secret = var.zscaler_client_secret
  customer_id   = var.zscaler_customer_id
  vanity_domain = var.zscaler_vanity_domain
}
```

Env vars (preferred over inline): `ZSCALER_CLIENT_ID`, `ZSCALER_CLIENT_SECRET`, `ZSCALER_CUSTOMER_ID`, `ZSCALER_VANITY_DOMAIN`.

Legacy per-product env vars exist (`ZPA_*`, `ZIA_*`, `ZCC_*`, `ZTC_*`) — see the per-product SKILL.md and the `best-practices` skill's secret-handling reference.

## Response Contract

Every HCL the skills produce includes:

1. **Assumptions made** (provider version floor, auth mode, cloud, microtenant if any).
2. **Risk** of the change (drift, ordering impact, activation requirement).
3. **Validation** to run before apply (`terraform plan`, `terraform test`, `terraform fmt -check`, `terraform validate`).
4. **Rollback** path (`terraform state rm`, `moved {}` block, manual undo, etc.).

## Capture Before Generating

If any of these are unknown, ask the user before producing HCL:

- Provider version floor (the resource's required `version` may be newer than the user's `required_providers`)
- Auth mode (OneAPI vs legacy vs GOV)
- Microtenant ID (ZPA only)
- Customer ID and cloud
- Whether the change requires activation (ZIA / ZTC always; ZPA / ZCC never)
- Whether write-only / ephemeral variables are available (Terraform 1.11+)

## Reference Files

Each skill ships its own `references/` directory with deep-dive content (auth patterns, resource catalogs, troubleshooting, recent provider changes). The skill's `SKILL.md` indexes them — load on demand, not eagerly.

Cross-cutting references in `skills/best-practices/references/`:

- `state-management.md` — backends, per-microtenant layout, blast-radius isolation
- `ci-cd-zscaler.md` — activation step in pipelines, OIDC against Zidentity
- `testing-and-validation.md` — `terraform test` three-layer pyramid, `mock_provider`
- `security-and-compliance.md` — secret handling, OneAPI rotation, scanners
- `module-patterns.md`, `coding-practices.md`, `naming-conventions.md`,
  `variables-and-outputs.md`, `versioning.md`, `anti-patterns.md` — code shape

## Discovery Tiers (Gemini CLI)

This repo can be consumed three ways:

1. **Extension install** (recommended): `gemini extensions install https://github.com/zscaler/zscaler-terraform-skills` — pulls everything, auto-discovers `skills/*/SKILL.md`.
2. **User-scoped clone**: `git clone https://github.com/zscaler/zscaler-terraform-skills ~/.gemini/skills/zscaler-terraform-skills`
3. **Workspace-scoped**: drop the `skills/*/` folders under `.gemini/skills/` or `.agents/skills/` in a project.
