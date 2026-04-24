---
name: zcc-skill
description: Use when writing, reviewing, or debugging Terraform HCL that uses the Zscaler Client Connector (ZCC) provider — covers provider auth (OneAPI / legacy ZCC v2 client), the small resource catalog (`zcc_trusted_network`, `zcc_forwarding_profile`, `zcc_failopen_policy` (singleton), `zcc_web_app_service` (existing-only)), the singleton + existing-only lifecycle pattern (no API delete on policy/web app service), the read-only data sources for users / devices / apps, and known quirks (`condition_type` accepting both `0` and `1`, GUID round-trips, plugin-framework semantics).
license: MIT
metadata:
  author: Zscaler
  version: 0.1.0
---

# Zscaler Client Connector (ZCC) Skill

Diagnose-first guidance for **end users writing Terraform HCL that consumes the `zscaler/zcc` provider**. ZCC manages Zscaler Client Connector configuration — trusted networks, forwarding profiles, fail-open policy, and bypass apps. This skill does not cover provider Go code.

**Canonical source of truth** for resource/data-source schemas: <https://registry.terraform.io/providers/zscaler/zcc/latest/docs>.

> **Provider status (as of 2026-04):** the `zscaler/zcc` provider is targeting first publication. Expect `~> 0.1.x` initially. Pin to the exact patch version in production until 1.0 ships.

## Response Contract

Every ZCC HCL response must include:

1. **Assumptions & version floor** — `zscaler/zcc` provider version (`~> 0.1.x`), Terraform/OpenTofu version, **auth mode (ASK if not stated — provider supports both OneAPI and legacy ZCC v2 as first-class options)**, cloud target (only set if non-default), and whether the resource being touched is **a singleton / existing-only** (which means delete is a no-op).
2. **Risk category addressed** — one or more of: auth misconfiguration, singleton/existing-only confusion, drift, schema-quirk handling (`condition_type`, GUID), secret exposure.
3. **Chosen approach & tradeoffs.**
4. **Validation plan** — `terraform fmt -check`, `terraform validate`, `terraform plan -out=tfplan`. **No activation step exists for ZCC** — changes apply directly to the API.
5. **Rollback notes** — for singleton resources (`zcc_failopen_policy`, `zcc_web_app_service`), `terraform destroy` only removes from state; the underlying API object persists. State the rollback procedure explicitly.

## Workflow

1. **Capture context** (see fields below).
2. **Diagnose intent** using the routing table.
3. **Load only the matching reference file(s).**
4. **Identify lifecycle type** for the targeted resource:
   - **Standard CRUD**: `zcc_trusted_network`, `zcc_forwarding_profile` — full create / update / delete.
   - **Singleton**: `zcc_failopen_policy` — pre-existing per-company, create = update settings, delete = state-only.
   - **Existing-only**: `zcc_web_app_service` — create = locate by `app_name` and apply changes; delete = state-only.
5. **Propose HCL** grounded in `references/resource-catalog.md` — never invent attribute names.
6. **Validate** and **emit the Response Contract**.

## Capture Context — Fields to Confirm

| Field             | Why it matters                                                                                              | Default if missing                |
| ----------------- | ----------------------------------------------------------------------------------------------------------- | --------------------------------- |
| Provider version  | Pre-1.0; schemas may change. Latest stable is `~> 0.1.x`.                                                    | Assume latest `0.1.x` and state it. |
| **Auth mode**     | **OneAPI and legacy ZCC v2 are both first-class.** Tenant must be migrated to Zidentity for OneAPI; otherwise legacy is the only option. | **Ask. Do not default.** State both options if unclear. |
| Cloud target      | OneAPI: `zscaler_cloud` is **optional** and only set for non-prod (e.g. `beta`). Legacy: `zcc_cloud` names the legacy cloud. | **Omit `zscaler_cloud` for production OneAPI.** Ask for legacy. |
| Resource lifecycle| Standard CRUD vs. singleton vs. existing-only. Affects how to write `terraform destroy` and import.          | Always check the catalog.         |
| Terraform runtime | Affects `optional()`, `moved`, `import`, `removed` availability.                                            | Assume `terraform ~> 1.9`.        |

## Diagnose Before You Generate

