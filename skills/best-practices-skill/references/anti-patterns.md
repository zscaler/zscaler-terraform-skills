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
| Unrelated products bundled in one module                     | One purpose per module; two providers only when one feature spans both | [Module Patterns](module-patterns.md)   |
| Copy-paste duplicated resource blocks                        | `for_each` over a map of inputs                              | [Coding Practices](coding-practices.md)          |
| `type = any` for structured data                             | `object({...})` with `optional()`                            | [Variables](variables-and-outputs.md)            |
| Variables with no `validation {}`                            | Add enum/range/regex validation                              | [Variables](variables-and-outputs.md)            |
| Parallel lists (`server_names` + `server_addresses`)         | One `map(object({...}))`                                     | [Variables](variables-and-outputs.md)            |
| Output the entire resource                                   | Selective, named outputs                                     | [Variables](variables-and-outputs.md)            |
| `count = length(list)` for collections                       | `for_each = toset(list)` or map                              | [Coding Practices](coding-practices.md)          |
| Hardcoded resource IDs in HCL                                | `data "..." "this"` lookup                                   | [Coding Practices](coding-practices.md)          |
| Implicit dependencies via apply order                        | Reference attributes (or `depends_on` if no reference exists) | [Coding Practices](coding-practices.md)          |
| Module exposes 30 individual variables                       | One `object({...})` config variable                          | [Module Patterns](module-patterns.md)            |
| God module that does every Zscaler product                   | Single-purpose modules, composed in root                     | [Module Patterns](module-patterns.md)            |
| Hand-writing HCL for a tenant that already exists            | `zscaler-terraformer import --resources "zia"`               | [Import and Brownfield](import-and-brownfield.md) |
| Circular module dependencies                                 | Restructure via shared module                                | [Module Patterns](module-patterns.md)            |
| Apply ZIA/ZTC resources without activation                   | Run `ziaActivator` / `ztcActivator` once after apply          | [CI/CD](ci-cd-zscaler.md)                        |
| `ZIA_ACTIVATION=true` to activate during the apply           | Leave unset; activate once (endpoint allows 10/min, 40/hr)    | (here)                                           |
| Assuming a long apply holds a single ZIA session             | Raise `api_session_timeout` to 20; keep runs short            | (here)                                           |
| Concurrent ZIA/ZTC applies from several states to one tenant | Serialise `apply` on the tenant; plans stay parallel          | [State](state-management.md#concurrency-is-a-tenant-property-not-a-state-property) |
| Activating once per workspace / per state                    | One activation after the final apply                          | [CI/CD](ci-cd-zscaler.md#activation-as-a-pipeline-stage) |
| Mixed v1 and v2 ZPA policy resources                         | Use `zpa_policy_*_v2` consistently                            | `zpa-skill` → policy-rules.md                    |
| Lowering `-parallelism` to handle rate limits                | Leave it at the default; retries are automatic               | (here)                                           |
| Hardcoded cross-provider IDs                                 | Data source lookup with `provider =` alias                   | (here)                                           |
| Examples that don't `terraform plan` cleanly                 | Complete, runnable examples; CI validates                    | [Module Patterns](module-patterns.md)            |
| Variables with no `description`                              | Always describe purpose + allowed values                     | [Variables](variables-and-outputs.md)            |
| `terraform state rm` against a Zscaler resource              | `removed {}` block (1.7+) or `apply -target=`                | [State](state-management.md)                     |
| One state for ZPA + ZIA + ZTC + ZCC                          | Per-product, per-environment, per-microtenant cohort         | [State](state-management.md)                     |
| Manual console activation in production CI                   | Activator binary as a pipeline stage, or activation in HCL     | [CI/CD](ci-cd-zscaler.md)                        |
| `terraform apply` re-running plan                            | Apply the **saved** plan artifact                             | [CI/CD](ci-cd-zscaler.md)                        |
| Mixing `ZSCALER_*` and `<product>_*` env vars in one job     | One auth namespace per job                                   | [CI/CD](ci-cd-zscaler.md)                        |

## Detail — The Non-Obvious Ones

### Lowering `-parallelism` to handle rate limits

ZIA and ZTC tenants enforce per-endpoint API rate limits, and a bulk apply can produce intermittent 429s. This does **not** require any tuning: the provider honours the `Retry-After` header on a 429 and retries transparently, so a throttled request costs a short delay rather than a failed apply.

Reducing parallelism is actively harmful, for two reasons.

It cannot be scoped. `-parallelism` applies to the entire run — Terraform offers no per-endpoint, per-provider, or per-resource-type setting — so lowering it to accommodate one resource type also slows every other resource in the configuration, including anything a rule depends on.

It defeats rule batching. To place rules at their declared `order`, the ZIA and ZTC providers reconcile rule positions on a periodic cycle shared by every rule created concurrently. At `-parallelism=1` each rule waits out a full cycle alone instead of sharing one with its batch. A real customer deployment of roughly 360 firewall rules took over six hours at `-parallelism=1`; the same apply at the default completes in well under an hour.

```bash
# Correct — for bulk imports and everything else
terraform apply
```

❌ `-parallelism=1` (or any reduced value) for a bulk import.
❌ `provider "zia" { parallelism = 1 }` — this argument is deprecated and ignored; remove it.
✅ Terraform's default parallelism, always.

### Hardcoded cross-provider IDs

ZIA forwarding control rules reference ZPA server groups, ZPA app segments, etc. The IDs are tenant-specific and should never be inlined.

❌

```hcl
resource "zia_forwarding_control_zpa_gateway" "gw" {
  zpa_server_group {
    external_id = "99999999999999999"
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

The change is **draft** in the tenant until activation. ZIA and ZTC require an activation push. Activation is tenant-wide — one call publishes everything pending.

✅ Run the activator binary once as its own pipeline stage:

```yaml
- run: terraform apply -auto-approve tfplan
- run: ziaActivator      # ztcActivator for ZTC
```

✅ Or, for a single flat state that owns all of its resources, include `<product>_activation_status` with `depends_on` covering every resource that must activate together:

```hcl
resource "zia_activation_status" "this" {
  status = "ACTIVE"

  depends_on = [
    zia_url_filtering_rules.this,
    zia_firewall_filtering_rule.this,
  ]
}
```

❌ Don't rely on `depends_on` in module-based configurations — it can't be inferred, so any resource missing from the list may be applied after activation and left draft with no error.

See [CI/CD: Activation Stage](ci-cd-zscaler.md#activation-as-a-pipeline-stage).

### `ZIA_ACTIVATION=true` to activate during the apply

❌ Applies get progressively slower as the configuration grows, with no errors.

The variable makes the provider activate in-flight after every create, update, and delete. Activation is tenant-wide, so every call but the last is redundant — and the endpoint allows only **10 POST requests per minute and 40 per hour**. A few dozen resources exhaust the hourly budget inside a single apply, after which the run decelerates to the pace of the rate limit (rate-limited requests are retried automatically, so nothing fails).

✅ Leave the variable unset and activate once with the activator binary. Treat it as legacy; it may be removed in a future provider release.

### Assuming a long apply holds a single ZIA session

❌ "Changes activated before the apply finished", or "we never ran an activation step but it activated anyway".

Neither is a provider bug. ZIA activates pending changes **when a session ends**, including when it ends by reaching the API session timeout — 5 to 20 minutes, **default 5** ([docs](https://help.zscaler.com/zia/configuring-advanced-settings#session-timeout)). Any apply longer than that crosses the boundary, gets its pending changes activated mid-run, then re-authenticates and continues without error.

✅ Raise it to 20 — in the ZIA Admin Portal under **Administration > Advanced Settings** → **API Session Timeout Duration (In Minutes)**, or via `api_session_timeout` on `zia_advanced_settings` — and keep runs short by splitting large configurations across smaller states. The behaviour is native to the platform and cannot be overridden by the provider, so run duration is the real lever.

When triaging either report: check run duration against the configured timeout first, and confirm which field was changed — the *UI* session timeout sits directly above the API one on the same page and does not affect API sessions.

❌ Don't suggest this fix for **ZTC**. ZTC exposes no adjustable API session lifetime at all, in the provider or the tenant — short runs are the only mitigation there.

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
