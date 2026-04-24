# ZTC — Rules & Ordering

ZTC traffic-forwarding rules share the same ordering semantics as ZIA, plus a known reorder race condition fixed in v0.1.7/v0.1.8 that affects multi-rule-type deployments.

## Affected Resources

These all share the same rule-ordering rules:

`ztc_traffic_forwarding_rule`, `ztc_traffic_forwarding_dns_rule`, `ztc_traffic_forwarding_log_rule`.

## The Three Hard Rules

| Rule                          | What                                                                                              | Why                                                                                       |
| ----------------------------- | ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| **`order` must be `>= 1`**    | Validation rejects `0` and negatives at plan time.                                                 | Older provider releases accepted `order = -1`, which the API stored as `0` — corrupting the rule. |
| **Orders must be contiguous** | After deleting a rule at `order = 5`, decrement every order > 5 in HCL to stay contiguous.         | The API silently renumbers gaps, which makes Terraform see drift on every subsequent plan. |
| **Use one Terraform config per rule type per tenant** | Splitting rules across configs makes ordering impossible to reason about.                  | The reorder mechanism is tenant-wide and can race across configs.                          |

## `rank` vs `order`

| Field   | Effect                                                                                  |
| ------- | --------------------------------------------------------------------------------------- |
| `order` | Position within the rule type's list. Lower number = higher priority. Must be ≥1.       |
| `rank`  | Tie-breaker / processing weight within the same `order`. Default `7`. Higher = earlier. |

In practice you rarely need to change `rank` from `7`. Always use distinct `order` values for distinct rules of the same type.

## Multi-Rule-Type Reorder Race (Fixed in v0.1.7 / v0.1.8)

If your apply touches **multiple rule types** at once (e.g. both `ztc_traffic_forwarding_rule` and `ztc_traffic_forwarding_dns_rule`), older provider versions had a race where the reorder timer could fire before all rules were registered, causing wrong final orders.

**Fix:** pin to `~> 0.1.8` or later. Provider v0.1.7 added an async reorder goroutine with automatic re-run for late-arriving rules; v0.1.8 added the `UpdateContext` deferral so `ReadContext` doesn't store stale orders.

❌ Do not work around the race with `depends_on` chains across rule types — they don't help; the reorder happens inside the provider, not Terraform's graph.
✅ Upgrade to v0.1.8+.

## Composing a Multi-Rule Configuration

```hcl
locals {
  base_order = 10  # leave 1-9 for any hand-managed predefined rules
}

resource "ztc_traffic_forwarding_rule" "direct_to_branch" {
  name           = "DIRECT to branch"
  order          = local.base_order + 0
  state          = "ENABLED"
  type           = "EC_RDR"
  forward_method = "DIRECT"
  # ...
}

resource "ztc_traffic_forwarding_rule" "zia_for_internet" {
  name           = "ZIA for Internet"
  order          = local.base_order + 1
  state          = "ENABLED"
  type           = "EC_RDR"
  forward_method = "ZIA"
  # ...
}
```

Patterns:

- ✅ Pin a `local.base_order` to leave room for hand-managed rules above it.
- ✅ Manage all rules of the same type in **one** Terraform configuration.
- ✅ Use `for_each` with a map keyed by rule purpose (`direct_to_branch`, not `rule_0`) so addresses stay stable.

## Deleting a Rule Mid-Sequence

If you want to delete the rule at `order = 12` and you have rules at 10, 11, 12, 13, 14:

1. **Remove the HCL** for the rule at order 12.
2. **Decrement orders** for rules previously at 13 and 14 — change them to 12 and 13 in HCL.
3. **Apply** in one shot.
4. **Activate**.

❌ Do not delete the rule and leave the gap (`10, 11, 13, 14`). The API may renumber it for you, and Terraform sees drift on every subsequent plan.

## Activation

ZTC changes are **draft** at the API level until activated.

### Decision Table — Pick the Activation Pattern

| Goal                                              | Use                                            | Tradeoff                                                                  |
| ------------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------- |
| Atomic per-apply activation in CI/CD              | `ztc_activation_status` resource in HCL        | If activation fails, draft changes need a manual or follow-up retry.      |
| Decoupled / scheduled activation                  | `ztcActivator` CLI out-of-band                 | Acceptable for nightly batch; harder to reason about per-PR effects.      |

Recommendation for production: **manage `ztc_activation_status` in HCL**.

### Canonical Pattern

```hcl
resource "ztc_traffic_forwarding_rule" "direct_to_branch" {
  name           = "DIRECT to branch"
  order          = 1
  state          = "ENABLED"
  type           = "EC_RDR"
  forward_method = "DIRECT"
  # ...
}

resource "ztc_forwarding_gateway" "zia_gw" {
  name           = "ZIA_GW01"
  type           = "ZIA"
  primary_type   = "AUTO"
  secondary_type = "AUTO"
  fail_closed    = true
}

resource "ztc_activation_status" "this" {
  status = "ACTIVE"

  depends_on = [
    ztc_traffic_forwarding_rule.direct_to_branch,
    ztc_forwarding_gateway.zia_gw,
  ]
}
```

Rules:

- ✅ One `ztc_activation_status` per Terraform configuration.
- ✅ List every config-affecting resource in `depends_on`.
- ✅ For multi-tenant configs, one `ztc_activation_status` per provider alias.
- ❌ Do not create multiple `ztc_activation_status` resources in the same state.

### `for_each` Helper for Big `depends_on`

```hcl
locals {
  ztc_resources = concat(
    [for r in values(ztc_traffic_forwarding_rule.by_vpc) : r],
    [for r in values(ztc_forwarding_gateway.by_region) : r],
  )
}

resource "ztc_activation_status" "this" {
  status     = "ACTIVE"
  depends_on = [local.ztc_resources]
}
```

## Common Errors

| Error                                                                       | Cause                                                                                       | Fix                                                                                              |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `expected order to be at least (1), got 0`                                  | `order = 0` or negative.                                                                    | Set `order >= 1`.                                                                                |
| Rule applied but not enforced                                               | No `ztc_activation_status` change.                                                          | Add or update `ztc_activation_status`.                                                           |
| `terraform plan` shows churn on `order` of unrelated rules                 | Non-contiguous orders.                                                                      | Re-number to contiguous in HCL.                                                                  |
| Rules created in correct order but API ends up with wrong final order      | Multi-rule-type reorder race (provider <0.1.8).                                              | Upgrade `zscaler/ztc` to `~> 0.1.8`.                                                             |
| `proxy_gateway` block churns drift on every plan                            | `name` not set on the nested block.                                                          | Always set both `id` and `name` on `proxy_gateway`, derive `name` from the resource attribute.   |
