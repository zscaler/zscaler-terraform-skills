# ZPA — Troubleshooting

User-facing diagnostics for the most common ZPA HCL problems. Provider-internal Go-side debugging is out of scope.

## Always Capture Debug Logs First

```bash
TF_LOG=DEBUG \
ZSCALER_SDK_VERBOSE=true \
ZSCALER_SDK_LOG=true \
  terraform apply -no-color 2>&1 | tee /tmp/zpa-debug.log
```

This enables Terraform's debug logging **and** the Zscaler SDK's HTTP request/response logging (`ZSCALER SDK REQUEST` / `ZSCALER SDK RESPONSE` markers). Every diagnostic below assumes you have this log.

❌ Do not paste a debug log directly into a public issue tracker — it contains tokens. ✅ Redact the `Authorization:` header and any `client_secret` before sharing.

---

## Symptom Index

| Symptom                                                                                          | Section                                                       |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| `terraform plan` shows changes you didn't make                                                   | [Drift Causes](#drift-causes)                                 |
| `terraform destroy` fails with `RESOURCE_IN_USE`                                                 | [Detach Before Delete](#detach-before-delete)                 |
| Resource exists in console, Read returns 404, Terraform recreates                                | [Microtenant Not Found](#microtenant-not-found)               |
| Policy rule rejected with `400 INVALID_INPUT`                                                    | [Policy 400 Errors](#policy-400-errors)                       |
| `401 unauthorized` or `vanity_domain not found`                                                  | [auth-and-providers.md → Common Auth Errors](auth-and-providers.md#common-auth-errors) |
| Stale resources blocking `terraform apply` after a failed run                                    | [Stale Test / PoC Resources](#stale-test--poc-resources)      |
| Want to remove a resource without deleting in ZPA                                                | [Never `state rm` a ZPA Resource](#never-state-rm-a-zpa-resource) |
| AppProtection / AD Inspection turned off, segment missing from the console list after an apply   | [AppProtection Segment Disappears After an Update](#appprotection-segment-disappears-after-an-update) |
| `terraform plan` takes many minutes on a large configuration                                     | [Slow Plans in Large Configurations](#slow-plans-in-large-configurations) |
| `api.concurrent.access.error` on a policy rule create, update, or delete                         | [Concurrent Policy Rule Writes](#concurrent-policy-rule-writes) |

---

## Drift Causes

`terraform plan` shows `~` diffs after a clean `apply`, no human change. Almost always one of:

### Bool flipping back to `false`

Symptom: `~ enabled = false -> true` (or vice versa) on every plan.

Cause: the API omits the field from the response when its value is `false` (`omitempty` in the SDK), and the resource schema doesn't compensate. This is fixed in newer provider versions for most resources, but if you hit it, you have two user-side options:

| Option                            | When                                                         |
| --------------------------------- | ------------------------------------------------------------ |
| Upgrade provider to latest 4.x    | Always try first. Most omit-empty bool drifts are fixed.     |
| Set the value explicitly in HCL   | Pin the value Terraform expects (e.g. `enabled = true`).     |

If the drift survives a provider upgrade, file an issue at <https://github.com/zscaler/terraform-provider-zpa/issues> with the resource name, attribute, and a redacted plan output.

### `conditions` block order shifting on policy rules

Symptom: `~ conditions { ... }` keeps reordering, no functional change.

Cause: the API returns conditions in a different order than what you wrote. Workaround:

- ✅ Always order conditions consistently in HCL — put the most specific (e.g. `APP`) first.
- ❌ Do not split a single rule across multiple Terraform configurations — it makes drift impossible to reason about.
- If drift persists, file an issue with the API team via Zscaler support; provider can't fix what the API returns.

### TypeList ordering drift on nested IDs

Symptom: `~ servers { id = [...] }` reorders.

Cause: the API returns IDs in a different order than HCL.

Fix: sort your HCL list to match the API order, or accept the drift as cosmetic. The provider may convert these to TypeSet (order-insensitive) in a future release.

### Write-only fields cleared on Read

Symptom: a secret-like field becomes `""` after refresh.

Cause: the API does not return secrets on GET. Fix: the provider should preserve them from prior state. If it doesn't, file a bug. As a user-side workaround, mark the variable `sensitive = true` and don't rely on outputs.

### Microtenant scope changed silently

Symptom: full recreate on next plan, even though nothing changed.

Cause: the resource was created with `microtenant_id = "X"` but the credential / Read call doesn't pass it. Read returns 404 → Terraform thinks the resource is gone. See [Microtenant Not Found](#microtenant-not-found).

---

## Detach Before Delete

Symptom:

```text
Error: DELETE .../appConnectorGroup/123, 400, {"code":"RESOURCE_IN_USE","message":"resource is in use"}
```

Affected resources: `zpa_app_connector_group`, `zpa_segment_group`, `zpa_server_group`, `zpa_application_segment` referenced by policy rules.

Cause: ZPA refuses to delete an object that is still referenced by another object (typically a policy rule).

Fix order:

1. Remove the policy rule (or update it to no longer reference the target object).
2. Apply (`terraform apply`).
3. Now the underlying object can be deleted — apply again to remove it, or `terraform destroy` it.

If you want this to happen in a single apply, use `depends_on` so Terraform knows the rule must be destroyed before the segment:

```hcl
resource "zpa_policy_access_rule" "to_crm" {
  # ...
  depends_on = [zpa_application_segment.crm]   # ensures rule is destroyed first on teardown
}
```

❌ Do not `terraform state rm` the policy rule to "force" the segment to delete — see [Never `state rm` a ZPA Resource](#never-state-rm-a-zpa-resource).

---

## Microtenant Not Found

Symptom:

```text
Error: GET .../segmentGroup/789, 404, resource not found
```

…on a resource that you can see in the ZPA console.

Cause: the resource lives in a microtenant, but Read is called without the microtenant context. The API returns 404. Terraform interprets 404 as "resource was deleted" and either recreates it or wipes it from state on next plan.

Diagnostic checklist:

- ✅ The resource was created with `microtenant_id = "..."` in HCL.
- ✅ The same `microtenant_id` is in current state (`terraform state show <addr>` should show it).
- ✅ The credential you're using (OneAPI client or legacy v3 secret) is scoped to (or has access to) that microtenant.
- ✅ Every data source that looks up a microtenant-scoped object also passes `microtenant_id`.

Common gotchas:

- ❌ Removed `microtenant_id` from HCL after the fact → next plan recreates the resource in the parent tenant.
- ❌ Two team members using credentials scoped to different microtenants on the same state → first one to apply wins, second sees 404 churn.

Fix: thread `var.zpa_microtenant_id` through every resource and every data source. Use `null` for parent-tenant. Do not mix scopes in one state file.

---

## Policy 400 Errors

Symptom: `400 INVALID_INPUT: Invalid operand type for the given condition` or `LHS value is required for the given operand`.

This is almost never a provider bug — it's an operand-shape mismatch.

Diagnostic:

1. Identify the failing rule.
2. For each `conditions { operands { ... } }` block, look up the `object_type` in [Policy Rules: Operand Reference](policy-rules.md#operand-reference).
3. Confirm `lhs`, `rhs`, and (for SCIM/SAML) `idp_id` are shaped exactly as that table says.

Top three offenders by frequency:

| Mistake                                                                                  | Fix                                                              |
| ---------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `SCIM_GROUP` with `lhs = "id"`                                                           | `lhs = data.zpa_idp_controller.<x>.id`, then add `idp_id` field. |
| `POSTURE` with `rhs = true` (boolean)                                                    | `rhs = "true"` (string).                                         |
| `SAML` operand without `idp_id`                                                          | Add `idp_id = data.zpa_idp_controller.<x>.id`.                   |

If the rule looks correct but the API still rejects, build the same rule in the ZPA Admin Portal, then capture its API representation (`GET .../policySet/.../rules/<id>`) and diff against the Terraform-generated payload.

---

## Stale Test / PoC Resources

Symptom: `Error: <name> already exists` on `terraform apply` after a previous run failed mid-way.

Cause: the previous run created a resource but errored before recording it in state. Terraform doesn't know about it.

Fix:

| Option                                       | When                                                  |
| -------------------------------------------- | ----------------------------------------------------- |
| Rename the resource (different `name` arg)   | Easiest if you're in active development.              |
| Delete it via the ZPA Admin Portal          | One-shot fix.                                         |
| `terraform import zpa_<resource>.<addr> <id>` | If you want the existing object under management.     |

❌ Do not `terraform state rm` and re-apply with the same name — the same conflict will repeat.

---

## Never `state rm` a ZPA Resource

`terraform state rm zpa_application_segment.x` removes the resource from state but **does not delete it from ZPA**. The next `terraform apply` will then either:

- Try to *create* an object with the same name → `400 already exists`.
- Or, worse, succeed in creating a duplicate alongside the orphaned one — and now you have two segments with the same domain, only one of which Terraform manages.

Safe alternatives:

| Goal                                          | Use                                                                                     |
| --------------------------------------------- | --------------------------------------------------------------------------------------- |
| Stop managing in Terraform, keep in ZPA       | `terraform state rm` **and** rename the object in ZPA console. Risky — prefer `removed`. |
| Move to a different Terraform module          | `moved { from = ... to = ... }` block (Terraform 1.1+).                                  |
| Permanently remove from ZPA                   | `terraform destroy -target=...` or remove the HCL block and apply.                       |
| Re-import after re-org                        | `terraform import zpa_<resource>.<addr> <id>`.                                           |

Use the `removed` block (Terraform 1.7+) for a declarative, reviewable removal-from-state-only:

```hcl
removed {
  from = zpa_application_segment.legacy
  lifecycle {
    destroy = false   # leave it in ZPA
  }
}
```

---

## AppProtection Segment Disappears After an Update

Symptom: after an apply that touched a `zpa_application_segment` — even an unrelated attribute — Auto App Protection or AD Inspection is off, the per-domain AppProtection config is incomplete, and the segment is missing from the console's main Application Segments list.

Cause: enabling Auto App Protection or AD Inspection (e.g. in the Admin Portal) converts the segment into an inspection segment. `zpa_application_segment` has no inspection attributes, so its update disables them. Not a provider bug.

| Step | Action |
| ---- | ------ |
| 1 | Repair the segment in the console (reachable from its segment group), or uncheck the per-domain AppProtection box. |
| 2 | `terraform import` it into `zpa_application_segment_inspection`. |
| 3 | Remove it from `zpa_application_segment` with a `removed { lifecycle { destroy = false } }` block. |

✅ Manage AppProtection / AD Inspection only through `zpa_application_segment_inspection` — see [Resource Catalog: Inspection Segment](resource-catalog.md#inspection-segment-appprotection--ad-inspection).
❌ Toggling AppProtection in the console on a segment Terraform manages as `zpa_application_segment`.

## Slow Plans in Large Configurations

Cause: the provider paces requests to the documented ZPA limits (20 GET / 10 POST-PUT-DELETE per 10 s).

| Provider | Refresh of 3,600 application segments |
| -------- | ------------------------------------- |
| `< v4.4.13` | 3,600 GETs — at least 30 minutes |
| `v4.4.13`+ | 8 GETs — list endpoint, 500 per page |

From `v4.4.13`, list-based refresh covers application segments, application servers, segment, server, and app connector groups, and v1/v2 access, timeout, and forwarding rules. Applies still cost one write per changed resource.

- ✅ Upgrade to `v4.4.13`+.
- ✅ Routine changes: `terraform plan -refresh=false` (TFE / HCP Terraform: workspace variable `TF_CLI_ARGS_plan="-refresh=false"`); full refresh periodically.
- ✅ Configurations that keep growing: split into smaller workspaces (by segment group or application domain).
- ❌ Changing `-parallelism` in either direction.
- ❌ Zscaler Go SDK env vars (`ZSCALER_CLIENT_RATE_LIMIT_MAX_RETRIES`, `ZSCALER_CLIENT_REQUEST_TIMEOUT`) — ignored by the provider. See [Auth & Providers: Retries and Timeouts](auth-and-providers.md#retries-timeouts-and-rate-limits).

## Concurrent Policy Rule Writes

Symptom: `400 api.concurrent.access.error — Unable to modify the resource due to concurrent change requests`.

Cause: ZPA policy rule endpoints accept one write at a time. Before `v4.4.13`, v1 and v2 rule resources of the same policy type in one apply were not serialized against each other.

- ✅ Upgrade to `v4.4.13`+ (all policy rule writes share one lock).
- ✅ Below `v4.4.13`: apply v1 rules first (`-target`), then the rest.
- ❌ Several concurrent applies modifying policy rules.

---

## Quick Reference

| Problem                                            | First thing to try                                                                     |
| -------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Bool drift                                         | Upgrade provider to latest 4.x.                                                        |
| `RESOURCE_IN_USE` on destroy                       | Remove referencing policy rule first.                                                  |
| 404 on a resource that exists in console           | Check `microtenant_id` is consistent across HCL, state, and credential scope.          |
| 400 on policy rule create                          | Recheck operand `lhs`/`rhs`/`idp_id` against [Operand Reference](policy-rules.md#operand-reference). |
| `already exists` on apply                          | Rename or `terraform import`. Never `state rm` and retry with same name.               |
| Want to stop managing without deleting             | Use `removed { lifecycle { destroy = false } }`.                                       |
| Need to capture HTTP for support ticket            | `TF_LOG=DEBUG ZSCALER_SDK_VERBOSE=true ZSCALER_SDK_LOG=true terraform plan` and redact tokens. |
| AppProtection lost after an apply                  | Move the segment to `zpa_application_segment_inspection`.                              |
| Slow plan on a large configuration                 | Provider `v4.4.13`+; `-refresh=false` for routine plans; smaller workspaces.           |
| `api.concurrent.access.error` on a policy rule     | Provider `v4.4.13`+; one apply modifying policy rules at a time.                       |
