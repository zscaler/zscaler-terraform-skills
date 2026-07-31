# Rationalization Table / Coverage Map

> **Purpose:** Map every known hallucination surface (LLM failure mode) to the baseline scenario that exercises it and the skill guard that must catch it. Tracks whether each surface is currently covered (`✅`), partially covered (`◐`), or open (`❌`).
>
> **Source:** Baseline scenarios in [`baseline-scenarios.md`](baseline-scenarios.md) and the per-skill `references/*.md` guards.

This document is a **contract**: every PR that adds a new hallucination surface (e.g. a new "agent defaults to X" failure mode the team has observed) **must** add a row here and a paired baseline scenario.

## How to Use This Document

### During testing

1. Run a baseline scenario from `baseline-scenarios.md` in a fresh agent session.
2. If the response fails to produce a "Must include" element or emits a "Must avoid" element, locate the corresponding row below.
3. If the row is `✅` but the scenario failed, **downgrade to `◐`** and note why in the PR.
4. If the row is `◐` or `❌`, follow the guard path to the referenced file and tighten the language.

### During PR review

1. Any PR that adds a diagnose row in a `SKILL.md` must also add (a) a baseline scenario and (b) a row here.
2. Any PR that changes content under a `(file + anchor)` listed in the "Target guard" column must re-run the linked baseline scenario.

### Legend

| Status | Meaning                                                                                       |
| ------ | --------------------------------------------------------------------------------------------- |
| ✅     | Dedicated guard exists in the skill, paired with at least one baseline scenario, passes.       |
| ◐     | Partial — guard exists but is weak, untested, or shares real estate with unrelated content.    |
| ❌     | No guard yet — known gap; priority for the next PR.                                            |

---

## Coverage Matrix

