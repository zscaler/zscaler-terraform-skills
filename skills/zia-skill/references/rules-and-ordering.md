# ZIA — Rules & Ordering

ZIA rule resources are the highest-risk surface in the provider: a single bad `order` value can corrupt a rule that even the GUI can't repair. This page is the source of truth.

## Affected Resources

These all share the same rule-ordering rules and predefined-rule semantics:

`zia_url_filtering_rules`, `zia_firewall_filtering_rule`, `zia_firewall_dns_rules`, `zia_firewall_ips_rules`, `zia_dlp_web_rules`, `zia_ssl_inspection_rules`, `zia_cloud_app_control_rule`, `zia_forwarding_control_rule`, `zia_nat_control_rules`, `zia_sandbox_rules`, `zia_bandwidth_control_rules`, `zia_traffic_capture_rules`, `zia_file_type_control_rules`, `zia_casb_dlp_rules`, `zia_casb_malware_rules`.

If a resource isn't in this list, the rules below don't apply to it.

## The Three Hard Rules

| Rule                                         | What                                                                                              | Why                                                                                       |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| **`order` must be `>= 1`**                   | `validation.IntAtLeast(1)` rejects `0` and negatives at plan time (provider v4.7.9+).             | Older versions accepted `order = -1`, which the API stored as `0`, creating a corrupted rule that neither Terraform nor the GUI could delete. |
| **Orders must be contiguous**                | After deleting a rule at `order = 5`, manually decrement every order > 5 to stay contiguous.       | The API silently renumbers gaps, which makes Terraform see drift on every subsequent plan. |
| **Predefined rules cannot be `terraform destroy`d** | Use `terraform apply -target=<custom_rule>` to delete only custom rules. Leave predefined rules in HCL if you want to manage their order. | The API rejects `DELETE` on predefined rules; the provider correctly surfaces this as an error. |

## `order` Field — Canonical Schema (provider side, FYI)

```go
"order": {
    Type:         schema.TypeInt,
    Required:     true,
    ValidateFunc: validation.IntAtLeast(1),
},
```

You don't write this — the provider does. But knowing the validation exists tells you that `order = 0` will be rejected at `terraform plan`, not at apply.

## Predefined vs Custom Rules

| Aspect                  | Custom rule                                  | Predefined rule                                         |
| ----------------------- | -------------------------------------------- | ------------------------------------------------------- |
| Can create via TF       | Yes                                          | No (already exists)                                     |
| Can update fields       | Yes                                          | Limited — not all attributes apply                      |
| Can change `order`      | Yes                                          | **Yes** — supported as of provider v4.7.9               |
| Can `terraform destroy` | Yes                                          | **No** — API rejects                                    |
| Show up in `terraform plan` after `import` | Normal                       | May show extra fields (`predefined`, `default_rule`, `access_control`) — provider strips on PUT |

If you import a predefined rule into Terraform purely to control its position, scope your `lifecycle` block carefully:

```hcl
resource "zia_firewall_filtering_rule" "office_365_one_click" {
  name  = "Office 365 One Click Rule"   # predefined
  state = "ENABLED"
  action = "ALLOW"
  order  = 1

  lifecycle {
    ignore_changes = [
      # Predefined-rule attributes the API may surface but you don't manage
      # Add specific fields here only if you see persistent drift
    ]
  }
}
```

❌ Do not put `lifecycle { prevent_destroy = false }` and run `terraform destroy` thinking it will skip predefined rules. The API rejects it before destroy can complete.

## Reordering — The Per-Rule-Type Field-Stripping Map

When the provider's reorder callback runs, it has to PUT each rule back with the new `order`. Predefined rules return read-only fields on GET that the API rejects on PUT. As of provider v4.7.9, the provider strips them automatically — but the **set of stripped fields differs per rule type**:

| Rule resource                                                         | Stripped fields                          |
| --------------------------------------------------------------------- | ---------------------------------------- |
| `zia_ssl_inspection_rules`, `zia_firewall_filtering_rule`, `zia_firewall_dns_rules`, `zia_firewall_ips_rules`, `zia_nat_control_rules`, `zia_traffic_capture_rules` | `Predefined`, `DefaultRule`, `AccessControl` |
| `zia_cloud_app_control_rule`                                          | `Predefined`, `AccessControl`            |
| `zia_sandbox_rules`, `zia_bandwidth_control_rules`                    | `DefaultRule`, `AccessControl`           |
| `zia_dlp_web_rules`, `zia_file_type_control_rules`, `zia_casb_dlp_rules`, `zia_casb_malware_rules` | `AccessControl`                          |
| `zia_url_filtering_rules`, `zia_forwarding_control_rule`              | None (struct has no read-only fields)    |

