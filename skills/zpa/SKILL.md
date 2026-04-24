---
name: zpa-skill
description: Use when writing, reviewing, or debugging Terraform HCL that uses the Zscaler Private Access (ZPA) provider — covers provider auth (OneAPI / legacy / multi-cloud), the resource catalog (application segments, server groups, segment groups, app connector groups, policy access rules), policy-rule operand semantics, and known API quirks (drift on omitempty bools, microtenant scoping, detach-before-delete).
license: MIT
metadata:
  author: Zscaler
  version: 1.0.0
---

# Zscaler Private Access (ZPA) Skill

Diagnose-first guidance for **end users writing Terraform HCL that consumes the `zscaler/zpa` provider**. This skill does not cover provider Go code (Plugin SDK schema, expand/flatten, acceptance tests).

**Canonical source of truth** for resource/data-source schemas: <https://registry.terraform.io/providers/zscaler/zpa/latest/docs>.

## Response Contract

Every ZPA HCL response must include:

1. **Assumptions & version floor** — `zscaler/zpa` provider version (`~> 4.0` minimum for OneAPI), Terraform/OpenTofu version, **auth mode (ASK if not stated — provider supports both OneAPI and legacy v3 as first-class options)**, ZPA customer ID, cloud target (only set if non-default), microtenant scope (yes/no + which `microtenant_id`). State assumptions explicitly if the user did not provide them.
2. **Risk category addressed** — one or more of: auth misconfiguration, resource catalog mismatch, policy operand misuse, dependency / detach order, microtenant scoping, drift, secret exposure.
3. **Chosen approach & tradeoffs** — what was chosen, what was traded off (e.g. data-source lookup vs hardcoded ID), why.
4. **Validation plan** — exact commands: `terraform fmt -check`, `terraform validate`, `terraform plan -out=tfplan`, optional `terraform show -json tfplan | jq` to inspect operand JSON before apply.
5. **Rollback notes** — for any policy-rule or segment-group change: how to undo (re-apply previous HCL, `terraform state rm` not safe for ZPA — see [Troubleshooting](references/troubleshooting.md#never-state-rm-a-zpa-resource)), what evidence to keep (debug log capture).

Never recommend `terraform apply` against a production ZPA tenant without a reviewed plan artifact and a microtenant scope check.

## Workflow

1. **Capture context** (see fields below).
2. **Diagnose intent** using the routing table.
3. **Load only the matching reference file(s).** Do not preload depth the task does not need.
4. **Propose HCL** grounded in the canonical examples from `references/resource-catalog.md` — never invent attribute names.
5. **Validate** with the commands tailored to risk tier.
6. **Emit the Response Contract.**

## Capture Context — Fields to Confirm

| Field             | Why it matters                                                                                                | Default if missing                |
| ----------------- | ------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| Provider version  | Resource catalog and auth options differ between v3 (legacy) and v4+ (OneAPI). Always pin `~> 4.0` minimum.    | Assume `~> 4.0` and state it.     |
| **Auth mode**     | **OneAPI and legacy v3 are both first-class.** Tenant must be migrated to Zidentity for OneAPI; otherwise legacy is the only option. `GOV` / `GOVUS` clouds are legacy-only. | **Ask. Do not default.** State both options if unclear. |
| Cloud target      | OneAPI: `zscaler_cloud` is **optional** and only set for non-prod (e.g. `beta`). Legacy: `zpa_cloud` is required only when **not** `PRODUCTION` (`BETA`, `ZPATWO`, `GOV`, `GOVUS`, `PREVIEW`). | **Omit `zscaler_cloud` for production OneAPI. Omit `zpa_cloud` for legacy PRODUCTION.** |
| Customer ID       | Required for both auth modes — tenant-scoped (`ZPA_CUSTOMER_ID`).                                              | Ask if absent.                    |
| Microtenant       | Many resources are microtenant-scoped. Mixing scopes silently breaks Read.                                     | Assume parent tenant; flag risk.  |
| Terraform runtime | Affects `optional()`, `moved`, `import`, `write_only` availability.                                            | Assume `terraform ~> 1.9`.        |

## Diagnose Before You Generate

| Failure category            | Symptoms                                                                                                            | Primary references                                                                                                                          |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| **Auth misconfiguration**   | `401 unauthorized`, `vanity_domain not found`, GOV cloud rejecting OneAPI                                            | [Auth & Providers](references/auth-and-providers.md)                                                                                        |
| **Resource catalog mismatch** | "Does ZPA have a resource for X?", invented attribute names, wrong block structure                                  | [Resource Catalog](references/resource-catalog.md)                                                                                          |
| **Policy operand misuse**   | `400 INVALID_INPUT` on policy rule, `Invalid operand type`, `LHS value is required`                                  | [Policy Rules: Operand Reference](references/policy-rules.md#operand-reference)                                                             |
| **Policy ordering / type**  | Wrong `policy_set_id`, rule applied in wrong policy, action enum rejected                                            | [Policy Rules: Policy Type Map](references/policy-rules.md#policy-type-map)                                                                 |
| **Dependency / detach order** | `RESOURCE_IN_USE` on `terraform destroy` of segment / server / app-connector group                                   | [Troubleshooting: Detach-Before-Delete](references/troubleshooting.md#detach-before-delete)                                                 |
| **Microtenant scoping**     | Resource exists in console but Read returns 404 → Terraform recreates                                                 | [Troubleshooting: Microtenant 404](references/troubleshooting.md#microtenant-not-found)                                                     |
| **Drift on every plan**     | Bool attribute keeps flipping, set order changes, write-only field clears                                             | [Troubleshooting: Drift Causes](references/troubleshooting.md#drift-causes)                                                                 |
| **Secret exposure**         | Client secrets / private keys in `.tfvars`, in state, in CI logs                                                     | [Auth & Providers: Credential Hygiene](references/auth-and-providers.md#credential-hygiene)                                                 |

## Provider Block — Pick One

The provider supports **two** auth paths. Pick based on whether the tenant has been migrated to Zidentity. **Do not default** — confirm with the user.

> **Authoring rule (do not summarise):** when emitting an OneAPI provider block, reproduce the env-var comment list **verbatim** — including `ZSCALER_CLOUD` with its `optional` annotation. Users need to discover that `ZSCALER_CLOUD` exists as a supported (but optional) parameter for OneAPI; condensing it to `# ZSCALER_CLIENT_ID, ZSCALER_CLIENT_SECRET, ZSCALER_VANITY_DOMAIN, ZPA_CUSTOMER_ID` hides that fact.

### OneAPI (Zidentity tenants)

```hcl
terraform {
  required_version = "~> 1.9"
  required_providers {
    zpa = {
      source  = "zscaler/zpa"
      version = "~> 4.0"
    }
  }
}

provider "zpa" {
  # In CI, set these env vars instead of hardcoding. The first four are required,
  # the fifth is optional and only used to target a non-production Zidentity environment.
  #   ZSCALER_CLIENT_ID       (required)
  #   ZSCALER_CLIENT_SECRET   (required; or ZSCALER_PRIVATE_KEY)
  #   ZSCALER_VANITY_DOMAIN   (required)
  #   ZPA_CUSTOMER_ID         (required)
  #   ZSCALER_CLOUD           (optional — only set for non-prod, e.g. "beta")
}
```

### Legacy v3 (pre-Zidentity tenants, GOV, GOVUS)

```hcl
provider "zpa" {
  use_legacy_client = true
  # Env vars:
  #   ZPA_CLIENT_ID, ZPA_CLIENT_SECRET, ZPA_CUSTOMER_ID
  #   ZPA_CLOUD               ← REQUIRED only when not PRODUCTION: BETA | ZPATWO | GOV | GOVUS | PREVIEW
  #   ZSCALER_USE_LEGACY_CLIENT=true
}
```

❌ Do not set `zscaler_cloud = "PRODUCTION"` on OneAPI — `PRODUCTION` is a **legacy** `zpa_cloud` value. On OneAPI, omit `zscaler_cloud` entirely for production tenants.

For private-key auth and microtenant scoping, see [Auth & Providers](references/auth-and-providers.md).

## Resource Hierarchy

| Layer            | Purpose                                                              | Example resources                                                                              |
| ---------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| **Connectivity** | Where ZPA reaches into the network                                   | `zpa_app_connector_group`, `zpa_app_connector_controller`                                      |
| **Application**  | What is being protected                                              | `zpa_application_server`, `zpa_application_segment`, `zpa_application_segment_browser_access`  |
| **Grouping**     | How applications and servers are grouped for policy targeting        | `zpa_segment_group`, `zpa_server_group`                                                        |
| **Identity**     | Where users come from                                                | `zpa_idp_controller`, `zpa_scim_groups`, `zpa_scim_attribute_header`, `zpa_saml_attribute`     |
| **Posture**      | Device-trust signals                                                 | `zpa_posture_profile`, `zpa_trusted_network`                                                   |
| **Policy**       | Allow / deny / forward / inspect / isolate                           | `zpa_policy_access_rule`, `zpa_policy_access_forwarding_rule`, `zpa_policy_access_isolation_rule`, `zpa_policy_access_inspection_rule` |
| **Tenancy**      | Microtenant scoping (optional)                                       | `zpa_microtenant_controller`                                                                   |

Standard composition flow: **Application Server → Server Group ← Segment Group ← Application Segment → referenced by Policy Rule.** See [Resource Catalog: Composition Recipes](references/resource-catalog.md#composition-recipes).

## Naming Conventions

- Use descriptive names: `resource "zpa_application_segment" "crm_app"`, not `... "this"`.
- Reserve `"this"` for genuine singletons (e.g. a single `zpa_microtenant_controller`).
- Prefix variables with context: `zpa_segment_group_id`, not `id`.
- Standard files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `providers.tf`.

## Block Ordering

Resource blocks: `count`/`for_each` first → required arguments → optional arguments → nested blocks → `lifecycle`.
Variable blocks: `description` → `type` → `default` → `validation` → `nullable` → `sensitive`.

## Policy Rules — Quick Rules

- **Always** look up `policy_set_id` via `data "zpa_policy_type"` — never hardcode.
- **Always** prefer data sources (`data.zpa_application_segment.x.id`) over literal IDs.
- `conditions` is an **ordered list of OR-groups** combined by the rule-level `operator`. Inside each `conditions` block, multiple `operands` are combined by that block's `operator`.
- `operands.object_type` is a closed enum (`APP`, `APP_GROUP`, `SCIM`, `SCIM_GROUP`, `SAML`, `IDP`, `POSTURE`, `TRUSTED_NETWORK`, `CLIENT_TYPE`, `PLATFORM`, `COUNTRY_CODE`, `MACHINE_GRP`, …).
- `lhs` / `rhs` semantics depend on `object_type`. For `SCIM_GROUP`, `lhs = idp_id`, `rhs = scim_group_id`. For `APP`, `lhs = "id"`, `rhs = application_segment_id`. Get this wrong → `400 INVALID_INPUT`.

Full mapping in [Policy Rules: Operand Reference](references/policy-rules.md#operand-reference).

## Microtenants — When to Worry

If the customer's tenant uses microtenants, **every** resource and **every** data source call must pass the same `microtenant_id`. Mixing scopes silently breaks Read (returns 404 → Terraform recreates the resource). See [Troubleshooting: Microtenant 404](references/troubleshooting.md#microtenant-not-found).

```hcl
resource "zpa_application_segment" "crm" {
  name           = "CRM"
  microtenant_id = var.zpa_microtenant_id  # propagate consistently
  # ...
}
```

If the user does not mention microtenants, assume parent tenant and **state that assumption** in the Response Contract.

## Data-Source-Only Objects

ZPA exposes 70 resources and 70 data sources, but ~30 of those data sources have **no matching resource** because the underlying object is provisioned by another system (IdP, posture vendor, ZPA console, cloud orchestration). Common data-source-only objects:

| Category                | Data sources only (representative — not exhaustive)                                                                                       |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Identity (IdP-driven)   | `zpa_idp_controller`, `zpa_saml_attribute`, `zpa_scim_attribute_header` (you can use `zpa_scim_groups` for SCIM groups but the IdP is read-only) |
| Posture (vendor-driven) | `zpa_posture_profile`, `zpa_machine_group`, `zpa_trusted_network` (often read-only when populated by an MDM)                              |
| Cloud orchestration     | `zpa_app_connector_controller`, `zpa_private_cloud_controller`, `zpa_branch_connector_group`, `zpa_cloud_connector_group`, `zpa_extranet_resource_partner` |
| Tenant / catalog        | `zpa_enrollment_cert`, `zpa_customer_version_profile`, `zpa_policy_type`, `zpa_risk_score_values`                                         |
| Helper / lookup         | `zpa_application_segment_by_type`, `zpa_access_policy_client_types`, `zpa_access_policy_platforms`, `zpa_lss_config_client_types`, `zpa_lss_config_log_type_formats`, `zpa_lss_config_status_codes` |
| Browser / isolation     | `zpa_browser_protection`, `zpa_managed_browser_profile`, `zpa_isolation_profile`, `zpa_cloud_browser_isolation_region`, `zpa_cloud_browser_isolation_zpa_profile` |
| Inspection catalog      | `zpa_inspection_predefined_controls`, `zpa_inspection_all_predefined_controls`                                                            |
| Location reference      | `zpa_location_controller`, `zpa_location_controller_summary`, `zpa_location_group_controller`                                             |

Always check the official Terraform Registry before assuming there's a matching resource:

- Resources index: <https://registry.terraform.io/providers/zscaler/zpa/latest/docs>
- Specific resource: `https://registry.terraform.io/providers/zscaler/zpa/latest/docs/resources/<name_without_zpa_prefix>`
- Specific data source: `https://registry.terraform.io/providers/zscaler/zpa/latest/docs/data-sources/<name_without_zpa_prefix>`

If only the data-source page exists for an object, it's read-only.

❌ Do not propose `resource "zpa_idp_controller"` — IdPs are configured in the ZPA admin console, not by Terraform. ✅ Use `data "zpa_idp_controller" { name = "Okta" }` to look one up for use in policy operands.

## Credential Hygiene

- ❌ Never put `client_secret`, `private_key`, or `customer_id` in `.tfvars` checked into git.
- ❌ Never echo credentials in CI job logs.
- ❌ **Do not mix `ZSCALER_*` and `ZPA_*` env vars in the same job** — the provider picks one path based on `use_legacy_client` and silently ignores the other namespace. (`ZPA_CUSTOMER_ID` is the exception — it is required for both modes.)
- ✅ Use env vars matching your auth path:
  - **OneAPI:** `ZSCALER_CLIENT_ID`, `ZSCALER_CLIENT_SECRET` (or `ZSCALER_PRIVATE_KEY`), `ZSCALER_VANITY_DOMAIN`, `ZPA_CUSTOMER_ID`, optionally `ZSCALER_CLOUD` for non-prod.
  - **Legacy:** `ZPA_CLIENT_ID`, `ZPA_CLIENT_SECRET`, `ZPA_CUSTOMER_ID`, `ZSCALER_USE_LEGACY_CLIENT=true`, plus `ZPA_CLOUD` for non-PRODUCTION clouds.
- ✅ Source from your secret store (Vault, AWS Secrets Manager, GH Actions secrets) and inject as env at job start.
- ✅ Mark any HCL variable that holds these `sensitive = true` even though it's display-only — it prevents accidental `terraform output` / log leakage.

State files contain identifiers (segment IDs, server IDs) but **not** the OneAPI client secret, since auth is config-only and not persisted. Still, treat state as sensitive — restrict S3/GCS bucket access.

## Reference Files

Progressive disclosure — essentials here, depth on demand:

- [Auth & Providers](references/auth-and-providers.md) — provider config, OneAPI vs legacy, env vars, GOV cloud, microtenant config, credential hygiene.
- [Resource Catalog](references/resource-catalog.md) — minimum-viable HCL per resource, composition recipes, data-source lookups.
- [Policy Rules](references/policy-rules.md) — policy type map, operand reference, condition composition, ordering, common 400 errors.
- [Troubleshooting](references/troubleshooting.md) — drift causes, detach-before-delete, microtenant 404, debug logging.
- [Recent Provider Changes](references/recent-provider-changes.md) — auto-mined from the upstream provider CHANGELOG; lists user-facing additions and breaking changes from the last several releases.

**Cross-cutting engineering discipline** (state organization, microtenant blast radius, CI/CD, secret handling, testing strategy, modules, naming, versioning) lives in the sibling **`best-practices-skill`** — load it whenever the question is about how to structure or operate a Zscaler-Terraform repo rather than how to call a specific `zpa_*` resource.

## Authoring Rule — Grounding for Uncatalogued Resources

The reference catalog ships canonical HCL for the most-used `zpa_*` resources, but ZPA exposes 70 resources and 70 data sources. When asked about an object not in [Resource Catalog](references/resource-catalog.md):

1. **Fetch the official Registry page first** before generating any HCL:
   - Resource: `https://registry.terraform.io/providers/zscaler/zpa/latest/docs/resources/<name_without_zpa_prefix>`
   - Data source: `https://registry.terraform.io/providers/zscaler/zpa/latest/docs/data-sources/<name_without_zpa_prefix>`
2. Ground every attribute name in that fetched page.
3. State the Registry URL you used in the Response Contract `Assumptions` section.

❌ Never invent attribute names. ✅ If the Registry page does not exist for a `zpa_<name>`, the resource does not exist — say so explicitly.

## What This Skill Will Not Do

- Generate HCL with attribute names not documented on the official Terraform Registry page for that resource.
- Recommend `terraform state rm` for ZPA resources (orphans the API object, see [Troubleshooting](references/troubleshooting.md#never-state-rm-a-zpa-resource)).
- Cover provider development (Plugin SDK schema, expand/flatten, acceptance tests) — out of scope.
