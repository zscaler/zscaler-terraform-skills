---
name: zia-skill
description: Use when writing, reviewing, or debugging Terraform HCL that uses the Zscaler Internet Access (ZIA) provider — covers provider auth (OneAPI / legacy / multi-cloud), the resource catalog (URL filtering, firewall, DLP, SSL inspection, cloud app control, sandbox), rule ordering semantics (predefined vs custom rules, contiguous order requirement, IntAtLeast(1)), the activation lifecycle, and known API quirks (DUPLICATE_ITEM, predefined-rule reorder, country-code validation).
license: MIT
metadata:
  author: Zscaler
  version: 0.2.0
---

# Zscaler Internet Access (ZIA) Skill

Diagnose-first guidance for **end users writing Terraform HCL that consumes the `zscaler/zia` provider**. This skill does not cover provider Go code (Plugin SDK schema, expand/flatten, acceptance tests).

**Canonical source of truth** for resource/data-source schemas: <https://registry.terraform.io/providers/zscaler/zia/latest/docs>.

## Response Contract

Every ZIA HCL response must include:

1. **Assumptions & version floor** — `zscaler/zia` provider version (`~> 4.0` minimum for OneAPI), Terraform/OpenTofu version, **auth mode (ASK if not stated — provider supports both OneAPI and legacy v3 as first-class options)**, cloud target (only set if non-default), and **whether the configuration creates or modifies any resource** (which makes activation mandatory).
2. **Risk category addressed** — one or more of: auth misconfiguration, resource catalog mismatch (including data-source-only objects), rule ordering, predefined-rule mishandling, activation forgotten, drift, secret exposure.
3. **Chosen approach & tradeoffs.**
4. **Validation plan** — `terraform fmt -check`, `terraform validate`, `terraform plan -out=tfplan`, **plus a `zia_activation_status` step if any resource is created/modified** (changes are draft until activated).
5. **Rollback notes** — never `terraform state rm` a ZIA resource; for predefined rules use `terraform apply -target=` (see [Troubleshooting](references/troubleshooting.md#never-state-rm-a-zia-resource)).

Never recommend `terraform apply` against a production ZIA tenant without a reviewed plan artifact and a clear activation step.

## Workflow

1. **Capture context** (see fields below).
2. **Diagnose intent** using the routing table.
3. **Load only the matching reference file(s).**
4. **Propose HCL** grounded in `references/resource-catalog.md` — never invent attribute names.
5. **Check rule ordering** (if any rule resource is touched).
6. **Decide activation** — explicit `zia_activation_status` resource, or document a manual activation step.
7. **Validate** with the commands tailored to risk tier.
8. **Emit the Response Contract.**

## Capture Context — Fields to Confirm

| Field             | Why it matters                                                                                              | Default if missing                |
| ----------------- | ----------------------------------------------------------------------------------------------------------- | --------------------------------- |
| Provider version  | Resource catalog and rule-order validation differ between v3 (legacy) and v4+ (OneAPI). `~> 4.0` minimum.   | Assume `~> 4.0` and state it.     |
| **Auth mode**     | **OneAPI and legacy v3 are both first-class.** Tenant must be migrated to Zidentity for OneAPI; otherwise legacy is the only option. `zscalergov` / `zscalerten` are legacy-only. | **Ask. Do not default.** State both options if unclear. |
| Cloud target      | OneAPI: `zscaler_cloud` is **optional** and only set for non-prod (e.g. `beta`). Legacy: `zia_cloud` is required and names the cloud (`zscaler`, `zscloud`, `zscalergov`, …). | **Omit `zscaler_cloud` for production OneAPI.** Ask for legacy. |
| Activation        | **ANY** create/update/delete on a ZIA resource needs `zia_activation_status`. Pure data-source workflows do not. | If any resource is touched: include activation. Always. |
| Rule ordering     | Order is enforced server-side and must be `>= 1` and contiguous.                                             | Ask if rule order matters.        |
| Terraform runtime | Affects `optional()`, `moved`, `import`, `removed` availability.                                            | Assume `terraform ~> 1.9`.        |

## Diagnose Before You Generate

| Failure category               | Symptoms                                                                                                            | Primary references                                                                                                    |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| **Auth misconfiguration**      | `401 unauthorized`, `vanity_domain not found`, GOV cloud rejecting OneAPI                                           | [Auth & Providers](references/auth-and-providers.md)                                                                  |
| **Resource catalog mismatch**  | "Does ZIA have a resource for X?", invented attribute names, wrong block structure, plural vs singular resource name | [Resource Catalog](references/resource-catalog.md)                                                                    |
| **Rule ordering / predefined** | `order = 0` rejected, predefined-rule destroy fails, rules drift after a delete, `Request body is invalid` on PUT    | [Rules & Ordering](references/rules-and-ordering.md)                                                                  |
| **Activation forgotten**       | `terraform apply` succeeds but policy doesn't change in the ZIA console                                              | [Activation](references/activation.md)                                                                                |
| **Drift on every plan**        | Bool keeps flipping, `idleTimeInMinutes` reverts to 0, predefined fields churn                                       | [Troubleshooting: Drift Causes](references/troubleshooting.md#drift-causes)                                           |
| **DUPLICATE_ITEM**             | `400 DUPLICATE_ITEM` on create — name collision with predefined or pre-existing object                              | [Troubleshooting: DUPLICATE_ITEM](references/troubleshooting.md#duplicate_item-on-create)                             |
| **Country / locale validation**| `'AUC' is not a valid ISO-3166 Alpha-2 country code`, `country` rejected on `zia_location_management`                | [Troubleshooting: Country Code Validation](references/troubleshooting.md#country-code--locale-validation)             |
| **Secret exposure**            | Credentials in `.tfvars`, in state, in CI logs                                                                       | [Auth & Providers: Credential Hygiene](references/auth-and-providers.md#credential-hygiene)                           |

## Provider Block — Pick One

The provider supports **two** auth paths. Pick based on whether the tenant has been migrated to Zidentity. **Do not default** — confirm with the user.

> **Authoring rule (do not summarise):** when emitting an OneAPI provider block, reproduce the env-var comment list **verbatim** — including `ZSCALER_CLOUD` with its `OPTIONAL` annotation. Users need to discover that `ZSCALER_CLOUD` exists as a supported (but optional) parameter; condensing it to `# ZSCALER_CLIENT_ID, ZSCALER_CLIENT_SECRET, ZSCALER_VANITY_DOMAIN` hides that fact.

### OneAPI (Zidentity tenants)

```hcl
terraform {
  required_version = "~> 1.9"
  required_providers {
    zia = {
      source  = "zscaler/zia"
      version = "~> 4.0"
    }
  }
}

provider "zia" {
  # In CI, set these env vars instead of hardcoding. The first three are required,
  # the fourth is optional and only used to target a non-production Zidentity environment.
  #   ZSCALER_CLIENT_ID       (required)
  #   ZSCALER_CLIENT_SECRET   (required; or ZSCALER_PRIVATE_KEY)
  #   ZSCALER_VANITY_DOMAIN   (required)
  #   ZSCALER_CLOUD           (optional — only set for non-prod, e.g. "beta")
}
```

### Legacy v3 (pre-Zidentity tenants, GOV, `zscalerten`)

```hcl
provider "zia" {
  use_legacy_client = true
  # Env vars:
  #   ZIA_USERNAME, ZIA_PASSWORD, ZIA_API_KEY
  #   ZIA_CLOUD               ← REQUIRED on legacy: zscaler | zscloud | zscalerbeta | zscalerone | zscalertwo | zscalerthree | zscalergov | zscalerten | zspreview
  #   ZSCALER_USE_LEGACY_CLIENT=true
}
```

❌ Do not set `zscaler_cloud = "zscaler"` on OneAPI — `zscaler` is a **legacy** cloud name. On OneAPI, omit `zscaler_cloud` entirely for production tenants.

For private-key auth, full env-var matrix, and credential hygiene, see [Auth & Providers](references/auth-and-providers.md).

## Resource Hierarchy

| Layer                | Purpose                                          | Example resources                                                                                                |
| -------------------- | ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| **Locations / forwarding** | Where traffic enters ZIA                   | `zia_location_management`, `zia_traffic_forwarding_gre_tunnel`, `zia_traffic_forwarding_vpn_credentials`         |
| **Identity sources**       | Users, groups, departments                  | `zia_user_management`, `zia_group_management`, `zia_department_management`, `zia_admin_user`                     |
| **URL filtering**          | What categories users can access            | `zia_url_filtering_rules`, `zia_url_categories`                                                                  |
| **Firewall**               | Network-layer policy                        | `zia_firewall_filtering_rule`, `zia_firewall_dns_rules`, `zia_firewall_ips_rules`, `zia_nat_control_rules`        |
| **SSL / inspection**       | TLS inspection rules                        | `zia_ssl_inspection_rules`                                                                                       |
| **DLP**                    | Data Loss Prevention                        | `zia_dlp_dictionary`, `zia_dlp_engines`, `zia_dlp_web_rules`, `zia_dlp_notification_templates`                   |
| **Cloud app control**      | Policy on SaaS apps (M365, GDrive, …)       | `zia_cloud_app_control_rule` (uses `zia_cloud_app_control_rule_actions` data source)                             |
| **Sandbox**                | Malware sandbox policy                      | `zia_sandbox_rules`, `zia_sandbox_behavioral_analysis`                                                           |
| **Forwarding control**     | ZIA → ZPA gateway, proxy, etc.              | `zia_forwarding_control_policy`, `zia_forwarding_control_proxies`, `zia_forwarding_control_zpa_gateway`           |
| **Activation**             | **Required** to push draft changes live     | `zia_activation_status`                                                                                          |

## Naming Conventions

- Use descriptive names: `resource "zia_url_filtering_rules" "block_gambling_for_sales"`, not `... "this"`.
- Reserve `"this"` for genuine singletons (e.g. `zia_activation_status`).
- Prefix variables with context: `zia_dlp_engine_id`, not `id`.
- Standard files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `providers.tf`.
- ZIA rule resources end in `s` (`_rules`, `_rule`) — be careful: `zia_url_filtering_rules` (plural) but `zia_firewall_filtering_rule` (singular). Always cross-check against [Resource Catalog](references/resource-catalog.md).

## Rule Resources — Critical Rules

These apply to **every** rule-style resource: `zia_url_filtering_rules`, `zia_firewall_filtering_rule`, `zia_firewall_dns_rules`, `zia_firewall_ips_rules`, `zia_dlp_web_rules`, `zia_ssl_inspection_rules`, `zia_cloud_app_control_rule`, `zia_forwarding_control_rule`, `zia_nat_control_rules`, `zia_sandbox_rules`, `zia_bandwidth_control_rules`, `zia_traffic_capture_rules`, `zia_file_type_control_rules`, `zia_casb_dlp_rules`, `zia_casb_malware_rules`.

- ❌ `order = 0` or negative — rejected at plan time (`validation.IntAtLeast(1)`); previously could create an undeletable rule.
- ❌ Non-contiguous orders (`1, 2, 5`) after a delete — causes drift on next plan.
- ❌ `terraform destroy` against a predefined rule — not supported.
- ✅ Use `terraform apply -target=<resource>` to delete specific custom rules, then re-adjust the surviving order numbers in HCL to stay contiguous.
- ✅ Predefined rules **can** be reordered via Terraform; changes go through cleanly as of provider v4.7.9.

Full mechanics in [Rules & Ordering](references/rules-and-ordering.md).

## Activation — Hard Rule

**Every** create/update/delete on a ZIA resource produces a draft change that **must** be activated to take effect. This includes "metadata-only" objects like `zia_rule_labels`, `zia_url_categories`, `zia_dlp_dictionary`, locations, departments, and admin users — there is no resource type in ZIA that bypasses activation. Only **pure data-source workflows** (read-only) skip it.

| Pattern                              | When                                                                                          |
| ------------------------------------ | --------------------------------------------------------------------------------------------- |
| Manage `zia_activation_status` in TF | Atomic per-apply activation — recommended for CI/CD.                                          |
| Manual activation in console         | Acceptable for ad-hoc / emergency changes; document the step in the PR.                       |
| **Skip activation entirely**         | **Only** when the configuration uses `data "zia_…"` exclusively — no `resource "zia_…"`.       |

Reference pattern (atomic activation):

```hcl
resource "zia_url_filtering_rules" "block_gambling" {
  name   = "Block Gambling"
  state  = "ENABLED"
  action = "BLOCK"
  order  = 1
  url_categories = ["GAMBLING"]
  protocols      = ["ANY_RULE"]
  request_methods = ["CONNECT", "DELETE", "GET", "HEAD", "OPTIONS", "OTHER", "POST", "PUT", "TRACE"]
}

resource "zia_activation_status" "this" {
  status     = "ACTIVE"
  depends_on = [zia_url_filtering_rules.block_gambling]
}
```

See [Activation](references/activation.md) for the full pattern, multi-resource batching, and CI/CD wiring.

## Data-Source-Only Objects

ZIA exposes **101 data sources but only 71 resources**. Many objects are read-only from Terraform's perspective — they're populated by the ZIA console, the agent, your IdP, or other Zscaler products — and trying to declare them as `resource` blocks will fail (no such resource type exists). Common data-source-only objects:

| Category                | Data sources only (representative — not exhaustive)                                                                                       |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Identity (read-only)    | `zia_department_management`, `zia_group_management`, `zia_devices`, `zia_device_groups` (all populated by the IdP / agent enrollment)     |
| Location helpers        | `zia_location_lite`, `zia_location_groups`                                                                                                |
| Predefined catalog      | `zia_dlp_dictionary_predefined_identifiers`, `zia_firewall_filtering_application_services`, `zia_firewall_filtering_network_application`, `zia_file_type_categories`, `zia_firewall_filtering_time_window` |
| Tenant / cloud info     | `zia_datacenters`, `zia_dedicated_ip_proxy`, `zia_cloud_applications`                                                                     |
| DLP infrastructure      | `zia_dlp_idm_profiles`, `zia_dlp_idm_profile_lite`, `zia_dlp_edm_schema`, `zia_dlp_icap_servers`, `zia_dlp_incident_receiver_servers`, `zia_dlp_cloud_to_cloud_ir` |
| CASB metadata           | `zia_casb_email_label`, `zia_casb_tenant`, `zia_casb_tombstone_template`                                                                  |
| Sandbox / runtime       | `zia_sandbox_report` (per-MD5 lookup, not a resource)                                                                                     |
| Misc                    | `zia_domain_profiles`, `zia_gre_internal_ip_range_list`, `zia_cloud_app_control_rule_actions`, `zia_cloud_browser_isolation_profile`, `zia_forwarding_control_proxy_gateway` |

Always check the official Terraform Registry before assuming there's a matching resource:

- Resources index: <https://registry.terraform.io/providers/zscaler/zia/latest/docs>
- Specific resource: `https://registry.terraform.io/providers/zscaler/zia/latest/docs/resources/<name_without_zia_prefix>`
- Specific data source: `https://registry.terraform.io/providers/zscaler/zia/latest/docs/data-sources/<name_without_zia_prefix>`

If only the data-source page exists for an object, it's read-only.

❌ Do not propose a `resource "zia_department_management"`. Departments come from the IdP. ✅ Use `data "zia_department_management" { name = "Sales" }` to look one up.

## Credential Hygiene

- ❌ Never put `client_secret`, `private_key`, `password`, or `api_key` in `.tfvars` checked into git.
- ❌ Never echo credentials in CI job logs.
- ❌ **Do not mix `ZSCALER_*` and `ZIA_*` env vars in the same job** — the provider picks one path based on `use_legacy_client` and silently ignores the other namespace.
- ✅ Use env vars matching your auth path:
  - **OneAPI:** `ZSCALER_CLIENT_ID`, `ZSCALER_CLIENT_SECRET` (or `ZSCALER_PRIVATE_KEY`), `ZSCALER_VANITY_DOMAIN`, optionally `ZSCALER_CLOUD` for non-prod.
  - **Legacy:** `ZIA_USERNAME`, `ZIA_PASSWORD`, `ZIA_API_KEY`, `ZIA_CLOUD`, `ZSCALER_USE_LEGACY_CLIENT=true`.
- ✅ Mark every HCL variable carrying a credential `sensitive = true`.

State considerations: the OneAPI client secret is **not** persisted to state. IDs and configuration are. Encrypt state at rest (S3+KMS, Terraform Cloud / Enterprise) and restrict access.

## Reference Files

Progressive disclosure — essentials here, depth on demand:

- [Auth & Providers](references/auth-and-providers.md) — OneAPI vs legacy, env vars, GOV / `zscalerten`, multi-tenant aliases, credential hygiene.
- [Resource Catalog](references/resource-catalog.md) — minimum-viable HCL for the most-used `zia_*` resources, composition recipes, data-source lookups.
- [Rules & Ordering](references/rules-and-ordering.md) — `order` rules, predefined vs custom, contiguous ordering, common 400 errors, per-rule-type field stripping.
- [Activation](references/activation.md) — `zia_activation_status`, atomic vs manual, CI/CD pattern, gotchas.
- [Troubleshooting](references/troubleshooting.md) — drift causes, DUPLICATE_ITEM, predefined rule errors, country code / DLP-name validation, debug logging, never-`state rm`.
- [Recent Provider Changes](references/recent-provider-changes.md) — auto-mined from the upstream provider CHANGELOG; lists user-facing additions and breaking changes from the last several releases.

**Cross-cutting engineering discipline** (state organization, CI/CD with the activation step, secret handling, testing strategy, modules, naming, versioning) lives in the sibling **`best-practices-skill`** — load it whenever the question is about how to structure or operate a Zscaler-Terraform repo rather than how to call a specific `zia_*` resource.

## Authoring Rule — Grounding for Uncatalogued Resources

The reference catalog ships canonical HCL for the most-used `zia_*` resources, but ZIA exposes 71 resources and 101 data sources — too many to inline. When asked about a resource or data source not in [Resource Catalog](references/resource-catalog.md):

1. **Fetch the official Registry page first** before generating any HCL:
   - Resource: `https://registry.terraform.io/providers/zscaler/zia/latest/docs/resources/<name_without_zia_prefix>`
   - Data source: `https://registry.terraform.io/providers/zscaler/zia/latest/docs/data-sources/<name_without_zia_prefix>`
2. Ground every attribute name in that fetched page.
3. State the Registry URL you used in the Response Contract `Assumptions` section.

❌ Never invent attribute names because "they look like other ZIA resources." ✅ If the Registry page does not exist for a `zia_<name>`, the resource does not exist — say so explicitly and ask whether the user means a related object.

## What This Skill Will Not Do

- Generate HCL with attribute names not documented on the official Terraform Registry page for that resource.
- Recommend `terraform state rm` for ZIA resources.
- Cover provider development (Plugin SDK schema, expand/flatten, acceptance tests, sweepers) — out of scope.
