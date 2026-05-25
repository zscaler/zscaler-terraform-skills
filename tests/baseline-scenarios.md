# Baseline Scenarios

Curated user prompts that the skills must handle correctly. Used as a regression check whenever any `SKILL.md` or `references/*.md` is changed.

For each scenario:

- **Trigger** — the user prompt verbatim.
- **Expected skill** — which `skills/<product>/SKILL.md` should activate.
- **Must include** — non-negotiable elements that must appear in the agent's response.
- **Must avoid** — known failure modes.

When you change content, **manually re-run** the affected scenarios in your IDE and confirm the response still meets the criteria. Update this file if a scenario's expected output changes intentionally.

---

## ZPA scenarios

### S-ZPA-01 — Application segment + server group + segment group

- **Trigger**: `"Create a ZPA application segment that exposes crm.example.com on TCP 443 to a SCIM group called Engineering, with a server group backed by one app connector group called US-East-1."`
- **Expected skill**: `zpa-skill`
- **Must include**:
  - `terraform { required_providers { zpa = { source = "zscaler/zpa", version = "~> 4.0" } } }`
  - `data "zpa_app_connector_group" "us_east_1"` (or equivalent name)
  - `zpa_segment_group`, `zpa_server_group`, `zpa_application_segment`, `zpa_application_server`
  - `tcp_port_ranges = ["443", "443"]` (paired range, NOT `["443"]`)
  - `server_groups { id = [...] }` as nested block
  - `data "zpa_idp_controller"` + `data "zpa_scim_groups"` + `zpa_policy_access_rule` with `policy_set_id = data.zpa_policy_type.access.id`
  - SCIM_GROUP operand with `lhs = data.zpa_idp_controller.<x>.id`, `idp_id = data.zpa_idp_controller.<x>.id`
  - Response Contract section at the end (assumptions, version floor, validation, rollback)
- **Must avoid**:
  - `tcp_port_ranges = ["443"]`
  - `server_groups = [zpa_server_group.x.id]` (wrong, must be nested block)
  - Hardcoded `policy_set_id`
  - SCIM_GROUP operand with `lhs = "id"`

### S-ZPA-02 — Posture-based deny

- **Trigger**: `"Add a ZPA access policy that denies access to all CRM apps when the CrowdStrike ZTA score is below 40."`
- **Expected skill**: `zpa-skill`
- **Must include**:
  - `data "zpa_posture_profile" "crwd_zta_40" { name = "CrowdStrike_ZPA_ZTA_40" }` (or similar name)
  - POSTURE operand with `lhs = data.zpa_posture_profile.<x>.posture_udid`, `rhs = "false"` (string, not boolean)
  - `action = "DENY"`
- **Must avoid**:
  - `rhs = false` (boolean instead of string)
  - `lhs = "id"` for POSTURE

### S-ZPA-03 — Drift on bool field

- **Trigger**: `"My ZPA application segment shows tcp_quick_ack_app drifting to false on every plan even though I never changed it. Why?"`
- **Expected skill**: `zpa-skill`
- **Must include**:
  - Diagnosis: `omitempty` bool / API does not return false values, `Computed: true` issue at provider level
  - Recommendation: upgrade `zscaler/zpa` to latest 4.x, or pin the value explicitly in HCL
  - Reference to `troubleshooting.md` debug-log capture
- **Must avoid**:
  - Recommending `terraform state rm` or `lifecycle { ignore_changes }` as the first answer

### S-ZPA-04 — Detach before delete

- **Trigger**: `"terraform destroy fails on my zpa_segment_group with RESOURCE_IN_USE. How do I delete it?"`
- **Expected skill**: `zpa-skill`
- **Must include**:
  - Cause: still referenced by a policy rule
  - Fix order: remove policy rule references first, apply, then destroy the segment group
  - `depends_on` pattern for single-apply teardown
- **Must avoid**:
  - Recommending `terraform state rm` to "force" the destroy

