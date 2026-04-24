# Zscaler Terraform — Quick Reference

DO / DON'T cheat sheet across all four Zscaler providers and the cross-cutting practices skill. Use as a fast-path lookup; route to the relevant provider skill or detailed reference for depth.

## Provider Floors

| Provider         | Source           | Recommended pin   | Notes                                                |
| ---------------- | ---------------- | ----------------- | ---------------------------------------------------- |
| ZPA              | `zscaler/zpa`    | `~> 4.0`          | OneAPI: `~> 4.0`. Legacy v3 still supported.         |
| ZIA              | `zscaler/zia`    | `~> 4.0`          | OneAPI: `~> 4.0`. Legacy v3 still supported.         |
| ZTC              | `zscaler/ztc`    | `~> 0.1`          | OneAPI + legacy v3. Pre-1.0; pin exact patch in prod. |
| ZCC              | `zscaler/zcc`    | `~> 0.1`          | OneAPI + legacy v2 ZCC. Pre-1.0; pin exact patch.    |
| Terraform runtime| `hashicorp/terraform` | `~> 1.9`     | 1.6+ for `terraform test`, 1.10+ for `use_lockfile`. |

## Auth Cheat Sheet

### OneAPI (Zidentity tenants)

```hcl
provider "zia" {                       # same shape for zpa, ztc, zcc
  # Env vars only — never inline:
  #   ZSCALER_CLIENT_ID       (required)
  #   ZSCALER_CLIENT_SECRET   (required; or ZSCALER_PRIVATE_KEY)
  #   ZSCALER_VANITY_DOMAIN   (required)
  #   ZSCALER_CLOUD           (optional — only for non-prod, e.g. "beta")
}
```

ZPA needs one extra:

```hcl
provider "zpa" {
  # ZPA_CUSTOMER_ID            (required for both auth modes)
  # ZPA_MICROTENANT_ID         (optional)
}
```

### Legacy v3 (pre-Zidentity, GOV, `zscalerten`)

```hcl
provider "zia" {
  use_legacy_client = true
  # Env vars:
  #   ZIA_USERNAME, ZIA_PASSWORD, ZIA_API_KEY
  #   ZIA_CLOUD     ← REQUIRED on legacy
  #   ZSCALER_USE_LEGACY_CLIENT=true
}
```

❌ Never set `zscaler_cloud = "zscaler"` on OneAPI — that's a **legacy** cloud name. On OneAPI, omit `zscaler_cloud` entirely for production tenants.

❌ Never mix `ZSCALER_*` and `<product>_*` env vars in the same job — provider picks one path and silently ignores the other.

## Activation — Hard Rules

| Provider | Activation needed?                                                | Resource                                |
| -------- | ----------------------------------------------------------------- | --------------------------------------- |
| ZPA      | No — changes apply on `terraform apply`                           | —                                       |
| ZIA      | **Yes — for any create/update/delete on any `zia_*` resource**     | `zia_activation_status`                 |
| ZTC      | **Yes — for any create/update/delete on any `ztc_*` resource**     | `ztc_activation_status`                 |
| ZCC      | No — changes apply on `terraform apply`                           | —                                       |

❌ ZIA / ZTC: never apply resource changes without including `<product>_activation_status` in the same state.
✅ Pure data-source workflows skip activation (no `resource` blocks → nothing to activate).

## Looping — `count` vs `for_each`

