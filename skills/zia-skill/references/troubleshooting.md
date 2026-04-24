# ZIA — Troubleshooting

User-facing diagnostics for the most common ZIA HCL problems. Provider-internal Go-side debugging is out of scope.

## Always Capture Debug Logs First

```bash
TF_LOG=DEBUG \
ZSCALER_SDK_VERBOSE=true \
ZSCALER_SDK_LOG=true \
  terraform apply -no-color 2>&1 | tee /tmp/zia-debug.log
```

This enables Terraform's debug logging **and** the Zscaler SDK's HTTP request/response logging. Every diagnostic below assumes you have this log.

❌ Do not paste a raw debug log into a public issue tracker — it contains tokens. ✅ Redact `Authorization:` headers and any `client_secret` / `pre_shared_key` / `password` values before sharing.

---

## Symptom Index

| Symptom                                                                                          | Section                                                       |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| `terraform plan` shows changes you didn't make                                                   | [Drift Causes](#drift-causes)                                 |
| `400 DUPLICATE_ITEM` on create                                                                    | [DUPLICATE_ITEM on Create](#duplicate_item-on-create)         |
| `deletion of the predefined rule 'X' is not allowed`                                              | [Predefined-Rule Errors](#predefined-rule-errors)             |
| `Request body is invalid` on rule reorder                                                         | [Predefined-Rule Errors](#predefined-rule-errors)             |
| `expected order to be at least (1), got 0`                                                        | [rules-and-ordering.md → Common Errors](rules-and-ordering.md#common-errors) |
| `'AUC' is not a valid ISO-3166 Alpha-2 country code` / country rejected on `zia_location_management` | [Country Code & Locale Validation](#country-code--locale-validation) |
| DLP dictionary lookup fails (`no dictionary found with name: ...`)                                 | [DLP Dictionary Names](#dlp-dictionary-names-with-spaces)     |
| Cloud app control action rejected as conflicting                                                  | [Conflicting API Actions](#conflicting-api-actions)           |
| Apply succeeds but policy doesn't change                                                          | [activation.md](activation.md)                                |
| Want to remove a resource without deleting in ZIA                                                 | [Never `state rm` a ZIA Resource](#never-state-rm-a-zia-resource) |

---

## Drift Causes

`terraform plan` shows `~` diffs after a clean `apply`, no human change. Almost always one of:

### Bool flipping back to `false`

Symptom: `~ enable_full_logging = false -> true` (or vice versa) on every plan.

Cause: `omitempty` in the SDK — the API omits `false` from the GET response. Older provider schemas didn't compensate.

Fix:

| Option                            | When                                                         |
| --------------------------------- | ------------------------------------------------------------ |
| Upgrade `zscaler/zia` to latest 4.x | Always try first.                                            |
| Set the value explicitly in HCL   | Pin to whatever Terraform expects.                            |

### API-injected default values

Symptom: `~ idle_time_in_minutes = 0 -> 30` or `~ display_time_unit = "" -> "MINUTE"` on every plan.

Cause: the API injects defaults you didn't ask for. The schema needs `Computed: true`.

Fix: upgrade provider; if not fixed, file an issue.

### Predefined fields churn after import

Symptom: `~ predefined`, `~ default_rule`, `~ access_control` flip on every plan after `terraform import`.

Cause: API returns these on GET; older provider didn't strip them on PUT.

Fix: upgrade `zscaler/zia` ≥ 4.7.9. If drift remains, add them to `lifecycle.ignore_changes`.

### Write-only fields cleared on Read

Symptom: `pre_shared_key`, `password`, or `api_key` becomes `""` after refresh.

Cause: API never returns secrets on GET. The provider should preserve from prior state.

Fix:

- ✅ Mark the variable holding the value `sensitive = true`.
- ❌ Don't try to set it from a data source — it will be empty.
- If you imported the resource, you must re-set the secret via Terraform variable; the API can't recover it.

### TypeList ordering drift on nested IDs

Symptom: `~ departments { id = [...] }` reorders.

Cause: API returns IDs in a different order than HCL.

Fix: sort your HCL list to match the API order, or upgrade — many of these have been converted to TypeSet.

---

## DUPLICATE_ITEM on Create

Symptom:

```text
Error: POST .../<resource>, 400, {"code":"DUPLICATE_ITEM","message":"DUPLICATE_ITEM"}
```

Cause: a resource with the same name already exists. Common cases:

- A predefined system resource has that name (e.g. `Office 365 One Click Rule`).
- A previous failed apply created the resource but didn't write it to state.
- Another team manages the same name out-of-band.

Fix:

| Option                                       | When                                                                          |
| -------------------------------------------- | ----------------------------------------------------------------------------- |
| Use a unique name                            | Easiest if you have naming flexibility.                                       |
| `terraform import zia_<resource>.<addr> <id>` | If you want the existing object under management.                             |
| Delete the conflict via the ZIA console      | Only if it's a stale custom resource, not predefined.                         |

❌ Do not loop `terraform apply` — the same conflict will repeat.

---

## Predefined-Rule Errors

### "deletion of the predefined rule 'X' is not allowed"

Cause: you removed a predefined-rule resource from HCL, or ran `terraform destroy`. The API refuses to delete it.

Fix: leave the HCL block in place. If you don't want to manage the rule via Terraform, accept that it stays in the GUI and remove the block from HCL **plus** `terraform state rm` the predefined rule (the rule itself stays in ZIA — `state rm` only severs Terraform's tracking, not the API object).

This is the **one** safe use of `terraform state rm` in ZIA — but only for predefined rules you no longer want to manage. For custom rules, see [Never `state rm` a ZIA Resource](#never-state-rm-a-zia-resource).

### "Request body is invalid" on rule reorder

Cause: provider < 4.7.9 not stripping read-only fields (`Predefined`, `DefaultRule`, `AccessControl`) on PUT for predefined rules during reorder.

Fix: upgrade `zscaler/zia` ≥ 4.7.9. If still seeing it, file a bug with the resource name + plan output.

### Stuck rule order after a failed reorder

Cause: a previous reorder failed mid-way, leaving rules at non-contiguous orders.

Fix:

1. List current orders via the GUI or `data "zia_*_rules" "x"`.
2. Re-write all `order` values in HCL to be contiguous.
3. Apply.
4. Activate.

---

## Country Code & Locale Validation

### Firewall rules: ISO-3166 Alpha-2

```text
Error: 'AUC' is not a valid ISO-3166 Alpha-2 country code
```

`dest_countries` (and similar) on `zia_firewall_*_rule`, `zia_url_filtering_rules`, etc. requires **two-letter** ISO codes:

```hcl
dest_countries = ["US", "BR", "DE"]   # ✅
dest_countries = ["USA"]              # ❌ — three letters
```

### Location management: full uppercase name

```text
Error: country must be a valid uppercase country name
```

`country` on `zia_location_management` requires the **full uppercase enum name**, not the ISO code:

```hcl
country = "UNITED_STATES"   # ✅
country = "US"              # ❌ — that's the firewall format
country = "United States"   # ❌ — wrong case
```

These two formats are easy to swap. The provider validates each locally at `terraform plan`.

---

## DLP Dictionary Names with Spaces

Symptom:

```text
Error: no dictionary found with name: Social Security Numbers (US)
```

Cause: the predefined dictionary name has spaces and parens. The lookup mechanism is sensitive to exact match.

Fix: clone the predefined dictionary with a name using underscores or dashes, then reference the clone:

```hcl
resource "zia_dlp_dictionary" "ssn_us" {
  name              = "social_security_numbers_us"   # underscores
  dictionary_type   = "PATTERNS_AND_PHRASES"
  # … copy phrases / patterns from the predefined dictionary, or use clone semantics
}
```

Then reference the clone (`zia_dlp_dictionary.ssn_us.id`) in your DLP engines.

---

## Conflicting API Actions

Symptom: cloud app control rule rejected with `Invalid action combination` or similar, even when the actions look valid per the data source.

Cause: some API endpoints (notably `webApplicationRules/AI_ML`) have contradictory validation — they require a permissive action alongside a restrictive one, then reject the combination as conflicting.

Status: API-level bug; tracked internally. Provider passes actions through as-is.

Workaround:

1. Build the rule via the ZIA Admin Portal first.
2. Capture the working action combination via `data "zia_cloud_app_control_rule" "x" { name = "..." }`.
3. Mirror that exact combination in HCL.

---

## Never `state rm` a ZIA Resource

`terraform state rm zia_url_filtering_rules.x` removes the resource from state but **does not delete it from ZIA**. The next `terraform apply` will then either:

- Try to *create* an object with the same name → `DUPLICATE_ITEM`.
- Or, if you renamed the HCL block, succeed in creating a duplicate alongside the orphaned one.

Safe alternatives:

| Goal                                          | Use                                                                                     |
| --------------------------------------------- | --------------------------------------------------------------------------------------- |
| Stop managing in Terraform, keep in ZIA       | `removed { from = ... lifecycle { destroy = false } }` (TF 1.7+).                        |
| Move to a different Terraform module          | `moved { from = ... to = ... }` block (TF 1.1+).                                         |
| Permanently remove from ZIA                   | Remove the HCL block and apply (`terraform destroy -target=...` for one-shot).           |
| Re-import after a re-org                      | `terraform import zia_<resource>.<addr> <id>`.                                           |

The **one exception** is predefined rules — `terraform state rm` is the safe way to stop managing a predefined rule without deleting it from ZIA (since you can't delete predefined rules in the API anyway).

---

## Quick Reference

| Problem                                            | First thing to try                                                                     |
| -------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Bool drift                                         | Upgrade provider to latest 4.x.                                                        |
| Predefined-rule reorder fails                      | Upgrade provider to ≥ 4.7.9.                                                           |
| `DUPLICATE_ITEM`                                   | Use unique name or `terraform import`.                                                 |
| Country code rejected                              | Firewall = ISO Alpha-2 (`US`); Location = uppercase enum (`UNITED_STATES`).            |
| DLP dictionary lookup fails                        | Clone with underscores in name.                                                        |
| AI_ML cloud app actions rejected                   | Capture working combo from console, mirror in HCL.                                     |
| Apply succeeds, no enforcement                     | Add `zia_activation_status` with `depends_on`. See [activation.md](activation.md).     |
| Want to stop managing predefined rule              | `terraform state rm` (the rule stays in ZIA — that's correct).                          |
| Want to stop managing custom rule without delete   | `removed { from = ... lifecycle { destroy = false } }`.                                |
| Need to capture HTTP for support ticket            | `TF_LOG=DEBUG ZSCALER_SDK_VERBOSE=true ZSCALER_SDK_LOG=true terraform plan`, redact tokens. |