### S-ZPA-05 — Microtenant 404

- **Trigger**: `"I created zpa_segment_group via Terraform with microtenant_id, but on the next plan it tries to recreate the resource. The segment group is visible in the ZPA console."`
- **Expected skill**: `zpa-skill`
- **Must include**:
  - Diagnosis: Read returning 404 because microtenant context isn't propagated
  - Checklist: `microtenant_id` in HCL, in state, in credential scope, on every data source
- **Must avoid**:
  - Recommending `terraform import` as the first answer
  - Recommending `lifecycle { ignore_changes }`

### S-ZPA-06 — Provider auth, OneAPI

- **Trigger**: `"Configure the ZPA provider for OneAPI authentication using environment variables in CI."`
- **Expected skill**: `zpa-skill`
- **Must include**:
  - Empty `provider "zpa" {}` block, env vars listed: `ZSCALER_CLIENT_ID`, `ZSCALER_CLIENT_SECRET`, `ZSCALER_VANITY_DOMAIN`, `ZSCALER_CLOUD`, `ZPA_CUSTOMER_ID`
  - Note that GOV / GOVUS are not OneAPI
- **Must avoid**:
  - Putting `client_secret` in `variables.tf` defaults
  - `sensitive = false` on credential variables

---

## ZIA scenarios

### S-ZIA-01 — URL filtering rule with order, scoped to a department

- **Trigger**: `"Add a ZIA URL filtering rule that blocks gambling categories for the Sales department, ordered after my existing predefined rules."`
- **Expected skill**: `zia-skill`
- **Must include**:
  - `terraform { required_providers { zia = { source = "zscaler/zia", version = "~> 4.0" } } }`
  - Resource name **`zia_url_filtering_rules`** (plural — not `zia_url_filtering_rule`)
  - `order >= 1` (positive integer; mention `validation.IntAtLeast(1)`)
  - `state = "ENABLED"` (string, not boolean)
  - `action = "BLOCK"`
  - `url_categories = ["GAMBLING"]` (or similar enum value)
  - `protocols = [...]` and `request_methods = [...]` (both required)
  - `departments { id = [data.zia_department_management.sales.id] }` (nested block, NOT flat list)
  - `data "zia_department_management" "sales" { name = "Sales" }`
  - Note about predefined rules + contiguous ordering (link to `rules-and-ordering.md`)
  - `zia_activation_status` resource with `depends_on = [...]` (NOT `zia_activation`)
  - Response Contract section
- **Must avoid**:
  - `zia_url_filtering_rule` (singular — wrong)
  - `zia_activation` (the resource is named `zia_activation_status`)
  - `state = true`
  - `departments = [data.zia_department_management.sales.id]` (flat list — wrong shape)
  - `order = 0` or negative
  - Hardcoded department ID

### S-ZIA-02 — Activation forgotten

- **Trigger**: `"My ZIA Terraform changes apply successfully but they don't take effect in the policy engine."`
- **Expected skill**: `zia-skill`
- **Must include**:
  - Diagnosis: ZIA changes are **draft** until activated
  - `zia_activation_status` resource with `status = "ACTIVE"` and `depends_on` on every policy resource
  - Recommendation to manage activation in HCL (atomic) vs manual
  - Reference to `references/activation.md`
- **Must avoid**:
  - `zia_activation` (wrong resource name)
  - Suggesting a manual GUI step as the only option
  - Multiple `zia_activation_status` resources in the same state

### S-ZIA-03 — Predefined-rule reorder fails with "Request body is invalid"

- **Trigger**: `"I'm reordering my ZIA firewall rules and one of the predefined rules is failing on the PUT with 'Request body is invalid'. What's wrong?"`
- **Expected skill**: `zia-skill`
- **Must include**:
  - Cause: provider <4.7.9 not stripping `Predefined` / `DefaultRule` / `AccessControl` on PUT
  - Fix: upgrade `zscaler/zia` ≥ 4.7.9
  - Reference to `rules-and-ordering.md` field-stripping table