| Failure category                  | Symptoms                                                                                                            | Primary references                                                                                                    |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| **Auth misconfiguration**         | `401 unauthorized`, wrong env vars (mixing OneAPI's `ZSCALER_*` with legacy's `ZCC_*`)                              | [Auth & Providers](references/auth-and-providers.md)                                                                  |
| **Singleton confusion**           | Trying to `terraform destroy` `zcc_failopen_policy` and being surprised the API object survives                     | [Resource Catalog: Singleton & Existing-Only](references/resource-catalog.md#singleton--existing-only-resources)      |
| **Existing-only confusion**       | `zcc_web_app_service` create fails because `app_name` doesn't exist in the tenant                                   | [Resource Catalog: zcc_web_app_service](references/resource-catalog.md#zcc_web_app_service-existing-only)             |
| **Schema quirks**                 | `condition_type` drift, GUID-related update failures, `condition_type = 0 vs 1` confusion                           | [Troubleshooting: Schema Quirks](references/troubleshooting.md#schema-quirks)                                         |
| **Resource catalog mismatch**     | Invented attribute names; assuming ZCC has rule-ordering or activation (it does not)                                | [Resource Catalog](references/resource-catalog.md)                                                                    |
| **Drift on every plan**           | Bool flips, fields churn after import                                                                                | [Troubleshooting: Drift Causes](references/troubleshooting.md#drift-causes)                                           |
| **Secret exposure**               | Credentials in `.tfvars`, in state, in CI logs                                                                       | [Auth & Providers: Credential Hygiene](references/auth-and-providers.md#credential-hygiene)                           |

## Provider Block — Pick One

The provider supports **two** auth paths. Pick based on whether the tenant has been migrated to Zidentity. **Do not default** — confirm with the user.

> **Authoring rule (do not summarise):** when emitting an OneAPI provider block, reproduce the env-var comment list **verbatim** — including `ZSCALER_CLOUD` with its `optional` annotation. Users need to discover that `ZSCALER_CLOUD` exists as a supported (but optional) parameter; condensing it to `# ZSCALER_CLIENT_ID, ZSCALER_CLIENT_SECRET, ZSCALER_VANITY_DOMAIN` hides that fact.

### OneAPI (Zidentity tenants)

```hcl
terraform {
  required_version = "~> 1.9"
  required_providers {
    zcc = {
      source  = "zscaler/zcc"
      version = "~> 0.1.0"   # pin tight: pre-1.0
    }
  }
}

provider "zcc" {
  # In CI, set these env vars instead of hardcoding. The first three are required,
  # the fourth is optional and only used to target a non-production Zidentity environment.
  #   ZSCALER_CLIENT_ID       (required)
  #   ZSCALER_CLIENT_SECRET   (required; or ZSCALER_PRIVATE_KEY)
  #   ZSCALER_VANITY_DOMAIN   (required)
  #   ZSCALER_CLOUD           (optional — only set for non-prod, e.g. "beta")
}
```

### Legacy ZCC v2 (pre-Zidentity tenants)

```hcl
provider "zcc" {
  use_legacy_client = true
  # Env vars:
  #   ZCC_CLIENT_ID, ZCC_CLIENT_SECRET
  #   ZCC_CLOUD               ← legacy cloud name
  #   ZSCALER_USE_LEGACY_CLIENT=true
}
```

❌ Do not set `zscaler_cloud = "zscaler"` on OneAPI — `zscaler` is a **legacy** cloud name. On OneAPI, omit `zscaler_cloud` entirely for production tenants.

For private-key auth and credential hygiene, see [Auth & Providers](references/auth-and-providers.md).

## Resource Hierarchy — Small On Purpose

ZCC has a deliberately compact resource surface (4 resources). Most ZCC objects live in other systems (devices come from the agent, users from your IdP, apps from `zia_*`). The ZCC provider exists to manage **policy on top of those objects**.

| Resource                  | Lifecycle               | Purpose                                                            |
| ------------------------- | ----------------------- | ------------------------------------------------------------------ |
| `zcc_trusted_network`     | Standard CRUD           | Define a trusted network for evaluation by Client Connector.        |
| `zcc_forwarding_profile`  | Standard CRUD           | How Client Connector forwards traffic; references trusted networks. |
| `zcc_failopen_policy`     | **Singleton** (per company) | Settings on the company's pre-existing fail-open policy.        |
| `zcc_web_app_service`     | **Existing-only**       | Update an already-existing web app service (bypass app).            |

For everything else (users, devices, apps), ZCC exposes **data sources only** — there is no resource counterpart, so do not try to manage them with `resource` blocks.

| Data source                  | What it returns                                              | Why it's read-only                                          |
| ---------------------------- | ------------------------------------------------------------ | ----------------------------------------------------------- |
| `zcc_devices`                | Enrolled Client Connector devices                            | Devices enroll via the agent install, not via API.          |
| `zcc_admin_user`             | Admin user record(s)                                         | Admin users are managed in the ZCC console / Zidentity.     |
| `zcc_admin_roles`            | Admin role catalog                                           | Roles are platform-defined.                                 |
| `zcc_company_info`           | Tenant metadata                                              | Tenant config, not Terraform-managed.                       |
| `zcc_application_profiles`   | Application profiles defined for the tenant                  | Profiles created via the ZCC console.                       |
| `zcc_predefined_ip_apps`     | Catalog of predefined IP-based bypass apps                   | Catalog, not user-defined.                                  |
| `zcc_custom_ip_apps`         | Custom IP bypass apps                                        | Read-only listing — provisioned via the console.            |
| `zcc_process_based_apps`     | Process-based bypass apps                                    | Read-only listing — provisioned via the console.            |

See [Resource Catalog: Data Sources](references/resource-catalog.md#data-source-cheat-sheet) for the full schema of each.

## What ZCC Does **Not** Have

These are common LLM hallucinations because ZIA / ZTC / ZPA do have them. ZCC does **not**:

- ❌ No `order` field on any resource — there is no rule-ordering concept.
- ❌ No `state = "ENABLED"` style state field — `active` is a boolean, not a string enum.
- ❌ No `zcc_activation_status` or activation step — changes apply directly.
- ❌ No `zia_workload_groups`-style cross-product references.
- ❌ No predefined-rule mechanic.
- ❌ No `microtenant_id`.

If you see a generated HCL block claiming any of these, reject it.

## Naming Conventions

- Use descriptive names: `resource "zcc_trusted_network" "corp_office"`, not `... "this"`.
- Reserve `"this"` for genuine singletons (`zcc_failopen_policy`).
- Standard files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `providers.tf`.

## Critical Schema Quirks

- ❌ `zcc_trusted_network.condition_type` accepts **both `0` and `1`** depending on what the API GET returns. Set whatever the GET response shows; omit on update to leave the remote value unchanged.
- ❌ `zcc_trusted_network.guid` is a **read-only** field set by the API on create and sent automatically on PUT updates. Don't try to set it manually.
- ❌ `zcc_web_app_service.app_name` must match an **existing** tenant object — create does not create a new web app service, it locates and updates one.
- ❌ `zcc_failopen_policy` is a singleton per company. Multiple `resource "zcc_failopen_policy"` blocks in the same state will fight each other.

Full mechanics in [Resource Catalog](references/resource-catalog.md) and [Troubleshooting](references/troubleshooting.md).

## Credential Hygiene

- ❌ Never put `client_secret`, `private_key`, or legacy `zcc_client_secret` in checked-in `.tfvars`.
- ❌ Never echo credentials in CI job logs.
- ✅ Use env vars: `ZSCALER_CLIENT_ID`, `ZSCALER_CLIENT_SECRET`, `ZSCALER_VANITY_DOMAIN`, `ZSCALER_CLOUD` (OneAPI) **or** `ZCC_CLIENT_ID`, `ZCC_CLIENT_SECRET`, `ZCC_CLOUD`, `ZSCALER_USE_LEGACY_CLIENT=true` (legacy ZCC v2).
- ✅ Never mix OneAPI and legacy env vars in the same job — the provider will pick one based on `use_legacy_client` and the rest are ignored, which makes misconfigurations silent.
- ✅ Mark every HCL variable carrying a credential `sensitive = true`.

State considerations:

- The OneAPI client secret is **not** persisted to state.
- For singleton / existing-only resources, state contains a reference to the pre-existing API object — losing state means losing the binding, not the object.

## Reference Files

Progressive disclosure:

- [Auth & Providers](references/auth-and-providers.md) — OneAPI vs legacy ZCC v2, env vars (and the trap of mixing them), credential hygiene.
- [Resource Catalog](references/resource-catalog.md) — minimum-viable HCL per resource, singleton & existing-only patterns, data source cheat sheet.
- [Troubleshooting](references/troubleshooting.md) — drift causes, schema quirks (`condition_type`, GUID), import semantics, never-`state rm`, debug logging.
- [Recent Provider Changes](references/recent-provider-changes.md) — auto-mined from the upstream provider CHANGELOG.

**Cross-cutting engineering discipline** (state organization, CI/CD, secret handling, testing strategy, modules, naming, versioning) lives in the sibling **`best-practices-skill`** — load it whenever the question is about how to structure or operate a Zscaler-Terraform repo rather than how to call a specific `zcc_*` resource.

## Authoring Rule — Grounding for Uncatalogued Resources

ZCC ships a small surface (4 resources, 12 data sources), all enumerated in [Resource Catalog](references/resource-catalog.md). When asked about anything that isn't in the catalog:

1. **Fetch the official Registry page first** before generating any HCL:
   - Resource: `https://registry.terraform.io/providers/zscaler/zcc/latest/docs/resources/<name_without_zcc_prefix>`
   - Data source: `https://registry.terraform.io/providers/zscaler/zcc/latest/docs/data-sources/<name_without_zcc_prefix>`
2. Ground every attribute name in that fetched page.
3. State the Registry URL you used in the Response Contract `Assumptions` section.

❌ Never invent attribute names. ✅ If the Registry page does not exist for a `zcc_<name>`, the resource does not exist — say so explicitly. (Reminder: `zcc_*` does **not** support `order`, `state`, `zcc_activation_status`, or `microtenant_id`.)

## What This Skill Will Not Do

- Generate HCL with attribute names not documented on the official Terraform Registry page for that resource.
- Generate `order`, `state = "ENABLED"`, `zcc_activation_status`, or `microtenant_id` — none of these exist in ZCC.
- Recommend `terraform destroy` on `zcc_failopen_policy` or `zcc_web_app_service` without warning that the API object persists.
- Cover provider development (the ZCC provider is built on `terraform-plugin-framework`, not SDK v2 — different schema/diagnostic mechanics, out of scope).
