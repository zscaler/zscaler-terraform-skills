# State Management — Zscaler Terraform

How to organize Terraform state when the providers are `zscaler/zpa`, `zscaler/zia`, `zscaler/ztc`, `zscaler/zcc`. The general Terraform rules apply (remote backend, locking, encryption); this reference covers the **Zscaler-specific** decisions.

## Decision Table — How Should I Split State?

| Goal                                                                                | Use                                                                                       | Tradeoff                                                                                              |
| ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Single small tenant, one team, < 50 resources total                                 | One state per environment (`prod/main.tfstate`)                                            | Simple. Any change blocks the whole team's plans.                                                     |
| Per-product ownership (network team owns ZPA, security team owns ZIA)               | One state per product, per environment (`prod/zpa/`, `prod/zia/`)                          | Decouples teams. Need cross-state outputs for shared IDs (e.g. SCIM groups).                          |
| Multi-microtenant org with autonomous teams per microtenant                         | One state per microtenant cohort (`prod/zpa/microtenant-a/`, `prod/zpa/microtenant-b/`)    | Highest parallelism. Need a registry mapping microtenants → state paths.                              |
| GOV + commercial in the same org                                                    | Separate state per cloud (`gov/zia/`, `commercial/zia/`)                                   | Mandatory — provider auth differs (`zscalergov` is legacy-only, GOV ≠ Zidentity OneAPI).              |
| Read-heavy "look up the IdP and SCIM groups" config                                  | Data-source-only state — no `resource` blocks, no activation                                | Skip activation entirely. Useful as an upstream reference state for other modules.                    |
| Cross-product composition (ZIA forwards to ZPA gateway)                              | Use `terraform_remote_state` to read outputs across states; do **not** merge states         | Adds a backend dependency. Worth it for the blast-radius isolation.                                   |

## Rules

- ❌ Never put all four products (ZPA + ZIA + ZTC + ZCC) in one state file. Different teams own them and lock contention will break workflows.
- ❌ Never put production and non-production in the same state.
- ❌ Never use `local` backend for any non-throwaway Zscaler config — apply lock contention only protects you with a remote backend.
- ✅ Split state on **policy ownership boundary**: who reviews and approves changes to this set of resources? That's a state.
- ✅ Use `terraform_remote_state` (or backend-specific equivalents) to read upstream IDs (SCIM group IDs from the identity state, app connector group IDs from the platform state).
- ✅ Per-microtenant state files when the microtenant has its own approval workflow; per-cohort if many microtenants share the same approver.

## Recommended Starter Layout

```text
infrastructure/
├── identity/                         # SCIM groups, IdP refs (read-mostly, data-source-only)
│   ├── prod/
│   └── nonprod/
├── zpa/
│   ├── prod/
│   │   ├── platform/                 # connector groups, segment groups (rare changes)
│   │   ├── microtenant-finance/      # finance team owns this
│   │   └── microtenant-sales/        # sales team owns this
│   └── nonprod/
├── zia/
│   ├── prod/
│   │   ├── policy-network/           # firewall + DNS + IPS (network team)
│   │   └── policy-content/           # URL filtering + DLP + sandbox (security team)
│   └── nonprod/
├── ztc/
│   └── ...
└── zcc/
    └── ...
```

**Why this shape:** identity comes first because every downstream state reads SCIM group IDs from it; ZPA splits on microtenant because that's the natural blast-radius boundary; ZIA splits on policy team ownership; ZTC/ZCC add their own splits if your tenancy/team shape demands it.

## Backend — Minimum Viable

S3 with native lockfile (Terraform 1.10+):

```hcl
terraform {
  required_version = "~> 1.9"
  backend "s3" {
    bucket       = "acme-terraform-state-prod"
    key          = "zscaler/zia/policy-network.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

For Terraform `< 1.10`: use `dynamodb_table = "terraform-state-lock"` instead of `use_lockfile`.

GCS / Azure Blob / Terraform Cloud / Terraform Enterprise / Spacelift all provide built-in locking — pick what your org already runs.

## Cross-State References

When your ZIA forwarding control rule needs a ZPA gateway ID that lives in a different state:

```hcl
data "terraform_remote_state" "zpa_platform" {
  backend = "s3"
  config = {
    bucket = "acme-terraform-state-prod"
    key    = "zscaler/zpa/platform.tfstate"
    region = "us-east-1"
  }
}

