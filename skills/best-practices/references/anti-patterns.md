# Anti-Patterns — Zscaler Terraform

Recurring footguns enumerated. Each entry shows the bad pattern and the fix. For depth on a category, follow the linked reference.

## Quick Index

| Anti-pattern                                                | Fix                                                          | See                                              |
| ----------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------ |
| Credentials in HCL or `.tfvars`                             | Env vars in CI; `*_wo` on 1.11+                              | [Security](security-and-compliance.md)           |
| Local backend in production                                  | Remote backend with native locking                            | [State](state-management.md)                     |
| `provider {}` block in a reusable module                     | Provider in root module only                                  | [Module Patterns](module-patterns.md)            |
| Missing `version` constraint on a provider                   | `version = "~> 4.0"` (pessimistic)                           | [Versioning](versioning.md)                      |
| Exact pin (`= 4.0.3`)                                        | `~> 4.0` for minor+patch, `~> 4.0.0` for patch-only          | [Versioning](versioning.md)                      |
| Monolithic `main.tf` (1000+ lines)                          | Split per resource family (`segment_group.tf`, etc.)         | [Module Patterns](module-patterns.md)            |
| Mixed providers in one module                                | One module per provider                                      | [Module Patterns](module-patterns.md)            |
| Copy-paste duplicated resource blocks                        | `for_each` over a map of inputs                              | [Coding Practices](coding-practices.md)          |
| `type = any` for structured data                             | `object({...})` with `optional()`                            | [Variables](variables-and-outputs.md)            |
| Variables with no `validation {}`                            | Add enum/range/regex validation                              | [Variables](variables-and-outputs.md)            |
| Parallel lists (`server_names` + `server_addresses`)         | One `map(object({...}))`                                     | [Variables](variables-and-outputs.md)            |
| Output the entire resource                                   | Selective, named outputs                                     | [Variables](variables-and-outputs.md)            |
| `count = length(list)` for collections                       | `for_each = toset(list)` or map                              | [Coding Practices](coding-practices.md)          |
| Hardcoded resource IDs in HCL                                | `data "..." "this"` lookup                                   | [Coding Practices](coding-practices.md)          |
| Implicit dependencies via apply order                        | Reference attributes (or `depends_on` if no reference exists) | [Coding Practices](coding-practices.md)          |
| Module exposes 30 individual variables                       | One `object({...})` config variable                          | [Module Patterns](module-patterns.md)            |
| God module that does every Zscaler product                   | Per-product modules, composed in root                        | [Module Patterns](module-patterns.md)            |
| Circular module dependencies                                 | Restructure via shared module                                | [Module Patterns](module-patterns.md)            |
| Apply ZIA/ZTC resources without activation                   | Include `<product>_activation_status` in the same state      | [CI/CD](ci-cd-zscaler.md)                        |
| Mixed v1 and v2 ZPA policy resources                         | Use `zpa_policy_*_v2` consistently                            | `zpa-skill` → policy-rules.md                    |
| Full parallelism on rate-limited tenants                     | `terraform apply -parallelism=1` for bulk operations         | (here)                                           |
| Hardcoded cross-provider IDs                                 | Data source lookup with `provider =` alias                   | (here)                                           |
| Examples that don't `terraform plan` cleanly                 | Complete, runnable examples; CI validates                    | [Module Patterns](module-patterns.md)            |
| Variables with no `description`                              | Always describe purpose + allowed values                     | [Variables](variables-and-outputs.md)            |
| `terraform state rm` against a Zscaler resource              | `removed {}` block (1.7+) or `apply -target=`                | [State](state-management.md)                     |
| One state for ZPA + ZIA + ZTC + ZCC                          | Per-product, per-environment, per-microtenant cohort         | [State](state-management.md)                     |
| Manual console activation in production CI                   | `<product>_activation_status` in the apply                   | [CI/CD](ci-cd-zscaler.md)                        |
| `terraform apply` re-running plan                            | Apply the **saved** plan artifact                             | [CI/CD](ci-cd-zscaler.md)                        |
| Mixing `ZSCALER_*` and `<product>_*` env vars in one job     | One auth namespace per job                                   | [CI/CD](ci-cd-zscaler.md)                        |

## Detail — The Non-Obvious Ones

### Full parallelism on rate-limited tenants

ZIA and ZTC tenants enforce per-tenant API rate limits. The default `terraform apply -parallelism=10` can throttle a bulk apply (e.g. importing 200 URL filtering rules) and produce intermittent 429s.

```bash
# For bulk imports/updates against a rate-limited tenant:
terraform apply -parallelism=1
```

Or pin the provider's parallelism (where supported):

```hcl
provider "zia" {
  parallelism = 1
}
```

❌ Default parallelism for the first big import.
✅ `-parallelism=1` for the import; default afterwards.