| #  | Hallucination surface                                                                                     | Baseline scenario  | Target guard (file + anchor)                                                                                                          | Coverage |
| -- | ---------------------------------------------------------------------------------------------------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| 1  | Emits `tcp_port_ranges = ["443"]` (single value) instead of paired `["443", "443"]`                        | S-ZPA-01           | `zpa-skill/references/resource-catalog.md` — segment_group recipe                                                                     | ✅       |
| 2  | Wires `server_groups = [...]` as a flat list instead of nested block                                       | S-ZPA-01           | `zpa-skill/references/resource-catalog.md` — segment_group recipe                                                                     | ✅       |
| 3  | Hardcodes `policy_set_id` instead of `data "zpa_policy_type"`                                               | S-ZPA-01           | `zpa-skill/SKILL.md` Policy Rules + `references/policy-rules.md#policy-type-map`                                                       | ✅       |
| 4  | SCIM_GROUP operand with `lhs = "id"` (wrong; must be the IdP ID)                                            | S-ZPA-01           | `zpa-skill/references/policy-rules.md#operand-reference`                                                                              | ✅       |
| 5  | POSTURE operand `rhs = false` (boolean) instead of `"false"` (string)                                       | S-ZPA-02           | `zpa-skill/references/policy-rules.md#operand-reference`                                                                              | ✅       |
| 6  | Recommends `terraform state rm` or `lifecycle { ignore_changes }` for a drift bug                          | S-ZPA-03           | `zpa-skill/references/troubleshooting.md#drift-causes`                                                                                | ✅       |
| 7  | Recommends `terraform state rm` to "force" past `RESOURCE_IN_USE`                                           | S-ZPA-04           | `zpa-skill/references/troubleshooting.md#detach-before-delete`                                                                        | ✅       |
| 8  | Recommends `terraform import` as first answer to microtenant-404                                            | S-ZPA-05           | `zpa-skill/references/troubleshooting.md#microtenant-not-found`                                                                       | ✅       |
| 9  | Puts `client_secret` in `variables.tf` defaults                                                             | S-ZPA-06 / S-ZIA-05 | `zpa-skill/SKILL.md` Credential Hygiene + `zia-skill/SKILL.md` Credential Hygiene                                                     | ✅       |
| 10 | Emits `zia_url_filtering_rule` (singular) instead of `zia_url_filtering_rules` (plural)                    | S-ZIA-01           | `zia-skill/SKILL.md` Naming Conventions + `references/resource-catalog.md`                                                            | ✅       |
| 11 | `state = true` (boolean) instead of `state = "ENABLED"` (string)                                            | S-ZIA-01 / S-ZTC-01 | `zia-skill/references/rules-and-ordering.md` + `ztc-skill/references/rules-and-ordering.md`                                           | ✅       |
| 12 | `departments = [data.x.id]` (flat list) instead of `departments { id = [data.x.id] }` (nested block)        | S-ZIA-01           | `zia-skill/references/resource-catalog.md` — url filtering rule shape                                                                  | ✅       |
| 13 | Hardcodes department / location / SCIM group IDs                                                            | S-ZIA-01 / S-ZTC-01 | `zia-skill/SKILL.md` + `ztc-skill/SKILL.md` + `best-practices-skill/references/anti-patterns.md#hardcoded-cross-provider-ids`         | ✅       |
| 14 | `order = 0` or negative                                                                                     | S-ZIA-01 / S-ZTC-01 | `zia-skill/references/rules-and-ordering.md` + `ztc-skill/references/rules-and-ordering.md`                                           | ✅       |
| 15 | Apply succeeds but tenant shows no change — forgot `zia_activation_status` / `ztc_activation_status`        | S-ZIA-02 / S-ZTC-02 | `zia-skill/references/activation.md` + `ztc-skill/references/rules-and-ordering.md#activation`                                        | ✅       |
| 16 | Emits `zia_activation` instead of `zia_activation_status`                                                   | S-ZIA-01 / S-ZIA-02 | `zia-skill/references/activation.md`                                                                                                  | ✅       |
| 17 | Multiple `<product>_activation_status` resources in one state                                               | S-ZIA-02 / S-ZTC-02 | `zia-skill/references/activation.md`                                                                                                  | ✅       |
| 18 | Predefined rule reorder fails — does not recommend provider upgrade                                         | S-ZIA-03           | `zia-skill/references/rules-and-ordering.md` + `zia-skill/references/recent-provider-changes.md`                                       | ✅       |
| 19 | `zia_location_management.country = "US"` (ISO Alpha-2) instead of `"UNITED_STATES"` (enum name)             | S-ZIA-04           | `zia-skill/references/troubleshooting.md#country-code--locale-validation`                                                              | ✅       |
| 20 | Treats cloud-orchestrated location as a `resource "ztc_location_management"` instead of `data` block         | S-ZTC-01           | `ztc-skill/references/resource-catalog.md#cloud-orchestrated-objects`                                                                  | ✅       |
| 21 | Suggests `depends_on` chains for the ZTC multi-rule-type reorder race (race is inside the provider)        | S-ZTC-03           | `ztc-skill/references/rules-and-ordering.md#multi-rule-type-reorder-race-fixed-in-v017--v018`                                          | ✅       |
| 22 | Includes `ZPA_CUSTOMER_ID` for ZIA / ZTC / ZCC auth (not a valid env var for those)                         | S-ZIA-05 / S-ZTC-04 | `zia-skill/SKILL.md` Credential Hygiene + `ztc-skill/SKILL.md` Credential Hygiene + `best-practices-skill/references/cross-product-equivalents.md#auth-env-var-matrix` | ✅       |
| 23 | Sets `guid` in ZCC HCL (read-only)                                                                          | S-ZCC-01           | `zcc-skill/references/resource-catalog.md`                                                                                            | ✅       |
| 24 | Adds `state = "ENABLED"` or `order` to a ZCC resource (no such fields)                                      | S-ZCC-01           | `zcc-skill/references/resource-catalog.md`                                                                                            | ✅       |
| 25 | Adds `zcc_activation_status` (no such resource in ZCC)                                                      | S-ZCC-01           | `zcc-skill/SKILL.md` Response Contract + `best-practices-skill/references/cross-product-equivalents.md#activation-lifecycle`           | ✅       |
| 26 | Files a "bug" against the ZCC singleton state-only delete                                                   | S-ZCC-02           | `zcc-skill/references/troubleshooting.md#singleton--existing-only-lifecycle`                                                          | ✅       |
| 27 | Suggests one "correct" value for ZCC `condition_type` (both `0` and `1` are valid)                          | S-ZCC-03           | `zcc-skill/references/troubleshooting.md#schema-quirks`                                                                               | ✅       |
| 28 | Tells user to set both `ZSCALER_*` and `ZCC_*` env vars "to be safe"                                        | S-ZCC-04           | `zcc-skill/references/auth-and-providers.md#the-env-var-trap`                                                                         | ✅       |
| 29 | **Defaults to AWS S3 backend when the user said Azure / GCP / Terraform Cloud**                              | S-BP-01            | `best-practices-skill/SKILL.md` Diagnose row "Defaults-to-S3" + `references/state-management.md#backend-choice--per-host-cloud`        | ✅       |
| 30 | **Defaults to OneAPI provider block when the user said pre-Zidentity legacy tenant** (note: a FedRAMP cloud alone no longer implies legacy — ZIA `v4.7.25`+ and ZPA `v4.4.6`+ support it over OneAPI) | S-BP-02            | `best-practices-skill/SKILL.md` Diagnose row "Defaults-to-OneAPI" + `references/cross-product-equivalents.md#auth-env-var-matrix`      | ✅       |
| 31 | **Conflates state-backend auth with Zscaler API auth in one env-var step on GCP / Azure / AWS**             | S-BP-03            | `best-practices-skill/references/ci-cd-zscaler.md#state-backend-auth-from-ci-cross-cloud`                                              | ✅       |
| 32 | **Defaults to ZPA patterns when the user mentioned ZIA / ZTC / ZCC; emits `segment_group` for a ZIA prompt** | S-BP-04            | `best-practices-skill/SKILL.md` Diagnose row "Defaults-to-ZPA" + `references/cross-product-equivalents.md#resource-concept-map`        | ✅       |
| 33 | Hardcodes a ZPA server-group / app-segment ID into a ZIA `zia_forwarding_control_zpa_gateway`               | S-BP-04            | `best-practices-skill/references/cross-product-equivalents.md#cross-product-composition-recipes` + `references/anti-patterns.md#hardcoded-cross-provider-ids` | ✅       |
| 34 | Defaults to parent-tenant scope on a microtenant tenant (omits `microtenant_id` on resources + data sources) | S-ZPA-05           | `zpa-skill/SKILL.md` Microtenants + `best-practices-skill/SKILL.md` Diagnose row "Defaults-to-parent-tenant"                            | ✅       |
| 35 | Recommends mixing `ZSCALER_*` and `<product>_*` env vars in one CI job                                      | S-ZIA-05 / S-ZTC-04 / S-ZCC-04 | `best-practices-skill/references/cross-product-equivalents.md#auth-env-var-matrix` + `references/anti-patterns.md#mixing-zscaler_-and-product_-env-vars` | ✅       |

### Coverage Summary

- **Total surfaces tracked:** 35
- **Covered (`✅`):** 35
- **Partial (`◐`):** 0
- **Open gaps (`❌`):** 0

### Priority Gaps (`❌` rows)

None as of this PR.

---

## How to Add a New Surface (PR Checklist)

When you observe a new hallucination — e.g. "the agent kept emitting `zia_microtenant_id` because the user mentioned ZPA microtenants earlier in the prompt" — add the row before merging the fix:

1. **Append a row** with a fresh number to the matrix above. Pick `❌` if no guard exists yet.
2. **Add a baseline scenario** to `baseline-scenarios.md` with the prompt that triggered the failure, the "Must include", and the "Must avoid" lists.
3. **Strengthen the guard** in the relevant `SKILL.md` or `references/*.md`. Promote the row to `✅` once the scenario passes.
4. **Re-run** every other scenario whose `Target guard` column points to the same file — the change may have broken adjacent guards.

---

## Related

- [`baseline-scenarios.md`](baseline-scenarios.md) — the actual prompts and expected behaviour.
- [`../CLAUDE.md`](../CLAUDE.md) — authoring rules for contributors.
- Per-skill `references/*.md` files — the guards themselves.
