# ZTC — Troubleshooting

User-facing diagnostics for the most common ZTC HCL problems.

## Always Capture Debug Logs First

```bash
TF_LOG=DEBUG \
ZSCALER_SDK_VERBOSE=true \
ZSCALER_SDK_LOG=true \
  terraform apply -no-color 2>&1 | tee /tmp/ztc-debug.log
```

❌ Do not paste a raw debug log into a public issue tracker — it contains tokens. ✅ Redact `Authorization:` headers, `client_secret`, `password`, and `api_key` values before sharing.

---

## Symptom Index

| Symptom                                                                                          | Section                                                       |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| `terraform plan` shows changes you didn't make                                                   | [Drift Causes](#drift-causes)                                 |
| `400 DUPLICATE_ITEM` on create                                                                    | [DUPLICATE_ITEM on Create](#duplicate_item-on-create)         |
| `terraform import` of a location/edge connector group fails                                       | [Cloud-Orchestrated Object Confusion](#cloud-orchestrated-object-confusion) |
| Rule applied but not enforced                                                                     | [rules-and-ordering.md → Activation](rules-and-ordering.md#activation) |
| `expected order to be at least (1), got 0`                                                        | [rules-and-ordering.md → Common Errors](rules-and-ordering.md#common-errors) |
| Multi-rule-type apply ends up with wrong order                                                    | [rules-and-ordering.md → Multi-Rule-Type Reorder Race](rules-and-ordering.md#multi-rule-type-reorder-race-fixed-in-v017--v018) |
| Resource works on legacy but read returns empty / wrong data on OneAPI                            | [OneAPI vs Legacy Availability Gaps](#oneapi-vs-legacy-availability-gaps) |
| `proxy_gateway` block keeps showing `~ name` drift                                                | [Drift Causes → proxy_gateway nested block](#drift-causes)   |
| Want to remove a Terraform-managed resource without deleting in ZTC                              | [Never `state rm` a ZTC Resource](#never-state-rm-a-ztc-resource) |

---

## Drift Causes

### `proxy_gateway` nested block churns

Symptom: `~ name = "" -> "ZIA_GW01"` on the `proxy_gateway` block of a `ztc_traffic_forwarding_rule` on every plan.

Cause: only `id` was set in HCL; the API returns both `id` and `name` and the schema requires both.

Fix:

```hcl
proxy_gateway {
  id   = ztc_forwarding_gateway.zia_gw.id
  name = ztc_forwarding_gateway.zia_gw.name
}
```

### Bool flipping back to `false`

Symptom: a boolean attribute flips on every plan.

Cause: SDK `omitempty` returning nothing for `false`. Older provider versions didn't compensate.

Fix: upgrade to latest `0.1.x`. If still seeing it, file an issue with the resource name and schema field.

### `order` re-renumbers on plans you didn't change

Cause: non-contiguous orders. See [rules-and-ordering.md](rules-and-ordering.md#deleting-a-rule-mid-sequence).

### Multi-rule-type reorder race

Symptom: After applying a config that creates rules of two different rule types in one apply, the final order in the API doesn't match HCL.

Cause: known race condition in provider <0.1.7.

Fix: upgrade to `~> 0.1.8`.

---

## DUPLICATE_ITEM on Create

Symptom:

```text
Error: POST .../<resource>, 400, {"code":"DUPLICATE_ITEM"}
```

Common causes:

| Cause                                                                            | Fix                                                                                       |
| -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Trying to `resource "ztc_location_management"` for a cloud-orchestrated location | Switch to `data "ztc_location_management"`. See [Cloud-Orchestrated Object Confusion](#cloud-orchestrated-object-confusion). |
| A predefined network service / IP group has the same name                        | Use a unique name, or `terraform import` the existing object.                              |
| Previous failed apply created the object but didn't write to state               | `terraform import ztc_<resource>.<addr> <id>`.                                            |
| Another team manages the same name out-of-band                                   | Coordinate naming; consider a per-team naming prefix.                                      |

---

## Cloud-Orchestrated Object Confusion

The most common new-user mistake.

In ZTC, edge connector groups and locations are typically created automatically by cloud connector orchestration in AWS/Azure/GCP. The Terraform provider exposes them only as **data sources**:

❌ **Wrong** — trying to declare a location as a resource:

```hcl
resource "ztc_location_management" "aws_vpc" {
  name = "AWS-CAN-ca-central-1-vpc-05c7f364cf47c2b93"
}
```

This will either fail with `DUPLICATE_ITEM` or — worse — succeed by creating a duplicate location that conflicts with the orchestrated one.

✅ **Right** — read the orchestrated location:

```hcl
data "ztc_location_management" "aws_vpc" {
  name = "AWS-CAN-ca-central-1-vpc-05c7f364cf47c2b93"
}

# Use data.ztc_location_management.aws_vpc.id everywhere a location_id is needed
```

The same pattern applies to `ztc_edge_connector_group`. See [Resource Catalog: Cloud-Orchestrated Objects](resource-catalog.md#cloud-orchestrated-objects).

---

## OneAPI vs Legacy Availability Gaps

A handful of ZTC resources have different read behavior between OneAPI and the legacy v3 API. Notably, `ztc_traffic_forwarding_rule` had a READ function bug fixed in v0.1.5/v0.1.6 where OneAPI tenants got incomplete data back.

Symptom: A resource imports cleanly via the legacy API but on OneAPI, `terraform plan` shows it wants to recreate or update fields you never changed.

Diagnosis:

```bash
# Compare what each auth path returns:
TF_LOG=DEBUG ZSCALER_USE_LEGACY_CLIENT=true terraform plan 2>&1 | grep -A 30 "ZSCALER SDK RESPONSE"
TF_LOG=DEBUG terraform plan 2>&1 | grep -A 30 "ZSCALER SDK RESPONSE"   # OneAPI
```

If the OneAPI response is missing fields, you're hitting the gap.

Fix:

| Option                                       | When                                                                          |
| -------------------------------------------- | ----------------------------------------------------------------------------- |
| Upgrade `zscaler/ztc` to ≥ 0.1.6             | Best fix for the documented `ztc_traffic_forwarding_rule` gap.                |
| Stick to legacy auth temporarily             | If your tenant is GOV / `zscalerten` you don't have a choice anyway.          |
| File an issue with redacted debug logs       | If still broken on the latest provider — there may be additional gaps.        |

---

## Never `state rm` a ZTC Resource

`terraform state rm ztc_traffic_forwarding_rule.x` removes the resource from state but **does not delete it from ZTC**. The next `terraform apply` will then either:

- Try to create an object with the same name → `DUPLICATE_ITEM`.
- Or, if you renamed the HCL block, succeed in creating a duplicate alongside the orphaned one.

Safe alternatives:

| Goal                                          | Use                                                                                     |
| --------------------------------------------- | --------------------------------------------------------------------------------------- |
| Stop managing in Terraform, keep in ZTC       | `removed { from = ... lifecycle { destroy = false } }` (TF 1.7+).                        |
| Move to a different Terraform module          | `moved { from = ... to = ... }` block (TF 1.1+).                                         |
| Permanently remove from ZTC                   | Remove the HCL block and apply (`terraform destroy -target=...` for one-shot).           |
| Re-import after a re-org                      | `terraform import ztc_<resource>.<addr> <id>`.                                           |

The **one** time `terraform state rm` is appropriate for ZTC is when you accidentally created a `ztc_location_management` resource for a cloud-orchestrated location and need to detach Terraform without affecting the real (orchestrated) object — but you should verify with the Zscaler team first.

---

## Quick Reference

| Problem                                            | First thing to try                                                                     |
| -------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `proxy_gateway` drift                              | Set both `id` and `name` on the nested block.                                          |
| Multi-rule-type reorder wrong                      | Upgrade `zscaler/ztc` to `~> 0.1.8`.                                                   |
| `DUPLICATE_ITEM` on a location                     | Switch from `resource` to `data` for orchestrated locations.                           |
| OneAPI plan shows phantom changes                  | Try legacy auth as a comparison; upgrade provider; file issue if persistent.           |
| Rule applied but not enforced                      | Add `ztc_activation_status` with `depends_on`.                                          |
| Want to stop managing without deleting             | `removed { from = ... lifecycle { destroy = false } }`.                                |
| Need to capture HTTP for support ticket            | `TF_LOG=DEBUG ZSCALER_SDK_VERBOSE=true ZSCALER_SDK_LOG=true terraform plan`, redact tokens. |