### Hardcoded cross-provider IDs

ZIA forwarding control rules reference ZPA server groups, ZPA app segments, etc. The IDs are tenant-specific and should never be inlined.

❌

```hcl
resource "zia_forwarding_control_zpa_gateway" "gw" {
  zpa_server_group {
    external_id = "72058304855457833"
    name        = "prod-webapp-servers"
  }
}
```

✅

```hcl
data "zpa_server_group" "existing" {
  provider = zpa
  name     = "prod-webapp-servers"
}

resource "zia_forwarding_control_zpa_gateway" "gw" {
  provider = zia

  zpa_server_group {
    external_id = data.zpa_server_group.existing.id
    name        = data.zpa_server_group.existing.name
  }
}
```

When the two providers are managed in different states, use [`terraform_remote_state`](state-management.md#cross-state-references) instead of the data source.

### "Just `terraform state rm` it" recovery

❌ `terraform state rm zpa_application_segment.crm` to "clean up" an inconsistency.

The state is now consistent **but the API object is orphaned**. The next plan will re-create it (DUPLICATE_ITEM error, because the original still exists in the tenant). Recovery requires either re-importing the orphan or deleting it via the console + applying again.

✅ Use `removed {}` (Terraform 1.7+) to stop managing it without deleting:

```hcl
removed {
  from = zpa_application_segment.crm
  lifecycle {
    destroy = false
  }
}
```

✅ Or `terraform apply -target=` after removing the resource block from HCL — Terraform deletes via the API and updates state.

### Apply succeeds but ZIA/ZTC console shows no change

❌ A ZIA URL filtering rule applied successfully via Terraform, but the rule isn't blocking traffic.

The change is **draft** in the tenant until activation. ZIA and ZTC require an activation push.

✅ Include `<product>_activation_status` in the same state, with `depends_on` covering every resource that must activate together:

```hcl
resource "zia_activation_status" "this" {
  status = "ACTIVE"

  depends_on = [
    zia_url_filtering_rules.this,
    zia_firewall_filtering_rule.this,
  ]
}
```

See [CI/CD: Activation Stage](ci-cd-zscaler.md#activation-as-a-pipeline-stage).

### Mixing v1 and v2 ZPA policy resources

ZPA introduced `zpa_policy_*_v2` resources with a different operand structure. Mixing v1 and v2 in the same configuration leads to inconsistent rule shapes and confused readers.

❌ `zpa_policy_access_rule` (v1) and `zpa_policy_access_rule_v2` (v2) side-by-side.
✅ Use `zpa_policy_access_rule_v2` consistently for new configurations. Migrate v1 to v2 in a dedicated PR.

### Mixing `ZSCALER_*` and `<product>_*` env vars

The Zscaler providers detect auth mode based on `use_legacy_client` and which env vars are set. If both namespaces are populated in the same job, the provider picks one path and **silently ignores the other**.

❌

```yaml
env:
  ZSCALER_CLIENT_ID:     ${{ secrets.ZSCALER_CLIENT_ID }}      # OneAPI
  ZSCALER_CLIENT_SECRET: ${{ secrets.ZSCALER_CLIENT_SECRET }}
  ZIA_API_KEY:           ${{ secrets.ZIA_API_KEY }}             # Legacy
  ZIA_USERNAME:          ${{ secrets.ZIA_USERNAME }}
  ZIA_PASSWORD:          ${{ secrets.ZIA_PASSWORD }}
```

✅ One auth path per job. If you need to migrate, run two parallel CI jobs (one per auth path) until the cutover.

### `dynamic` block where the block is always present once

❌

```hcl
resource "zpa_server_group" "this" {
  name = "example"

  dynamic "app_connector_groups" {
    for_each = [var.connector_group_id]   # Always exactly one
    content {
      id = [app_connector_groups.value]
    }
  }
}
```

✅

```hcl
resource "zpa_server_group" "this" {
  name = "example"

  app_connector_groups {
    id = [var.connector_group_id]
  }
}
```

`dynamic` adds reading cost. Only use it when the block count actually varies.

### Outdated documentation

Inline examples in module READMEs go stale fast. Generate them.

```bash
brew install terraform-docs
terraform-docs markdown table . > README.md
```

Wire it into pre-commit so the README is regenerated on every change to `variables.tf` / `outputs.tf`. Audit at least quarterly.

## Related

- [Module Patterns](module-patterns.md) — composition discipline.
- [Coding Practices](coding-practices.md) — positive patterns.
- [Security & Compliance](security-and-compliance.md) — secret hygiene.
- [CI/CD for Zscaler](ci-cd-zscaler.md) — pipeline shape and activation.
- [State Management](state-management.md) — never-`state rm`, blast radius.
- [Quick Reference](quick-reference.md) — fast-lookup DO/DON'T.
