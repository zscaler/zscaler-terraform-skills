# Versioning — Zscaler Terraform

Pinning Terraform, the Zscaler providers, and your own modules. Lockfile and upgrade discipline.

## Decision Table — Constraint Operator

| Operator        | Example          | Allows                                                                |
| --------------- | ---------------- | --------------------------------------------------------------------- |
| `>= X`          | `>= 1.9.0`       | Any version ≥ X. Open-ended; pulls breaking majors. Avoid in prod.   |
| `~> X.Y`        | `~> 4.0`         | Any 4.x. Allows minor + patch updates within major.                   |
| `~> X.Y.Z`      | `~> 4.0.0`       | Any 4.0.x. Allows patch only.                                          |
| `>= X, < Y`     | `>= 1.9, < 2.0`  | Bounded range. Use for `required_version` to allow Terraform updates. |
| `= X`           | `= 4.0.3`        | Exact pin. Don't — blocks security/bug-fix patches.                   |
| (none)          | —                | Always latest. Don't.                                                 |

## Hard Rules

- ❌ No version constraint at all (`source = "zscaler/zpa"` with no `version`).
- ❌ Exact pin (`version = "= 4.0.3"`) without an open exception (e.g. waiting on a known regression fix).
- ❌ Open-ended `>= X` for the provider in production root configs (one breaking major shipped without you noticing = day-ruined plan).
- ❌ `.terraform.lock.hcl` not committed.
- ❌ `terraform init -upgrade` mixed into a feature PR (lock-file changes deserve their own PR with a tested upgrade plan).
- ✅ Pessimistic constraints (`~>`) for every provider.
- ✅ Lockfile committed; upgrades are a dedicated PR.
- ✅ Bounded `required_version` (`>= 1.9, < 2.0`) so Terraform 2.x can't silently land.

## Recommended Pins

```hcl
terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    zpa = {
      source  = "zscaler/zpa"
      version = "~> 4.0"
    }
    zia = {
      source  = "zscaler/zia"
      version = "~> 4.0"
    }
    ztc = {
      source  = "zscaler/ztc"
      version = "~> 0.1"
    }
    zcc = {
      source  = "zscaler/zcc"
      version = "~> 0.1"
    }
  }
}
```

| Provider          | Recommended pin   | Notes                                                       |
| ----------------- | ----------------- | ----------------------------------------------------------- |
| `zscaler/zpa`     | `~> 4.0`          | OneAPI in `4.x`. Legacy v3 still supported.                  |
| `zscaler/zia`     | `~> 4.0`          | OneAPI in `4.x`. Legacy v3 still supported.                  |
| `zscaler/ztc`     | `~> 0.1`          | Pre-1.0; pin **exact patch** in prod (`~> 0.1.7`).            |
| `zscaler/zcc`     | `~> 0.1`          | Pre-1.0; pin **exact patch** in prod.                         |
| Terraform runtime | `>= 1.9, < 2.0`   | 1.6+ for `terraform test`; 1.10+ for `use_lockfile`; 1.11+ for `write_only` / `ephemeral`. |

For pre-1.0 providers (`ztc`, `zcc`), the SemVer guarantee doesn't hold — minor bumps can break. Pin tighter.

## The Lockfile (`.terraform.lock.hcl`)

- Commit it. Always.
- It locks the **resolved** provider versions and their checksums per platform.
- A teammate running `terraform init` gets exactly the providers you tested with.
- A CI runner gets the same.

```bash
# Update lockfile (intentional, dedicated PR)
terraform init -upgrade

# Refresh to add new platform checksums (when a teammate is on a different OS)
terraform providers lock -platform=darwin_arm64 -platform=linux_amd64

# Verify integrity (CI)
terraform init -backend=false -lockfile=readonly
```

❌ `terraform init -upgrade` bundled into a feature PR.
❌ Manually editing `.terraform.lock.hcl`.
✅ Lockfile changes ship in their own PR titled "Bump providers" with the new versions and a changelog summary.
✅ CI runs `init -lockfile=readonly` to catch drift.

## Module Versioning (SemVer)

Internal modules ship as Git tags or registry releases. Use SemVer:

```text
MAJOR.MINOR.PATCH
  │     │     └── Bug fixes, doc changes, internal refactors with no interface change
  │     └──────── New optional variables/outputs, new optional features, deprecation warnings
  └────────────── Removed/renamed variables or outputs, changed types, resource address renames
```

