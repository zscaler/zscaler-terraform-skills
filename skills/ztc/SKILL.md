---
name: ztc-skill
description: Use when writing, reviewing, or debugging Terraform HCL that uses the Zscaler Zero Trust Cloud (ZTC, formerly Cloud Branch Connector) provider — covers provider auth (OneAPI / legacy / multi-cloud), the resource catalog (edge connector groups, location management, forwarding gateways, traffic forwarding rules, network services, IP source/destination/pool groups, workload groups, ZIA forwarding gateways), rule ordering semantics, the activation lifecycle (`ztc_activation_status`), and the data-source-first pattern for cloud-orchestrated objects.
license: MIT
metadata:
  author: Zscaler
  version: 0.1.3
---

# Zscaler Zero Trust Cloud (ZTC) Skill

Diagnose-first guidance for **end users writing Terraform HCL that consumes the `zscaler/ztc` provider**. ZTC is the Zscaler Zero Trust Cloud product (formerly Cloud Branch Connector — the rebrand affects branding only; resource names still use `ztc_` and the API path remains `/cloud-branch-connector`). This skill does not cover provider Go code.

**Canonical source of truth** for resource/data-source schemas: <https://registry.terraform.io/providers/zscaler/ztc/latest/docs>.

## Response Contract

Every ZTC HCL response must include:

1. **Assumptions & version floor** — `zscaler/ztc` provider version (`~> 0.1.x` is current; the provider is pre-1.0), Terraform/OpenTofu version, **auth mode (ASK if not stated — provider supports both OneAPI and legacy v3 as first-class options)**, cloud target (only set if non-default), and **whether the configuration creates or modifies any resource** (which makes activation mandatory).
2. **Risk category addressed** — one or more of: auth misconfiguration, resource catalog mismatch (including data-source-only objects), rule ordering, activation forgotten, drift, secret exposure, or **cloud-orchestrated-resource confusion** (treating a data source as a resource).
3. **Chosen approach & tradeoffs.**
4. **Validation plan** — `terraform fmt -check`, `terraform validate`, `terraform plan -out=tfplan`, **plus a `ztc_activation_status` step if any resource is created/modified** (changes are draft until activated).
5. **Rollback notes** — never `terraform state rm` a ZTC resource backed by a real API object.

The provider is pre-1.0 (`~> 0.1.x`). Surface this in the assumptions: schemas may change between minor releases. Pin to the exact patch version in production until 1.0 ships.

## Workflow

1. **Capture context** (see fields below).
2. **Diagnose intent** using the routing table.
3. **Load only the matching reference file(s).**
4. **Propose HCL** grounded in `references/resource-catalog.md` — never invent attribute names.
5. **Decide source vs sink** — many ZTC objects (locations, edge connector groups) are created out-of-band by cloud orchestration and **must** be referenced via data sources, not resources.
6. **Check rule ordering** (if any rule resource is touched).
7. **Decide activation** — explicit `ztc_activation_status` resource or document a manual activation step.
8. **Validate** with the commands tailored to risk tier.
9. **Emit the Response Contract.**

## Capture Context — Fields to Confirm

| Field             | Why it matters                                                                                              | Default if missing                |
| ----------------- | ----------------------------------------------------------------------------------------------------------- | --------------------------------- |
| Provider version  | Pre-1.0; schemas may change. Latest stable is `~> 0.1.x`.                                                    | Assume latest `0.1.x` and state it. |
| **Auth mode**     | **OneAPI and legacy v3 are both first-class.** Tenant must be migrated to Zidentity for OneAPI; otherwise legacy is the only option. `zscalergov` / `zscalerten` are legacy-only. | **Ask. Do not default.** State both options if unclear. |
| Cloud target      | OneAPI: `zscaler_cloud` is **optional** and only set for non-prod (e.g. `beta`). Legacy: `ztc_cloud` is required and names the cloud (`zscaler`, `zscloud`, `zscalergov`, …). | **Omit `zscaler_cloud` for production OneAPI.** Ask for legacy. |
| Activation        | **ANY** create/update/delete on a ZTC resource needs `ztc_activation_status`. Pure data-source workflows do not. | If any resource is touched: include activation. Always. |
| Cloud orchestration| Which objects already exist in the tenant (created by AWS/Azure/GCP integrations) vs. what TF should create. | Ask. Default: locations and edge connector groups exist. |
| Rule ordering     | `order` and `rank` apply to traffic forwarding rules — must follow the same rules as ZIA.                    | Ask if rule order matters.        |
| Terraform runtime | Affects `optional()`, `moved`, `import`, `removed` availability.                                            | Assume `terraform ~> 1.9`.        |

