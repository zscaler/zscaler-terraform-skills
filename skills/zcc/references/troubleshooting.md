# ZCC — Troubleshooting

User-facing diagnostics for the most common ZCC HCL problems.

## Always Capture Debug Logs First

```bash
TF_LOG=DEBUG \
ZSCALER_SDK_VERBOSE=true \
ZSCALER_SDK_LOG=true \
  terraform apply -no-color 2>&1 | tee /tmp/zcc-debug.log
```

❌ Do not paste a raw debug log into a public issue tracker — it contains tokens. ✅ Redact `Authorization:` headers, `client_secret`, and any `*_secret` values before sharing.

---

## Symptom Index

| Symptom                                                                                    | Section                                                       |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| `terraform plan` shows changes you didn't make                                             | [Drift Causes](#drift-causes)                                 |
| `condition_type` keeps flipping between `0` and `1`                                         | [Schema Quirks: condition_type](#schema-quirks)              |
| `terraform destroy` of `zcc_failopen_policy` "succeeds" but the policy still exists in ZCC | [Singleton / Existing-Only Lifecycle](#singleton--existing-only-lifecycle) |
| `zcc_web_app_service` create fails with not-found                                           | [Singleton / Existing-Only Lifecycle](#singleton--existing-only-lifecycle) |
| `401 unauthorized` despite setting env vars                                                 | [auth-and-providers.md → The Env Var Trap](auth-and-providers.md#the-env-var-trap) |
| GUID-related update failures                                                                | [Schema Quirks: guid](#schema-quirks)                         |
| Want to remove from Terraform without touching the underlying ZCC object                    | [Never `state rm` a Standard ZCC Resource](#never-state-rm-a-standard-zcc-resource) |

---

## Drift Causes

### Bool / Number / String type confusion on `zcc_failopen_policy`

Symptom: every plan shows `~ enable_fail_open = "1" -> 1` or vice versa.

Cause: this resource has **inconsistent types** for similar-looking fields:

- `enable_fail_open`, `enable_captive_portal_detection`, `enable_strict_enforcement_prompt` — **Number** (`0` / `1`).
- `active`, `enable_web_sec_on_proxy_unreachable`, `enable_web_sec_on_tunnel_failure` — **String** (`"0"` / `"1"`).

Fix: match the type exactly. See [Resource Catalog: zcc_failopen_policy](resource-catalog.md#zcc_failopen_policy-singleton).

### `condition_type` flipping

Symptom: `~ condition_type = 0 -> 1` (or vice versa) on every plan, even though you didn't change it.

Cause: the API returns whatever value was last set; `0` and `1` are both valid. If you set `0` in HCL but a previous out-of-band change set it to `1`, every plan tries to revert.

Fix:

| Option                                | When                                                                |
| ------------------------------------- | ------------------------------------------------------------------- |
| Match the API's value in HCL          | If you don't care which it is, just match the GET response.         |
| Omit `condition_type` entirely        | If the field doesn't matter for your match logic, leave it unset.    |
| `lifecycle { ignore_changes = [condition_type] }` | If out-of-band changes are expected (e.g., admin tweaks via console). |

### Match field churn (DNS, hostnames, SSID)

Symptom: a match field keeps churning even though you didn't change HCL.

Cause: the API normalizes whitespace, ordering, or case for some match fields.

Fix: match the API's normalized form in HCL exactly. Capture the GET response with debug logging and copy the normalized value.

---

## Schema Quirks

### `condition_type` (both `0` and `1` valid)

The ZCC API accepts both values for the same logical state in some contexts. There is no canonical "default" — set what `GET listByCompany` returns. See above for handling.

### `guid` (read-only on `zcc_trusted_network`)

`guid` is set by the API on create and **automatically included in PUT requests** by the provider. Do not set it manually in HCL.

❌ Wrong:

```hcl
resource "zcc_trusted_network" "x" {
  network_name = "..."
  guid         = "abc-123-def"   # ← will be ignored or rejected
}
```

✅ Right: omit `guid`. After import, the provider populates it in state and uses it for subsequent updates.

### `app_name` lookup on `zcc_web_app_service`

`zcc_web_app_service` is **existing-only** — it does not create a new web app service, it locates one by `app_name` and updates it.

Symptom: create fails with `not found: app_name = "..."`.

Cause: the bypass app doesn't exist in the tenant.

Fix:

1. Create the bypass app in the ZCC admin portal.
2. Re-run `terraform apply`. The `zcc_web_app_service` resource will locate it and apply your settings.

There is no `resource "zcc_create_web_app_service"` — bypass apps are administered out-of-band.

### Inconsistent enable_* type families on `zcc_failopen_policy`

Already covered in [Drift Causes](#drift-causes). The mix of Number / String types isn't a bug, it's the API's typing — the provider passes through.

---

## Singleton / Existing-Only Lifecycle

### `terraform destroy` of `zcc_failopen_policy` removes from state but not API

Symptom: `terraform destroy` succeeds, but the fail-open policy is still active in the ZCC admin portal with the settings you applied.

Cause: `zcc_failopen_policy` is a **singleton per company**. The provider intentionally implements `delete` as a state-only operation — there's no API to delete the singleton, only to update its settings.

This is by design. To "undo" your changes:

| Goal                                          | Action                                                                                  |
| --------------------------------------------- | --------------------------------------------------------------------------------------- |
| Stop managing in Terraform, keep current settings | `removed { from = ... lifecycle { destroy = false } }` (TF 1.7+).                    |
| Reset to defaults                             | Define a new `zcc_failopen_policy` block with the desired defaults and apply.           |
| Hand back to manual admin                     | `terraform state rm` and document the handoff (this is the singleton's safe `state rm`). |

### `terraform destroy` of `zcc_web_app_service`

Same pattern — destroy removes from state only. The bypass app stays in ZCC. Use the ZCC admin portal to delete the underlying app if needed.

---

## Never `state rm` a Standard ZCC Resource

For `zcc_trusted_network` and `zcc_forwarding_profile` (the standard CRUD resources), `terraform state rm` removes the resource from state but **does not delete it from ZCC**. The next apply with the same HCL will then either:

- Try to create an object with the same name → may succeed and create a duplicate.
- Or, if you renamed the HCL block, succeed in creating a duplicate alongside the orphaned one.

Safe alternatives:

| Goal                                          | Use                                                                                     |
| --------------------------------------------- | --------------------------------------------------------------------------------------- |
| Stop managing in Terraform, keep in ZCC       | `removed { from = ... lifecycle { destroy = false } }` (TF 1.7+).                        |
| Move to a different Terraform module          | `moved { from = ... to = ... }` block (TF 1.1+).                                         |
| Permanently remove from ZCC                   | Remove the HCL block and apply (`terraform destroy -target=...` for one-shot).           |
| Re-import after a re-org                      | `terraform import zcc_<resource>.<addr> <id>`.                                           |

The **only** ZCC resources where `terraform state rm` is the right answer are the singleton / existing-only ones (`zcc_failopen_policy`, `zcc_web_app_service`) — and only when you intentionally want to stop managing without deleting.

---

## Quick Reference

| Problem                                            | First thing to try                                                                     |
| -------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `condition_type` flip                              | Match API value, or `ignore_changes`.                                                  |
| Type mismatch on `zcc_failopen_policy`             | Check Number vs String per field; see resource catalog table.                          |
| `zcc_web_app_service` create fails                 | Create the bypass app in ZCC admin portal first.                                       |
| Destroy "succeeds" but object remains              | You're on a singleton/existing-only resource — that's by design.                       |
| `401` despite env vars                             | You probably mixed `ZSCALER_*` and `ZCC_*` namespaces. See auth-and-providers.md.      |
| GUID drift                                          | Don't set `guid` in HCL.                                                                |
| Want to detach a standard resource                 | `removed { from = ... lifecycle { destroy = false } }`, not `terraform state rm`.       |
| Need to capture HTTP for support ticket            | `TF_LOG=DEBUG ZSCALER_SDK_VERBOSE=true ZSCALER_SDK_LOG=true terraform plan`, redact tokens. |