You don't write this — the provider does. But if you see "Request body is invalid" on a reorder of one of these rules **and** you're on provider < 4.7.9, **upgrade**.

## Composing a Multi-Rule Configuration

```hcl
locals {
  base_order = 10  # leave 1-9 for higher-priority hand-managed rules
}

resource "zia_url_filtering_rules" "block_gambling" {
  name            = "Block Gambling"
  state           = "ENABLED"
  action          = "BLOCK"
  order           = local.base_order + 0
  url_categories  = ["GAMBLING"]
  protocols       = ["ANY_RULE"]
  request_methods = ["CONNECT", "DELETE", "GET", "HEAD", "OPTIONS", "OTHER", "POST", "PUT", "TRACE"]
}

resource "zia_url_filtering_rules" "block_adult" {
  name            = "Block Adult"
  state           = "ENABLED"
  action          = "BLOCK"
  order           = local.base_order + 1
  url_categories  = ["ADULT_THEMES"]
  protocols       = ["ANY_RULE"]
  request_methods = ["CONNECT", "DELETE", "GET", "HEAD", "OPTIONS", "OTHER", "POST", "PUT", "TRACE"]
}
```

Patterns:

- ✅ Pin a `local.base_order` to leave room for hand-managed predefined rules above it.
- ✅ Manage all rules of the **same type** (`zia_url_filtering_rules`) in **one** Terraform configuration. Splitting them across configs makes ordering impossible to reason about and causes thrash.
- ✅ Use `for_each` with a map keyed by rule purpose (`block_gambling`, not `block_0`) so you can add/remove rules without renaming addresses.

## Deleting a Rule Mid-Sequence

If you want to delete the rule at `order = 12` and you have rules at 10, 11, 12, 13, 14:

1. **Remove the HCL** for the rule at order 12.
2. **Decrement orders** for rules previously at 13 and 14 — change them to 12 and 13 in HCL.
3. **Apply** in one shot. Terraform will delete the removed rule and update orders on the remaining ones.
4. **Activate**. See [Activation](activation.md).

❌ Do not delete the rule and leave the gap (`10, 11, 13, 14`). The API may renumber it for you, and Terraform sees drift on every subsequent plan.

If you want to delete only **one** rule out of many in a stable way (e.g. emergency removal):

```bash
terraform apply -target=zia_url_filtering_rules.block_gambling
# then in a follow-up commit, decrement the surviving rules' orders to stay contiguous
```

## Common Errors

| Error                                                                       | Cause                                                                                       | Fix                                                                                              |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `expected order to be at least (1), got 0`                                  | `order = 0` or negative — pre-empted by validation.                                          | Set `order >= 1`.                                                                                |
| `expected order to be at least (1), got -1`                                 | Same as above.                                                                              | Same.                                                                                            |
| `Request body is invalid` on a predefined-rule reorder                      | Provider < 4.7.9; read-only fields not stripped.                                            | Upgrade `zscaler/zia` to ≥ 4.7.9.                                                                |
| `deletion of the predefined rule '...' is not allowed`                       | `terraform destroy` (or removing HCL of) a predefined rule.                                 | Remove from Terraform via `terraform state rm` is **wrong**. Instead, leave the HCL in place. To stop managing, document and accept it stays in the GUI. |
| Rule applied but not enforced                                                | No `zia_activation_status` change after the rule changes.                                   | Add or update `zia_activation_status` (see [Activation](activation.md)).                          |
| `terraform plan` shows churn on `order` of unrelated rules                  | Non-contiguous orders.                                                                      | Re-number to contiguous in HCL.                                                                  |
| `terraform plan` shows churn on `predefined`, `default_rule`, `access_control` after import | API returns these fields; older provider didn't strip them.                                 | Upgrade provider; if that doesn't help, add them to `lifecycle.ignore_changes`.                  |
| Rule fires but action is wrong                                              | `actions` enum mismatch with the rule `type` (cloud_app_control), or `action` enum wrong for the rule resource. | Check the `action` enum table in [Resource Catalog](resource-catalog.md) and the per-type actions data source. |

## When To Use `lifecycle.ignore_changes`

Sparingly. Most "drift" on rule resources is fixable by:

1. Upgrading the provider (most common fix).
2. Switching `TypeList` back to `TypeSet` (provider-side, file an issue).
3. Re-checking the order rules above.

Use `ignore_changes` only when you've confirmed the field is genuinely API-managed and you don't want to fight it. Document why every time.

```hcl
resource "zia_firewall_filtering_rule" "imported_predefined" {
  # ...
  lifecycle {
    ignore_changes = [
      # API surfaces this on GET but rejects updates;
      # provider strips on PUT but the diff still appears in plan
      access_control,
    ]
  }
}
```