| Change                                                          | Bump   |
| --------------------------------------------------------------- | ------ |
| Bug fix without behavior change                                  | PATCH  |
| Doc-only update                                                  | PATCH  |
| Internal refactor, no public-interface change                    | PATCH  |
| New optional `variable` or `output`                              | MINOR  |
| New optional feature toggle                                      | MINOR  |
| Deprecation warning (with backward-compat shim)                  | MINOR  |
| Removed `variable` / `output`                                    | MAJOR  |
| Changed `variable` type or default value                         | MAJOR  |
| Renamed resource address (consumers' state breaks without `moved`) | MAJOR |
| Bumped `required_providers` floor to a major version             | MAJOR  |

Tag and reference:

```bash
git tag -a v1.2.0 -m "Add optional inspection profile support"
git push origin v1.2.0
```

```hcl
module "zpa_application" {
  source = "git::https://github.com/acme/zpa-modules.git//application?ref=v1.2.0"
}
```

Or via Terraform Registry:

```hcl
module "zpa_application" {
  source  = "acme/zpa-application/zscaler"
  version = "~> 1.2"
}
```

❌ Module sources without `?ref=` (Git) or `version =` (Registry) — pulls latest, breaks builds.
✅ All module references pinned. Updates are PRs with tests.

## `moved {}` Blocks (Renaming Without Breaking State)

Terraform 1.1+ ships `moved` blocks. Use them when you rename a module call, refactor resources between modules, or restructure addresses.

```hcl
# After renaming module "app" -> module "application"
moved {
  from = module.app.zpa_application_segment.this
  to   = module.application.zpa_application_segment.this
}
```

Without the `moved` block, downstream consumers' state files would treat it as a destroy + recreate.

❌ Renaming resource addresses without `moved` blocks.
✅ Ship `moved` blocks in the same release as the rename. Document as a MINOR bump.

## Upgrade Workflow

### Provider upgrade

```bash
# 1. Read the provider CHANGELOG (linked from the provider skill).
# 2. Update version constraint in versions.tf in a dedicated branch.
# 3. Refresh lockfile.
terraform init -upgrade

# 4. Plan against a non-prod state.
terraform plan

# 5. If the plan is clean, ship the PR. If not, investigate before merging.
```

❌ Upgrading provider in production state without first plan-ing in non-prod.
❌ Upgrading provider on a Friday afternoon.
✅ Upgrades happen in a dedicated PR with a clean non-prod plan as evidence.
✅ Use the per-provider `recent-provider-changes.md` reference page (auto-mined) as the changelog summary.

### OneAPI migration (Legacy v3 → OneAPI)

The Zscaler providers support both legacy v3 and OneAPI auth in `4.x`. Migration shape:

```hcl
# Before (legacy v3)
provider "zpa" {
  use_legacy_client = true
  # ZPA_CLIENT_ID, ZPA_CLIENT_SECRET, ZPA_CUSTOMER_ID, ZPA_CLOUD env vars
}

# After (OneAPI)
provider "zpa" {
  # ZSCALER_CLIENT_ID, ZSCALER_CLIENT_SECRET, ZSCALER_VANITY_DOMAIN, ZPA_CUSTOMER_ID env vars
  # ZSCALER_CLOUD only for non-prod (e.g. "beta")
}
```

Steps:

1. Stand up OneAPI (Zidentity) credentials in your tenant.
2. Run a non-prod state under both auth modes (sequentially) and confirm `terraform plan` is clean.
3. Switch the prod state's env vars + remove `use_legacy_client = true`.
4. Run `terraform plan` — should be a no-op.

❌ Mixing `ZSCALER_*` and `<product>_*` env vars in the same job during migration.
❌ Switching auth mode mid-CI run.
✅ Auth mode change is its own PR; CI confirms `plan` is empty.

GOV (`zscalergov`) and `zscalerten` clouds are still legacy-only — no OneAPI migration available.

### Terraform runtime upgrade

```bash
# 1. Read Terraform release notes (HashiCorp).
# 2. Update required_version bound (e.g. >= 1.9, < 2.0 -> >= 1.10, < 2.0).
# 3. Re-init.
terraform init

# 4. Plan against non-prod.
terraform plan
```

Tighten `required_version` lower-bound when you adopt features that need it (`use_lockfile` → 1.10+, `write_only` → 1.11+).

## Compatibility Matrix

| Terraform   | `zscaler/zpa` | `zscaler/zia` | `zscaler/ztc` | `zscaler/zcc` | Notes                                          |
| ----------- | ------------- | ------------- | ------------- | ------------- | ---------------------------------------------- |
| `~> 1.9`    | `~> 4.0`      | `~> 4.0`      | `~> 0.1`      | `~> 0.1`      | Recommended.                                   |
| `~> 1.6`    | `~> 4.0`      | `~> 4.0`      | `~> 0.1`      | `~> 0.1`      | Minimum for `terraform test`.                  |
| `~> 1.3`    | `4.x`         | `4.x`         | `0.x`         | `0.x`         | Minimum supported (`optional()` is stable).    |
| `< 1.3`     | —             | —             | —             | —             | Not supported.                                 |

## Related

- [CI/CD for Zscaler](ci-cd-zscaler.md) — lockfile checks in CI.
- [State Management](state-management.md) — backend version constraints.
- [Security & Compliance](security-and-compliance.md) — `write_only` / `ephemeral` (1.11+).