| Goal                                          | Use                                  | Why                                                |
| --------------------------------------------- | ------------------------------------ | -------------------------------------------------- |
| Optional resource (create / don't)            | `count = condition ? 1 : 0`          | Singleton toggle.                                  |
| List of named Zscaler objects                 | `for_each = toset(list)` or `map`    | Stable addresses on add / remove.                  |
| Reference by key                              | `for_each = map`                     | Named access (`each.key`, `each.value`).           |

❌ `count = length(var.applications)` over a list — removing the middle item churns every downstream resource address.

## Rule Resources — Critical Rules (ZIA + ZTC)

- ❌ `order = 0` or negative — rejected at plan time (`IntAtLeast(1)`).
- ❌ Non-contiguous orders (`1, 2, 5`) after a delete — causes drift on next plan.
- ❌ `terraform destroy` against a predefined rule — not supported.
- ✅ Use `terraform apply -target=<resource>` to delete specific custom rules; re-adjust surviving order numbers in HCL.
- ✅ Predefined rules **can** be reordered via Terraform (provider 4.7.9+ for ZIA).

## Data-Source-Only Objects (Common Footguns)

These exist as `data` blocks but **not** as `resource` blocks. Trying to declare them as resources fails.

| Provider | Common data-source-only objects                                                                                              |
| -------- | ---------------------------------------------------------------------------------------------------------------------------- |
| ZPA      | `zpa_idp_controller`, `zpa_scim_groups`, `zpa_scim_attribute_header`, `zpa_posture_profile`                                   |
| ZIA      | `zia_department_management`, `zia_group_management`, `zia_devices`, `zia_dlp_dictionary_predefined_identifiers`, `zia_location_lite` |
| ZTC      | `zia_edge_connector_group`, `zia_supported_regions`, `zia_zia_workload_group`                                                  |
| ZCC      | `zcc_devices`, `zcc_admin_user`, `zcc_admin_roles`, `zcc_custom_ip_apps`                                                       |

## State Discipline

- ❌ All four products in one state file.
- ❌ Production and non-production in one state.
- ❌ `terraform state rm` on any Zscaler resource — orphans the API object.
- ✅ One state per blast-radius / approval-ownership boundary.
- ✅ Remote backend with native locking (S3 + `use_lockfile`, GCS, Azure Blob, Terraform Cloud).
- ✅ Encrypt state at rest; restrict access to the owning team.

## Secret Discipline

- ❌ `client_secret` / `password` / `api_key` in `.tfvars` checked into git.
- ❌ Credentials in `var.*` on Terraform `< 1.11` — they land in state.
- ❌ Mixing `ZSCALER_*` and `<product>_*` env vars in the same job.
- ✅ CI secret env vars only.
- ✅ On 1.11+: `*_wo` write-only attributes when the provider exposes them.
- ✅ OIDC against Zidentity when supported (eliminates long-lived static keys).
- ✅ Rotate static client credentials at least every 90 days.

## CI/CD — Required Stages

1. **Validate** — `fmt -check`, `validate`, `tflint`.
2. **Scan** — `trivy config`, `checkov`.
3. **Plan** — `terraform plan -out=tfplan`, save artifact, post to PR.
4. **Apply** — `terraform apply tfplan` (the **reviewed** artifact, not a re-plan).
5. **Activate** — included via `<product>_activation_status` in the same apply (ZIA / ZTC).

❌ Re-running `plan` inside the apply job.
❌ Manual console activation in production CI.
✅ Plan artifact retained for the duration required by your audit regime.

## Naming — Rule of Thumb

- ❌ `resource "zpa_application_segment" "this"` (every team uses `this` → no info).
- ❌ `resource "zpa_application_segment" "main"` (same problem).
- ✅ `resource "zpa_application_segment" "crm_finance"` (names the **intent**).
- ✅ Reserve `"this"` for genuine singletons (`zia_activation_status.this`).
- ✅ Prefix variables with context: `zpa_app_connector_group_id`, not `id`.

## Files Layout

```text
my-zscaler-config/
├── main.tf           # Primary resources
├── variables.tf      # Typed inputs with descriptions
├── outputs.tf        # Outputs
├── versions.tf       # required_version + required_providers
├── providers.tf      # Provider blocks (root only — never in reusable modules)
└── README.md         # Usage + input/output table
```

❌ Reusable modules with `provider` blocks. Providers are configured by the root.
✅ Reusable modules expose typed variables; root composes them.

## Testing — Minimum Bar

| Risk tier         | Test bar                                                                                              |
| ----------------- | ----------------------------------------------------------------------------------------------------- |
| Doc-only PR       | `fmt -check`.                                                                                          |
| Module change     | Static checks + `terraform test` (plan + mock).                                                       |
| New resource      | Above + `terraform test` (apply against sandbox tenant) + manual sandbox verification.                |
| Prod change       | Above + reviewed plan artifact + named approver + post-deploy verification.                           |

❌ `mock_provider` tests claiming "API behavior is verified" — mocks don't catch API contract bugs.
✅ Pair mock tests with sandbox-tenant integration on merge to main.

## Common Errors — Fast Diagnose

| Error message                                                  | Likely cause                                                                                  | Where to look                                                |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `401 unauthorized` from any provider                            | Auth mode mismatch; mixed `ZSCALER_*` + `<product>_*` env vars                                  | provider skill → auth-and-providers.md                       |
| `400 DUPLICATE_ITEM` on create                                  | Name collision with predefined or pre-existing object                                          | provider skill → troubleshooting.md                          |
| Apply succeeds but Zscaler console shows no change (ZIA/ZTC)    | Forgot `<product>_activation_status`                                                          | provider skill → activation.md                               |
| Drift on every plan after a `for_each` add                      | `count` over a list (use `for_each` over a map)                                                | best-practices → quick-reference (this file)                 |
| `RESOURCE_IN_USE` on destroy (ZPA)                              | Detach references first (segment groups, server groups)                                        | zpa-skill → troubleshooting.md                               |
| `'AUC' is not a valid ISO-3166 Alpha-2 country code` (ZIA)      | Use `AU` not `AUC`; `country` field expects ISO Alpha-2                                        | zia-skill → troubleshooting.md                               |

## Where to Route Questions

| Asking about…                                              | Go to                                                       |
| ---------------------------------------------------------- | ----------------------------------------------------------- |
| ZPA resource attributes, policy rules, microtenants        | `zpa-skill`                                                 |
| ZIA resource attributes, rule ordering, activation         | `zia-skill`                                                 |
| ZTC resource attributes, cloud-orchestrated objects        | `ztc-skill`                                                 |
| ZCC resource attributes, singleton lifecycle, env-var trap | `zcc-skill`                                                 |
| State organization, blast radius, microtenant strategy     | `best-practices-skill` → state-management.md                |
| CI/CD pipeline shape, OIDC, activation in CI               | `best-practices-skill` → ci-cd-zscaler.md                   |
| Secret handling, scanning, compliance                      | `best-practices-skill` → security-and-compliance.md         |
| Testing strategy, sandbox tenants, mock providers          | `best-practices-skill` → testing-and-validation.md          |
| "Is this allowed?" / "DO/DON'T for X"                      | This file                                                   |