resource "zia_forwarding_control_zpa_gateway" "this" {
  name              = "zpa-gw"
  zpa_app_segments  = [data.terraform_remote_state.zpa_platform.outputs.crm_app_segment_id]
  # ...
}
```

❌ Do **not** merge the two states to avoid the cross-reference. The cost of a 30-line `data` block beats the cost of one team blocking another's plans every workday.

## Multi-Tenant / Multi-Microtenant State

For ZPA microtenants, two patterns:

**A. Microtenant in provider config — one state per microtenant.**

```hcl
provider "zpa" {
  microtenant_id = var.microtenant_id
}
```

Best when each microtenant has its own approver and changes ship independently.

**B. Microtenant in resource config — one state, multiple microtenants.**

```hcl
resource "zpa_application_segment" "this" {
  microtenant_id = var.microtenants["finance"].id
  # ...
}
```

Cleaner when one team manages all microtenants. Loses parallelism — every microtenant's changes contend for the same lock.

Pick A for autonomous teams. Pick B for centrally-administered platforms.

## Never `terraform state rm` a Zscaler Resource

Every Zscaler resource is backed by a real API object. `terraform state rm` removes the resource from state but leaves the API object orphaned. Recovery requires either re-importing the orphan or manually deleting it via the console / API.

Instead:

| Goal                                          | Do this                                                                                  |
| --------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Stop managing a resource without deleting it  | `removed { from = ... ; lifecycle { destroy = false } }` (Terraform 1.7+) — auditable.    |
| Delete a specific resource without disturbing siblings | `terraform apply -target=<resource>` after removing it from HCL.                          |
| Recover from accidental `state rm`            | `terraform import <addr> <id>` against the orphan, or delete via console + re-apply.      |

## Recovery — Stuck Lock

| Backend                | Unlock command                                                                           |
| ---------------------- | ---------------------------------------------------------------------------------------- |
| S3 + native lockfile   | `terraform force-unlock <lock-id>` (read lock-id from S3 lockfile object)                 |
| S3 + DynamoDB          | `terraform force-unlock <lock-id>` (read from DynamoDB item)                              |
| GCS                    | Delete the `.tflock` object in the bucket, then `terraform force-unlock`                  |
| Terraform Cloud        | Web UI → workspace → states → discard / cancel run                                        |

Always confirm no apply is **actually** running before force-unlocking — concurrent applies against Zscaler can produce DUPLICATE_ITEM errors and partial state.

## State File Sensitivity

State files contain:

- ✅ Resource IDs (segment IDs, rule IDs, location IDs).
- ✅ Configuration attributes (rule names, URL categories, network ranges).
- ✅ Computed attributes (gateway IPs, server-assigned IDs).
- ❌ The OneAPI `client_secret` is **not** persisted to state for any of the four providers.
- ❌ Legacy `password` / `api_key` are **not** persisted to state.
- ⚠️ Any value put into a `variable` whose value happens to be a credential (anti-pattern) **will** end up in state unless you use `write_only` (Terraform 1.11+).

Encrypt at rest (S3 + KMS, Azure Blob server-side encryption, GCS CMEK, Terraform Cloud workspace encryption). Restrict bucket / workspace access to the state's owner team.

## Disaster Recovery Checklist

- [ ] Backend has versioning enabled (S3 versioning, GCS object versioning, TFC built-in).
- [ ] Backend has a retention policy aligned with your audit requirements.
- [ ] You have tested `terraform state pull > backup.tfstate` from each state at least once.
- [ ] Your runbook documents how to restore a previous state version per backend.
- [ ] You have a sweep job / cleanup mechanism for any sandbox-tenant state that might accumulate.