- **Must avoid**:
  - Suggesting `terraform state rm` as the fix
  - Suggesting `lifecycle { ignore_changes }` as the first answer

### S-ZIA-04 — Country code confusion

- **Trigger**: `"My zia_location_management is failing with 'country must be a valid uppercase country name' but I set country = \"US\". What's wrong?"`
- **Expected skill**: `zia-skill`
- **Must include**:
  - Diagnosis: `zia_location_management.country` requires the **full uppercase enum name** (e.g. `UNITED_STATES`), not the ISO Alpha-2 code
  - Mention the contrast: firewall `dest_countries` uses ISO Alpha-2 (`US`)
  - Reference to `troubleshooting.md#country-code--locale-validation`
- **Must avoid**:
  - Suggesting the user file an issue (this is documented behavior)

### S-ZIA-05 — Provider auth, OneAPI on commercial cloud

- **Trigger**: `"Configure the ZIA provider for OneAPI authentication using environment variables in CI."`
- **Expected skill**: `zia-skill`
- **Must include**:
  - Empty `provider "zia" {}` block, env vars listed: `ZSCALER_CLIENT_ID`, `ZSCALER_CLIENT_SECRET`, `ZSCALER_VANITY_DOMAIN`, `ZSCALER_CLOUD`
  - Note that ZIA does **not** require `ZPA_CUSTOMER_ID` (unlike ZPA)
  - Note that GOV / `zscalerten` are not OneAPI — switch to legacy
- **Must avoid**:
  - Including `ZPA_CUSTOMER_ID` (not a ZIA env var)
  - Putting `client_secret` in `variables.tf` defaults
  - `sensitive = false` on credential variables

---

## ZTC scenarios

### S-ZTC-01 — Direct egress traffic forwarding rule for an AWS VPC

- **Trigger**: `"Create a ZTC traffic forwarding rule that sends traffic from my AWS VPC AWS-CAN-ca-central-1-vpc-A directly out to branch subnets 10.30.0.0/16."`
- **Expected skill**: `ztc-skill`
- **Must include**:
  - `terraform { required_providers { ztc = { source = "zscaler/ztc", version = "~> 0.1.8" } } }` (pre-1.0 pin tight)
  - `data "ztc_location_management" "aws_vpc"` (NOT a `resource` — VPC location is cloud-orchestrated)
  - `resource "ztc_traffic_forwarding_rule"` with `order >= 1`, `state = "ENABLED"` (string), `forward_method = "DIRECT"`, `type = "EC_RDR"`
  - `locations { id = [data.ztc_location_management.aws_vpc.id] }` as nested block
  - `dest_addresses = ["10.30.0.0/16"]`
  - `resource "ztc_activation_status"` with `depends_on = [...]` listing the rule
  - Response Contract section (assumptions, version floor, validation, rollback)