## Diagnose Before You Generate

| Failure category                           | Symptoms                                                                                                            | Primary references                                                                                              |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| **Auth misconfiguration**                  | `401 unauthorized`, `vanity_domain not found`, GOV cloud rejecting OneAPI                                           | [Auth & Providers](references/auth-and-providers.md)                                                            |
| **Cloud-orchestrated resource confusion**  | Trying to `resource "ztc_location_management"` instead of `data` — the object is created by the cloud integration   | [Resource Catalog: Cloud-Orchestrated Objects](references/resource-catalog.md#cloud-orchestrated-objects)        |
| **Resource catalog mismatch**              | Invented attribute names, wrong block structure                                                                     | [Resource Catalog](references/resource-catalog.md)                                                              |
| **Rule ordering**                          | `order = 0` rejected, rules drift after a delete, rule reorder race conditions                                       | [Rules & Ordering](references/rules-and-ordering.md)                                                            |
| **Activation forgotten**                   | `terraform apply` succeeds but config doesn't take effect                                                            | [Rules & Ordering: Activation](references/rules-and-ordering.md#activation)                                     |
| **OneAPI vs Legacy availability gap**      | Resource works on legacy auth but read returns empty / partial data on OneAPI (or vice versa)                        | [Troubleshooting: OneAPI vs Legacy gaps](references/troubleshooting.md#oneapi-vs-legacy-availability-gaps)      |
| **Drift on every plan**                    | Bool flips, computed defaults churn                                                                                  | [Troubleshooting: Drift Causes](references/troubleshooting.md#drift-causes)                                     |
| **Secret exposure**                        | Credentials in `.tfvars`, in state, in CI logs                                                                       | [Auth & Providers: Credential Hygiene](references/auth-and-providers.md#credential-hygiene)                     |

## Provider Block — Pick One

The provider supports **two** auth paths. Pick based on whether the tenant has been migrated to Zidentity. **Do not default** — confirm with the user.

> **Authoring rule (do not summarise):** when emitting an OneAPI provider block, reproduce the env-var comment list **verbatim** — including `ZSCALER_CLOUD` with its `optional` annotation. Users need to discover that `ZSCALER_CLOUD` exists as a supported (but optional) parameter; condensing it to `# ZSCALER_CLIENT_ID, ZSCALER_CLIENT_SECRET, ZSCALER_VANITY_DOMAIN` hides that fact.

### OneAPI (Zidentity tenants)

```hcl
terraform {
  required_version = "~> 1.9"
  required_providers {
    ztc = {
      source  = "zscaler/ztc"
      version = "~> 0.1.8"  # pin tight: provider is pre-1.0
    }
  }
}

provider "ztc" {
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
provider "ztc" {
  use_legacy_client = true
  # Env vars:
  #   ZTC_USERNAME, ZTC_PASSWORD, ZTC_API_KEY
  #   ZTC_CLOUD               ← REQUIRED on legacy: zscaler | zscloud | zscalerbeta | zscalergov | zscalerten | zspreview
  #   ZSCALER_USE_LEGACY_CLIENT=true
}
```

❌ Do not set `zscaler_cloud = "zscaler"` on OneAPI — `zscaler` is a **legacy** cloud name. On OneAPI, omit `zscaler_cloud` entirely for production tenants.

For private-key auth and credential hygiene, see [Auth & Providers](references/auth-and-providers.md).

## Resource Hierarchy

| Layer                          | Purpose                                              | Typical access pattern                                                       |
| ------------------------------ | ---------------------------------------------------- | ---------------------------------------------------------------------------- |
| **Edge connector groups**      | The compute fleet running the connector              | **Data source** (`data "ztc_edge_connector_group"`) — created by cloud orchestration |
| **Locations**                  | A site / VPC / VNet                                   | **Data source** (`data "ztc_location_management"`) — created by cloud orchestration |
| **Location templates**         | Templates for locations                              | Resource: `ztc_location_template`                                            |
| **Forwarding gateways**        | Outbound gateways (to ZIA, direct, third-party)     | Resource: `ztc_forwarding_gateway`, `ztc_dns_forwarding_gateway`, `ztc_zia_forwarding_gateway` |
| **DNS gateways**               | DNS resolution gateways                              | Resource: `ztc_dns_gateway`                                                  |
| **Traffic forwarding rules**   | Where traffic goes (rule with `order`, `rank`)        | Resource: `ztc_traffic_forwarding_rule`, `ztc_traffic_forwarding_dns_rule`, `ztc_traffic_forwarding_log_rule` |
| **Network services**           | Network service objects                              | Resource: `ztc_network_services`, `ztc_network_services_groups`              |
| **IP groups**                  | Source / destination / pool address groups           | Resource: `ztc_ip_source_groups`, `ztc_ip_destination_groups`, `ztc_ip_pool_groups` |
| **Workload groups**            | Workload classification (cross-references ZIA)       | Resource: `ztc_workload_groups` (also data source from `zia_workload_groups`) |
| **Provisioning URL**           | Per-edge bootstrap URL                               | Resource: `ztc_provisioning_url`                                             |
| **Activation**                 | **Required** to push draft changes live              | Resource: `ztc_activation_status`                                            |

## Naming Conventions

- Use descriptive names: `resource "ztc_traffic_forwarding_rule" "direct_to_branch_a"`, not `... "this"`.
- Reserve `"this"` for genuine singletons (`ztc_activation_status`).
- Standard files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `providers.tf`.
- Keep one Terraform configuration per ZTC tenant — activation has tenant-wide effect.

## Cloud-Orchestrated Objects — Critical Pattern

In ZTC, **edge connector groups and locations** are typically created automatically when a cloud connector spins up in AWS / Azure / GCP. The provider exposes them only as **data sources** (and where a resource exists, you usually still want to read the orchestrated one rather than create a new one). Trying to `resource "ztc_location_management"` with the same name as an existing orchestrated location will fail with `DUPLICATE_ITEM`.

```hcl
data "ztc_location_management" "aws_vpc" {
  name = "AWS-CAN-ca-central-1-vpc-05c7f364cf47c2b93"
}

data "ztc_edge_connector_group" "aws_vpc_a" {
  name = "zs-cc-vpc-096108eb5d9e68d71-ca-central-1a"
}

resource "ztc_traffic_forwarding_rule" "this" {
  # ...
  locations { id = [data.ztc_location_management.aws_vpc.id] }
}
```

❌ Do not `resource "ztc_location_management"` for cloud-orchestrated locations. ✅ Always go through the data source for these. See [Resource Catalog: Cloud-Orchestrated Objects](references/resource-catalog.md#cloud-orchestrated-objects).

## Rule Resources — Critical Rules

These apply to **every** rule-style resource: `ztc_traffic_forwarding_rule`, `ztc_traffic_forwarding_dns_rule`, `ztc_traffic_forwarding_log_rule`.

- ❌ `order = 0` or negative — rejected.
- ❌ Non-contiguous orders after a delete — causes drift.
- ✅ All rules of the same type managed in one Terraform configuration.
- ✅ Use the `ztc_activation_status` resource to push draft changes live.

The provider has known reorder race conditions across rule types; v0.1.7 fixed an async race where the reorder timer fired before all rules were registered. **Pin to v0.1.8+** if you manage multiple rule types in one apply. See [Rules & Ordering](references/rules-and-ordering.md).

## Activation — Hard Rule

**Every** create/update/delete on a ZTC resource produces a draft change that **must** be activated to take effect. Only **pure data-source workflows** (read-only) skip it.

| Pattern                              | When                                                                |
| ------------------------------------ | ------------------------------------------------------------------- |
| Manage `ztc_activation_status` in TF | Atomic per-apply activation — recommended for CI/CD.                |
| `ztcActivator` CLI out-of-band       | When activation is decoupled (e.g. nightly batch).                  |
| **Skip activation entirely**         | **Only** when the configuration uses `data "ztc_…"` exclusively — no `resource "ztc_…"`. |

Reference pattern (atomic activation):

```hcl
resource "ztc_traffic_forwarding_rule" "direct_to_branch_a" {
  name           = "DIRECT_to_branch_a"
  order          = 1
  state          = "ENABLED"
  type           = "EC_RDR"
  forward_method = "DIRECT"
  # …
}

resource "ztc_activation_status" "this" {
  status     = "ACTIVE"
  depends_on = [ztc_traffic_forwarding_rule.direct_to_branch_a]
}
```

See [Rules & Ordering: Activation](references/rules-and-ordering.md#activation).

## Data-Source-Only Objects

ZTC exposes 19 data sources but only 14 resources. Some objects are read-only because they are populated by cloud orchestration or by another Zscaler product:

| Data source                    | Why it's read-only                                                                                        |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| `ztc_edge_connector_group`     | Created by AWS / Azure / GCP cloud connector orchestration when a connector VM spins up.                  |
| `ztc_location_management`      | Auto-provisioned per VPC / VNet by the cloud integration. (A resource exists too, but use the data source for orchestrated locations.) |
| `ztc_account_groups`           | Tenant-level grouping; managed in the ZTC console.                                                         |
| `ztc_supported_regions`        | Cloud-provider region catalog the connector can run in.                                                    |
| `ztc_activation_status`        | Read-side companion to the activation resource — useful for asserting state in tests.                      |

❌ Do not propose a `resource "ztc_edge_connector_group"`. It does not exist; use `data "ztc_edge_connector_group" { name = "…" }` to look one up.

## Credential Hygiene

- ❌ Never put `client_secret`, `private_key`, legacy `password`, or `api_key` in checked-in `.tfvars`.
- ❌ Never echo credentials in CI job logs.
- ❌ **Do not mix `ZSCALER_*` and `ZTC_*` env vars in the same job** — the provider picks one path based on `use_legacy_client` and silently ignores the other namespace.
- ✅ Use env vars matching your auth path:
  - **OneAPI:** `ZSCALER_CLIENT_ID`, `ZSCALER_CLIENT_SECRET` (or `ZSCALER_PRIVATE_KEY`), `ZSCALER_VANITY_DOMAIN`, optionally `ZSCALER_CLOUD` for non-prod.
  - **Legacy:** `ZTC_USERNAME`, `ZTC_PASSWORD`, `ZTC_API_KEY`, `ZTC_CLOUD`, `ZSCALER_USE_LEGACY_CLIENT=true`.
- ✅ Mark every HCL variable carrying a credential `sensitive = true`.

## Reference Files

Progressive disclosure:

- [Auth & Providers](references/auth-and-providers.md) — OneAPI vs legacy, env vars, GOV / `zscalerten`, multi-tenant aliases, credential hygiene.
- [Resource Catalog](references/resource-catalog.md) — minimum-viable HCL for each ZTC resource, cloud-orchestrated vs Terraform-created objects, composition recipes.
- [Rules & Ordering](references/rules-and-ordering.md) — `order` and `rank` semantics, contiguous ordering, rule-reorder race conditions, activation lifecycle.
- [Troubleshooting](references/troubleshooting.md) — drift causes, OneAPI vs Legacy gaps, debug logging, never-`state rm`.
- [Recent Provider Changes](references/recent-provider-changes.md) — auto-mined from the upstream provider CHANGELOG.

**Cross-cutting engineering discipline** (state organization, CI/CD with the activation step, secret handling, testing strategy, modules, naming, versioning) lives in the sibling **`best-practices-skill`** — load it whenever the question is about how to structure or operate a Zscaler-Terraform repo rather than how to call a specific `ztc_*` resource.

## Authoring Rule — Grounding for Uncatalogued Resources

The reference catalog ships canonical HCL for the most-used `ztc_*` resources, but ZTC exposes 14 resources and 19 data sources. When asked about an object not in [Resource Catalog](references/resource-catalog.md):

1. **Fetch the official Registry page first** before generating any HCL:
   - Resource: `https://registry.terraform.io/providers/zscaler/ztc/latest/docs/resources/<name_without_ztc_prefix>`
   - Data source: `https://registry.terraform.io/providers/zscaler/ztc/latest/docs/data-sources/<name_without_ztc_prefix>`
2. Ground every attribute name in that fetched page.
3. State the Registry URL you used in the Response Contract `Assumptions` section.

❌ Never invent attribute names. ✅ If the Registry page does not exist for a `ztc_<name>`, the resource does not exist — say so explicitly.

## What This Skill Will Not Do

- Generate HCL with attribute names not documented on the official Terraform Registry page for that resource.
- Recommend `terraform state rm` for ZTC resources backed by real API objects.
- Recommend creating a `ztc_location_management` resource for a cloud-orchestrated location.
- Cover provider development.
