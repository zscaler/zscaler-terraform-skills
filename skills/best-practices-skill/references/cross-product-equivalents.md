# Cross-Product Equivalents — Zscaler Terraform

Side-by-side tables across the four Zscaler providers (`zpa`, `zia`, `ztc`, `zcc`) so the four can be treated as **peers** instead of "ZPA + three afterthoughts". Use this reference whenever a user asks "what's the ZIA equivalent of …" or whenever a prompt mentions more than one product.

For host-cloud (AWS / Azure / GCP) state-backend equivalents, see [State Management: Backend Choice — Per Host Cloud](state-management.md#backend-choice--per-host-cloud).
For host-cloud CI auth (state-backend OIDC), see [CI/CD: State-Backend Auth from CI](ci-cd-zscaler.md#state-backend-auth-from-ci-cross-cloud).

## Decision Table — Which Reference Do I Need?

| Asking about…                                                | Use                                                                                       |
| ------------------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| "What's the ZIA equivalent of a ZPA segment_group?"          | [Resource Concept Map](#resource-concept-map) — first, then per-product `references/resource-catalog.md` |
| "How do I auth ZTC vs ZIA?"                                  | [Auth Env-Var Matrix](#auth-env-var-matrix)                                               |
| "Does ZCC need activation?"                                  | [Activation Lifecycle](#activation-lifecycle)                                              |
| "Which products support microtenants?"                        | [Tenancy & Multi-Tenancy Models](#tenancy--multi-tenancy-models)                          |
| "What version pin should I use for each provider?"           | [Version Pin Floors](#version-pin-floors)                                                  |
| "How do I forward ZIA traffic to a ZPA gateway?"             | [Cross-Product Composition Recipes](#cross-product-composition-recipes)                    |
| "Why are the four so different?"                              | [What's NOT Cross-Product](#whats-not-cross-product)                                       |

---

## Resource Concept Map

Not every Zscaler API has a peer in the other three. Use this map to set user expectations *before* searching for an analog that doesn't exist.

| Concept                            | ZPA                                                | ZIA                                                            | ZTC                                                       | ZCC                                                |
| ---------------------------------- | -------------------------------------------------- | -------------------------------------------------------------- | --------------------------------------------------------- | -------------------------------------------------- |
| **Policy rule**                     | `zpa_policy_access_rule_v2` (+ forwarding / inspection / isolation variants) | `zia_url_filtering_rules`, `zia_firewall_filtering_rule`, `zia_dlp_web_rules`, … | `ztc_traffic_forwarding_rule`, `ztc_traffic_forwarding_dns_rule` | — (no rule-based policy)                           |
| **Group of policy targets**         | `zpa_segment_group`, `zpa_server_group`            | n/a (rules reference categories / departments / locations directly) | n/a (rules reference locations and network services)       | — (no policy targeting)                            |
| **Logical location / entry point**  | `zpa_app_connector_group`                          | `zia_location_management`                                       | `data "ztc_location_management"` (cloud-orchestrated)      | `zcc_trusted_network`                              |
| **Identity reference**              | `data "zpa_idp_controller"`, `data "zpa_scim_groups"` | `data "zia_department_management"`, `data "zia_group_management"` | n/a                                                        | `data "zcc_admin_user"`                             |
| **Activation handle**               | — (changes apply on `terraform apply`)             | `zia_activation_status`                                         | `ztc_activation_status`                                    | — (changes apply on `terraform apply`)             |
| **Microtenant scoping field**       | `microtenant_id` on resources                      | — (not exposed)                                                 | — (not exposed)                                            | — (not exposed)                                    |
| **Cross-product wiring resource**   | (consumed by `zia_forwarding_control_zpa_gateway`) | `zia_forwarding_control_zpa_gateway` (references ZPA server group) | n/a                                                        | `zcc_forwarding_profile` (references ZIA tunnels)  |

❌ Do not invent ZIA's "segment_group" or ZCC's "activation_status" — they do not exist.
✅ When a user asks for an equivalent that has no peer, name the **closest concept** and explain why the analogy breaks (e.g. "ZIA rules reference categories directly; there is no grouping layer like ZPA's `zpa_segment_group`").

---

## Auth Env-Var Matrix

Both OneAPI (Zidentity) and legacy v3 (per-product) are **first-class** for all four providers. Pick one per job — never mix `ZSCALER_*` with `<product>_*` in the same job. The provider silently ignores the wrong namespace based on `use_legacy_client`.

### OneAPI (Zidentity tenants)

| Provider | Required                                                                                       | Optional                                       | Notes                                                                  |
| -------- | ---------------------------------------------------------------------------------------------- | ---------------------------------------------- | ---------------------------------------------------------------------- |
| ZPA      | `ZSCALER_CLIENT_ID`, `ZSCALER_CLIENT_SECRET` (or `ZSCALER_PRIVATE_KEY`), `ZSCALER_VANITY_DOMAIN`, `ZPA_CUSTOMER_ID` | `ZSCALER_CLOUD` (`beta` for non-prod; `gov` / `govus` for FedRAMP on `v4.4.6`+), `ZPA_MICROTENANT_ID` | `ZPA_CUSTOMER_ID` is required on **both** auth modes.                  |
| ZIA      | `ZSCALER_CLIENT_ID`, `ZSCALER_CLIENT_SECRET` (or `ZSCALER_PRIVATE_KEY`), `ZSCALER_VANITY_DOMAIN` | `ZSCALER_CLOUD` (`beta` for non-prod; `gov` / `govus` for FedRAMP on `v4.7.25`+) | Does **not** need `ZPA_CUSTOMER_ID`.                 |
| ZTC      | `ZSCALER_CLIENT_ID`, `ZSCALER_CLIENT_SECRET` (or `ZSCALER_PRIVATE_KEY`), `ZSCALER_VANITY_DOMAIN` | `ZSCALER_CLOUD` (only for non-prod)            | Does **not** need `ZPA_CUSTOMER_ID`. **No released FedRAMP OneAPI support** — use legacy. |
| ZCC      | `ZSCALER_CLIENT_ID`, `ZSCALER_CLIENT_SECRET` (or `ZSCALER_PRIVATE_KEY`), `ZSCALER_VANITY_DOMAIN` | `ZSCALER_CLOUD` (only for non-prod)            | Does **not** need `ZPA_CUSTOMER_ID`.                                   |

### Legacy v3 (pre-Zidentity tenants, and ZTC FedRAMP)

| Provider | Required                                                                                       | Notes                                                                  |
| -------- | ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| ZPA      | `ZPA_CLIENT_ID`, `ZPA_CLIENT_SECRET`, `ZPA_CUSTOMER_ID`, `ZSCALER_USE_LEGACY_CLIENT=true`     | `ZPA_CLOUD` only when not `PRODUCTION`: `BETA`, `ZPATWO`, `GOV`, `GOVUS`, `PREVIEW`. |
| ZIA      | `ZIA_USERNAME`, `ZIA_PASSWORD`, `ZIA_API_KEY`, `ZIA_CLOUD`, `ZSCALER_USE_LEGACY_CLIENT=true`  | `ZIA_CLOUD` is **always required** on legacy: `zscaler`, `zscloud`, `zscalergov`, `zscalerten`, etc. |
| ZTC      | `ZTC_USERNAME`, `ZTC_PASSWORD`, `ZTC_API_KEY`, `ZTC_CLOUD`, `ZSCALER_USE_LEGACY_CLIENT=true`  | Same cloud-name set as ZIA.                                            |
| ZCC      | `ZCC_CLIENT_ID`, `ZCC_CLIENT_SECRET`, `ZCC_CLOUD`, `ZSCALER_USE_LEGACY_CLIENT=true`           | ZCC legacy uses a v2 client, not a v3 user/password.                   |

❌ `zscaler_cloud = "PRODUCTION"` on OneAPI — `PRODUCTION` is a **legacy** value. On OneAPI, omit it.
❌ `zscaler_cloud = "zscaler"` on OneAPI — `zscaler` is a **legacy ZIA cloud name**.
❌ `zscaler_cloud = "zscalergov"` / `"GOV"` on OneAPI — also legacy names. OneAPI uses lowercase `gov` / `govus`.
✅ On OneAPI for commercial production tenants: omit the cloud attribute entirely.
✅ On OneAPI for FedRAMP tenants: set `gov` or `govus` (ZIA `v4.7.25`+, ZPA `v4.4.6`+).

---

## Cloud Target Rules

| Cloud target attr / env var       | OneAPI                                                       | Legacy                                                         |
| ---------------------------------- | ------------------------------------------------------------ | -------------------------------------------------------------- |
| ZPA: `zpa_cloud` / `ZPA_CLOUD`     | n/a (use `ZSCALER_CLOUD` if needed)                          | Only set when NOT `PRODUCTION`. Values: `BETA`, `ZPATWO`, `GOV`, `GOVUS`, `PREVIEW`. |
| ZIA: `zia_cloud` / `ZIA_CLOUD`     | n/a (use `ZSCALER_CLOUD` if needed)                          | **Always required**. Values: `zscaler`, `zscloud`, `zscalerbeta`, `zscalerone`, `zscalertwo`, `zscalerthree`, `zscalergov`, `zscalerten`, `zspreview`. |
| ZTC: `ztc_cloud` / `ZTC_CLOUD`     | n/a (use `ZSCALER_CLOUD` if needed)                          | **Always required**. Same cloud-name set as ZIA.               |
| ZCC: `zcc_cloud` / `ZCC_CLOUD`     | n/a (use `ZSCALER_CLOUD` if needed)                          | **Always required**.                                           |
| All: `zscaler_cloud` / `ZSCALER_CLOUD` | Optional for commercial production. Set `beta` for non-prod, or `gov` / `govus` for FedRAMP (ZIA `v4.7.25`+, ZPA `v4.4.6`+; not yet released for ZTC). | n/a |

---

## Activation Lifecycle

| Provider | Activation needed?                                                | Resource                                | If you forget                                                  |
| -------- | ----------------------------------------------------------------- | --------------------------------------- | -------------------------------------------------------------- |
| ZPA      | ❌ No — changes apply on `terraform apply`                         | —                                       | n/a                                                            |
| ZIA      | ✅ **Yes — for any create/update/delete on any `zia_*` resource**  | `zia_activation_status`                 | Apply succeeds; tenant shows **draft**; users see no change.   |
| ZTC      | ✅ **Yes — for any create/update/delete on any `ztc_*` resource**  | `ztc_activation_status`                 | Same as ZIA. Alternative: `ztcActivator` CLI for out-of-band.  |
| ZCC      | ❌ No — changes apply on `terraform apply`                         | —                                       | n/a                                                            |

Atomic-activation pattern (ZIA / ZTC):

```hcl
resource "zia_activation_status" "this" {
  status = "ACTIVE"

  depends_on = [
    zia_url_filtering_rules.block_gambling,
    zia_firewall_filtering_rule.allow_finance_egress,
  ]
}
```

❌ Pure data-source workflows do not need activation — only `resource "zia_*"` / `resource "ztc_*"` blocks trigger it.
❌ Multiple `zia_activation_status` in the same state — collapses to whichever applies last, no benefit.
✅ One `<product>_activation_status` per state, `depends_on` covering every config-affecting resource.

See [CI/CD: Activation as a Pipeline Stage](ci-cd-zscaler.md#activation-as-a-pipeline-stage) for the three activation patterns (in-state, two-stage, manual).

---

## Tenancy & Multi-Tenancy Models

| Concept                            | ZPA                                                | ZIA                                                            | ZTC                                                       | ZCC                                                |
| ---------------------------------- | -------------------------------------------------- | -------------------------------------------------------------- | --------------------------------------------------------- | -------------------------------------------------- |
| Primary tenant scope               | `ZPA_CUSTOMER_ID` (required, both auth modes)      | `ZSCALER_VANITY_DOMAIN` / `ZIA_CLOUD` + creds                  | `ZSCALER_VANITY_DOMAIN` / `ZTC_CLOUD` + creds              | `ZSCALER_VANITY_DOMAIN` / `ZCC_CLOUD` + creds      |
| Microtenant scope                  | ✅ `microtenant_id` per resource / `ZPA_MICROTENANT_ID` env | ❌ Not exposed (one tenant per ZIA cloud)                       | ❌ Not exposed                                             | ❌ Not exposed                                     |
| Cross-tenant fan-out via aliases   | ✅ `provider "zpa" { alias = "tenant_a" }`         | ✅ `provider "zia" { alias = "tenant_a" }`                      | ✅ `provider "ztc" { alias = "tenant_a" }`                 | ✅ `provider "zcc" { alias = "tenant_a" }`         |

❌ Mixing parent-tenant and microtenant-scoped ZPA resources in one config without separating them — Read silently returns 404 on the mis-scoped reads → Terraform recreates the resource on every plan.
✅ For multi-microtenant orgs, one state file per microtenant cohort. See [State Management: Multi-Tenant / Multi-Microtenant State](state-management.md#multi-tenant--multi-microtenant-state).

---

## Version Pin Floors

| Provider | Source           | Recommended pin   | Why                                                                  |
| -------- | ---------------- | ----------------- | -------------------------------------------------------------------- |
| ZPA      | `zscaler/zpa`    | `~> 4.0`          | Post-1.0; OneAPI introduced in v4. Pessimistic minor pin.            |
| ZIA      | `zscaler/zia`    | `~> 4.0`          | Post-1.0; OneAPI introduced in v4. Pessimistic minor pin.            |
| ZTC      | `zscaler/ztc`    | `~> 0.1.8`        | **Pre-1.0; pin tight in production.** v0.1.7 fixed async rule reorder; v0.1.8 added deferred ReadContext. |
| ZCC      | `zscaler/zcc`    | `~> 0.1.0`        | **Pre-1.0; pin tight in production.** Schema may change between minor releases. |

❌ `version = ">= 4.0"` (open-ended) — provider upgrades land in prod uncontrolled.
❌ `version = "= 4.0.3"` exact pin on ZPA / ZIA — blocks security patches.
✅ `~> 4.0` for post-1.0 (ZPA, ZIA).
✅ `~> 0.1.8` for pre-1.0 (ZTC, ZCC) — exact patch pin in production until 1.0 ships.

---

## Rule-Style Resource Rules

For ZIA, ZTC (and partially the v2 ZPA policy resources), rule-style resources share the same hard rules:

| Rule                                                         | ZPA (`*_v2`)             | ZIA                                  | ZTC                                  | ZCC |
| ------------------------------------------------------------ | ------------------------ | ------------------------------------ | ------------------------------------ | --- |
| `order >= 1` (positive int, server-validated)                | ✅ (`IntAtLeast(1)`)      | ✅                                    | ✅                                    | n/a |
| Contiguous order across rules of the same type               | n/a (operand-driven)     | ✅ (gaps cause drift)                 | ✅                                    | n/a |
| Predefined rules cannot be `terraform destroy`'d             | n/a                      | ✅                                    | ✅                                    | n/a |
| Predefined rules **can** be reordered via Terraform          | n/a                      | ✅ (provider 4.7.9+)                  | ✅ (provider 0.1.7+)                  | n/a |
| `state = "ENABLED"` (string, not boolean)                    | n/a                      | ✅                                    | ✅                                    | n/a |

❌ `order = 0` or negative — rejected at plan time on ZIA and ZTC.
❌ `state = true` — must be the string `"ENABLED"` / `"DISABLED"` on ZIA and ZTC.
❌ `terraform destroy` against a predefined rule — not supported on ZIA or ZTC.
✅ For deletes of custom rules, use `terraform apply -target=<resource>` then re-adjust surviving order numbers in HCL to stay contiguous.

---

## Data-Source-Only Object Categories

All four providers ship more data sources than resources. Categories where you'll **always** be using `data` blocks:

| Category                       | Why data-only                                                                       | Examples per product                                                                                                  |
| ------------------------------ | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Identity (IdP-driven)          | Populated by the customer's IdP, not by Zscaler.                                    | ZPA: `zpa_idp_controller`, `zpa_scim_groups`. ZIA: `zia_department_management`, `zia_group_management`, `zia_devices`. ZCC: `zcc_devices`, `zcc_admin_user`. |
| Predefined catalogs            | Curated by Zscaler; mutating them would break the product.                          | ZIA: `zia_dlp_dictionary_predefined_identifiers`, `zia_firewall_filtering_application_services`. ZPA: `zpa_policy_type`. |
| Cloud-orchestrated objects     | Created by AWS/Azure/GCP integrations or vendor MDM, not by Terraform.              | ZPA: `zpa_app_connector_controller`, `zpa_branch_connector_group`. ZTC: `zia_edge_connector_group`, `ztc_location_management` for cloud locations. |
| Lookups / helpers              | Read-only helper objects (e.g. supported regions, valid client types).              | ZPA: `zpa_application_segment_by_type`, `zpa_access_policy_platforms`. ZTC: `zia_supported_regions`.                  |

❌ `resource "zpa_idp_controller"` — IdPs are configured in the ZPA admin console.
❌ `resource "zia_department_management"` — departments come from the IdP.
✅ `data "<product>_<object>" { name = "…" }` and feed the `.id` into the resource that consumes it.

See each per-product skill's "Data-Source-Only Objects" section for the full list.

---

## Cross-Product Composition Recipes

When two Zscaler products work together, the wiring lives in **data-source lookups across providers**, not in inlined IDs. If the two are managed in different states, use `terraform_remote_state` instead (see [State Management: Cross-State References](state-management.md#cross-state-references)).

### ZIA forwards to a ZPA gateway

```hcl
# providers.tf — both providers configured in the same root
provider "zpa" { /* OneAPI env vars */ }
provider "zia" { /* OneAPI env vars */ }

# data.tf — look up the ZPA server group by name
data "zpa_server_group" "prod_webapp" {
  provider = zpa
  name     = "prod-webapp-servers"
}

# main.tf — wire ZIA to ZPA
resource "zia_forwarding_control_zpa_gateway" "to_webapp" {
  provider = zia
  name     = "to-prod-webapp"

  zpa_server_group {
    external_id = data.zpa_server_group.prod_webapp.id
    name        = data.zpa_server_group.prod_webapp.name
  }
}

resource "zia_activation_status" "this" {
  status     = "ACTIVE"
  depends_on = [zia_forwarding_control_zpa_gateway.to_webapp]
}
```

❌ Hardcoding the ZPA server group ID into the ZIA resource. Tenant-specific.
✅ Data-source lookup across providers in the same root, or `terraform_remote_state` if the ZPA platform state lives elsewhere.

### ZCC trusted network gates a ZIA tunnel

```hcl
resource "zcc_trusted_network" "corp_office" {
  network_name    = "corp-office"
  active          = true
  condition_type  = 1
  trusted_subnets = "10.0.0.0/8"
}

resource "zcc_forwarding_profile" "default" {
  name                       = "default-profile"
  evaluate_trusted_network   = true
  trusted_network_ids        = [zcc_trusted_network.corp_office.id]
  # … forwarding decisions (tunnel-to-ZIA vs direct) consume the trusted_network match
}
```

ZCC has no activation step — the forwarding profile is live on `terraform apply`. The corresponding ZIA tunnel configuration lives in the ZIA state and requires `zia_activation_status`.

### ZTC location feeds a ZIA forwarding policy

```hcl
data "ztc_location_management" "aws_vpc" {
  name = "AWS-CAN-ca-central-1-vpc-A"
}

# ZIA forwarding policy references the same logical location
data "zia_location_lite" "aws_vpc" {
  name = "AWS-CAN-ca-central-1-vpc-A"
}

resource "zia_forwarding_control_rule" "from_aws_vpc" {
  name  = "from-aws-vpc"
  state = "ENABLED"
  order = 1

  locations {
    id = [data.zia_location_lite.aws_vpc.id]
  }
  # …
}
```

The location is **owned by ZTC** (created by the AWS integration) and **referenced from ZIA** via `zia_location_lite`. Do not create the location twice.

---

## What's NOT Cross-Product

Stating the limits explicitly, so the agent does not invent equivalents.

| Concept                            | What's missing                                                                                  |
| ---------------------------------- | ----------------------------------------------------------------------------------------------- |
| `microtenant_id` outside ZPA       | ZIA, ZTC, and ZCC do **not** expose a microtenant attribute. One tenant per cloud per product.   |
| `<product>_activation_status` for ZPA / ZCC | Does not exist; changes are live on `terraform apply`.                                          |
| `segment_group` / `server_group` outside ZPA | ZIA rules reference categories / departments / locations directly; no grouping layer.        |
| `dynamic "operands"` outside ZPA policy | The ZIA / ZTC rule schema is flat — no nested operand structure.                                |
| Singleton-with-no-API-delete pattern outside ZCC | Only `zcc_failopen_policy` and `zcc_web_app_service` have this lifecycle.                  |

❌ Do not propose `zia_microtenant_id`, `zpa_activation_status`, `zia_segment_group`, or `zia_policy_access_rule_v2`. None exist.
✅ Name the closest concept and explain the gap.

---

## Quick Cross-Reference

| You see…                                                | Likely product         | Likely cross-product link                                                       |
| ------------------------------------------------------- | ---------------------- | ------------------------------------------------------------------------------- |
| `zpa_application_segment` + `microtenant_id`            | ZPA on microtenant     | [Tenancy & Multi-Tenancy Models](#tenancy--multi-tenancy-models)                |
| `zia_url_filtering_rules` + missing activation          | ZIA forgot activation  | [Activation Lifecycle](#activation-lifecycle)                                    |
| `ztc_traffic_forwarding_rule` + AWS VPC location        | ZTC cloud-orchestrated | [Resource Concept Map](#resource-concept-map), per-product `references/resource-catalog.md` |
| Mixed `ZSCALER_*` + `ZIA_*` env vars                    | Auth env-var trap      | [Auth Env-Var Matrix](#auth-env-var-matrix)                                     |
| `zia_forwarding_control_zpa_gateway` with hardcoded ID  | Cross-product wiring   | [Cross-Product Composition Recipes](#cross-product-composition-recipes)         |
| `condition_type = 0 vs 1` flipping                       | ZCC                    | `zcc-skill` → troubleshooting.md (no cross-product analog)                      |

---

## Related

- [Quick Reference](quick-reference.md) — fast-lookup DO/DON'T across all four products.
- [State Management](state-management.md) — host-cloud backend choice + cross-state references.
- [CI/CD for Zscaler](ci-cd-zscaler.md) — activation as a pipeline stage + cross-cloud OIDC.
- Per-product skills (`zpa-skill`, `zia-skill`, `ztc-skill`, `zcc-skill`) — resource catalog, auth detail, and known quirks for each provider in isolation.