- **Must avoid**:
  - `resource "ztc_location_management"` for the AWS VPC location (it's cloud-orchestrated)
  - `state = true` (must be string `"ENABLED"`)
  - `order = 0` or negative
  - Hardcoded location ID

### S-ZTC-02 — Activation forgotten

- **Trigger**: `"My ZTC traffic forwarding rule applies successfully but it doesn't take effect."`
- **Expected skill**: `ztc-skill`
- **Must include**:
  - Diagnosis: ZTC changes are **draft** at the API level until activated
  - `ztc_activation_status` resource with `status = "ACTIVE"` and `depends_on` covering every config-affecting resource
  - Mention of the alternative `ztcActivator` CLI for out-of-band activation
  - Reference to `references/rules-and-ordering.md#activation`
- **Must avoid**:
  - Suggesting a manual GUI-only step as the only option
  - Multiple `ztc_activation_status` resources in the same state

### S-ZTC-03 — Wrong order after multi-rule-type apply

- **Trigger**: `"I deployed both ztc_traffic_forwarding_rule and ztc_traffic_forwarding_dns_rule in the same apply and the final order in the API is wrong even though my HCL has correct order values."`
- **Expected skill**: `ztc-skill`
- **Must include**:
  - Diagnosis: known multi-rule-type reorder race in `zscaler/ztc` <0.1.7
  - Fix: upgrade to `~> 0.1.8` (v0.1.7 added async reorder with re-run, v0.1.8 deferred ReadContext)
  - Reference to `references/rules-and-ordering.md#multi-rule-type-reorder-race-fixed-in-v017--v018`
- **Must avoid**:
  - Suggesting `depends_on` chains across rule types as the fix (the race is inside the provider, not Terraform's graph)
  - Suggesting `terraform state rm`

### S-ZTC-04 — Provider auth, OneAPI

- **Trigger**: `"Configure the ZTC provider for OneAPI authentication using environment variables in CI."`
- **Expected skill**: `ztc-skill`
- **Must include**:
  - Empty `provider "ztc" {}` block, env vars listed: `ZSCALER_CLIENT_ID`, `ZSCALER_CLIENT_SECRET`, `ZSCALER_VANITY_DOMAIN`, `ZSCALER_CLOUD`
  - Note that ZTC does **not** require `ZPA_CUSTOMER_ID`
  - Note that GOV / `zscalerten` are not OneAPI — switch to legacy with `ZTC_USERNAME`, `ZTC_PASSWORD`, `ZTC_API_KEY`, `ZTC_CLOUD`, `ZSCALER_USE_LEGACY_CLIENT=true`
- **Must avoid**:
  - Including `ZPA_CUSTOMER_ID`
  - Putting `client_secret` in `variables.tf` defaults
  - `sensitive = false` on credential variables

---

## ZCC scenarios

### S-ZCC-01 — Trusted network + forwarding profile

- **Trigger**: `"Create a ZCC trusted network for the corporate office on 10.0.0.0/8, then a forwarding profile that evaluates it."`
- **Expected skill**: `zcc-skill`
- **Must include**:
  - `terraform { required_providers { zcc = { source = "zscaler/zcc", version = "~> 0.1.0" } } }` (pre-1.0 pin tight)
  - `resource "zcc_trusted_network"` with `network_name`, `active = true`, `condition_type` (mention both `0` and `1` are valid), `trusted_subnets = "10.0.0.0/8"`
  - `resource "zcc_forwarding_profile"` with `evaluate_trusted_network = true` and `trusted_network_ids = [zcc_trusted_network.x.id]` (typed numbers, not strings)
  - Response Contract section
- **Must avoid**:
  - Setting `guid` in HCL (read-only)
  - Using `state = "ENABLED"` (no such field; ZCC has no string state enum)
  - Adding an `order` field (no rule-ordering concept in ZCC)
  - Adding a `zcc_activation_status` resource (no activation step in ZCC)

### S-ZCC-02 — Singleton destroy confusion

- **Trigger**: `"I ran terraform destroy on my zcc_failopen_policy and Terraform says it succeeded, but the policy is still active in the ZCC admin portal. Why?"`
- **Expected skill**: `zcc-skill`
- **Must include**:
  - Diagnosis: `zcc_failopen_policy` is a **singleton per company** — `delete` is implemented as a state-only operation by design (no API delete exists for the singleton)
  - Mention same pattern applies to `zcc_web_app_service` (existing-only)
  - Recommendation for safe handoff: `removed { from = ... lifecycle { destroy = false } }` (TF 1.7+) for standard CRUD resources; the singleton's safe `state rm` is one of the few legitimate uses
  - Reference to `references/troubleshooting.md#singleton--existing-only-lifecycle`
- **Must avoid**:
  - Suggesting this is a bug to file
  - Suggesting `terraform import` will somehow fix it

### S-ZCC-03 — `condition_type` flipping drift

- **Trigger**: `"My zcc_trusted_network shows condition_type drift between 0 and 1 on every plan."`
- **Expected skill**: `zcc-skill`
- **Must include**:
  - Diagnosis: API accepts both `0` and `1`; out-of-band changes (or initial mismatch) cause perpetual revert
  - Fix options: match API's value in HCL; omit `condition_type` to leave remote unchanged; or `lifecycle { ignore_changes = [condition_type] }` if out-of-band changes are expected
  - Reference to `references/troubleshooting.md#schema-quirks`
- **Must avoid**:
  - Suggesting `terraform state rm`
  - Asserting a single "correct" value (`0` or `1`) — both are valid

### S-ZCC-04 — Provider auth env-var trap

- **Trigger**: `"My ZCC provider keeps returning 401 even though I exported ZCC_CLIENT_ID and ZCC_CLIENT_SECRET. What's wrong?"`
- **Expected skill**: `zcc-skill`
- **Must include**:
  - Diagnosis: OneAPI uses `ZSCALER_*` env vars; legacy ZCC v2 uses `ZCC_*`. The provider defaults to OneAPI and silently ignores `ZCC_*` unless `use_legacy_client = true` (or `ZSCALER_USE_LEGACY_CLIENT=true`) is set.
  - Fix: pick one path — set `ZSCALER_*` for OneAPI, OR set `ZSCALER_USE_LEGACY_CLIENT=true` plus `ZCC_*` for legacy.
  - Reference to `references/auth-and-providers.md#the-env-var-trap`
- **Must avoid**:
  - Telling the user to set both namespaces "to be safe"
  - Suggesting they regenerate credentials before checking the env-var path

---

## Best Practices (cross-cutting) scenarios

These scenarios exercise the `best-practices-skill` and specifically catch defaults-bias hallucinations (host-cloud defaulting to AWS, auth defaulting to OneAPI, product defaulting to ZPA, conflated auth steps). They map to rows 29–33 in [`rationalization-table.md`](rationalization-table.md).

### S-BP-01 — Remote state for a Zscaler repo running on Azure

- **Trigger**: `"Set up Terraform remote state for our Zscaler-Terraform repo. We run all our infrastructure on Azure."`
- **Expected skill**: `best-practices-skill`
- **Must include**:
  - `backend "azurerm" { ... }` with `resource_group_name`, `storage_account_name`, `container_name`, `key`
  - Note that locking is automatic via blob lease — no companion lock table needed (unlike AWS S3 + DynamoDB pre-1.10)
  - Reference to `references/state-management.md#backend-choice--per-host-cloud`
  - Bootstrap-auth recommendation: federated credentials (not static service-principal secrets) when CI runs on GitHub / GitLab
  - Encryption-at-rest note: default-on; CMK optional
- **Must avoid**:
  - `backend "s3"` (the user said Azure)
  - Recommending a DynamoDB lock table (DynamoDB is AWS-only)
  - Defaulting to `use_lockfile = true` (S3 attribute) anywhere in the answer
  - Telling the user to migrate to AWS S3 "because the example uses S3"

### S-BP-02 — ZIA provider setup on a pre-Zidentity tenant

- **Trigger**: `"Help me configure the ZIA provider. We haven't moved to Zidentity yet — we're on the zscalerten cloud."`
- **Expected skill**: `zia-skill` (with `best-practices-skill` cross-reference)
- **Must include**:
  - `provider "zia" { use_legacy_client = true }`
  - Env vars: `ZIA_USERNAME`, `ZIA_PASSWORD`, `ZIA_API_KEY`, `ZIA_CLOUD=zscalerten`, `ZSCALER_USE_LEGACY_CLIENT=true`
  - Explicit note that `zscalerten` is a **legacy** cloud and is **not available on OneAPI**
  - Reference to `best-practices-skill/references/cross-product-equivalents.md#auth-env-var-matrix` or `zia-skill/references/auth-and-providers.md`
- **Must avoid**:
  - Emitting the OneAPI provider block (`ZSCALER_CLIENT_ID`, `ZSCALER_VANITY_DOMAIN`) anywhere as the primary recommendation
  - Suggesting the user migrate to Zidentity before answering the auth question (they explicitly said they haven't migrated)
  - Mixing `ZSCALER_*` and `ZIA_*` env vars in the example
  - `zscaler_cloud = "zscalerten"` (legacy uses `zia_cloud`, not `zscaler_cloud`)

### S-BP-03 — GitHub Actions OIDC for state on GCP + Zidentity for the provider

- **Trigger**: `"Set up GitHub Actions for our Zscaler-Terraform repo with keyless auth. State lives in GCS, and our tenant uses Zidentity OneAPI."`
- **Expected skill**: `best-practices-skill`
- **Must include**:
  - **Two distinct credential steps** in the workflow:
    1. `google-github-actions/auth@v2` with `workload_identity_provider` + `service_account` for GCS backend access
    2. Zidentity OneAPI credentials (`ZSCALER_CLIENT_ID`, `ZSCALER_CLIENT_SECRET`, `ZSCALER_VANITY_DOMAIN`) as env on the `terraform apply` step
  - `permissions: id-token: write` at workflow / job level
  - Reference to `best-practices-skill/references/ci-cd-zscaler.md#state-backend-auth-from-ci-cross-cloud`
  - Explicit note that GCP state-backend auth and Zidentity provider auth are **two different credential paths** kept in separate steps
- **Must avoid**:
  - Suggesting a long-lived GCP service-account key in `secrets.GOOGLE_APPLICATION_CREDENTIALS_JSON`
  - Mixing GCP and Zscaler env vars in a single `env:` block on one step
  - Defaulting to AWS OIDC (`aws-actions/configure-aws-credentials`) when the user said GCP
  - Using a single OIDC trust for both paths

### S-BP-04 — Forwarding ZIA traffic to a ZPA gateway

- **Trigger**: `"I want to forward traffic from my ZIA tenant to a ZPA application segment named CRM that lives in my ZPA tenant. How?"`
- **Expected skill**: `zia-skill` (with `best-practices-skill` cross-reference for the cross-product pattern)
- **Must include**:
  - Both `provider "zpa" {}` and `provider "zia" {}` configured (likely in the same root)
  - `data "zpa_server_group"` (or `data "zpa_application_segment"` + segment-group lookup) — **not** a hardcoded ID
  - `resource "zia_forwarding_control_zpa_gateway"` with `zpa_server_group { external_id = data.zpa_server_group.x.id, name = data.zpa_server_group.x.name }`
  - `zia_activation_status` with `depends_on = [zia_forwarding_control_zpa_gateway.x]`
  - Reference to `best-practices-skill/references/cross-product-equivalents.md#cross-product-composition-recipes`
  - Note about cross-state alternative (`terraform_remote_state`) if ZPA and ZIA are managed in different states
- **Must avoid**:
  - Hardcoding a ZPA server-group / app-segment ID (e.g. `external_id = "99999999999999999"`)
  - Inventing a `zia_segment_group` or `zia_zpa_app_segment` resource
  - Skipping `zia_activation_status` (this is a ZIA resource change — activation is mandatory)
  - Defaulting to ZPA-only patterns (the user explicitly wants the ZIA forwarding side)

---

## How to run a scenario manually

1. Open a fresh agent session in your IDE with the `zscaler-terraform-skills` plugin installed.
2. Paste the trigger verbatim.
3. Compare the response against the **Must include** and **Must avoid** lists.
4. If a criterion fails:
   - Open the affected `references/*.md` and tighten the relevant section.
   - Re-run.
   - If this surfaces a brand-new failure mode, add a row to [`rationalization-table.md`](rationalization-table.md) before merging the fix.
   - Document the change in `CHANGELOG.md` under the next version.
