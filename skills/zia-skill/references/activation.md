# ZIA — Activation

ZIA changes are **draft** at the API level until activated. A successful `terraform apply` only writes draft state; it does not push policy to enforcement points.

**Activation is tenant-wide, not per-resource.** One call to the activation endpoint publishes every pending change in the tenant. No configuration ever needs more than one activation call per run — this single fact determines which pattern is correct.

## Decision Table — Pick the Activation Pattern

| Goal                                                        | Use                                                          | Tradeoff                                                                                          |
| ----------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| Any pipeline, and any config built from modules             | **Out-of-band `ziaActivator` CLI after apply** (recommended) | Activation lives in the pipeline, not the graph, so it is not visible in `terraform plan`.        |
| Single flat config that owns all its resources              | `zia_activation_status` resource in HCL                      | `depends_on` must list **every** resource; anything omitted may be applied after activation.       |
| **Several states against one tenant**                       | **Out-of-band `ziaActivator` once, after the last apply**    | Applies must be serialised on the tenant. Per-state activation does not work — it queues behind every other session. [Details](#several-states-one-tenant) |
| Manual activation by a human after change review            | No activation in HCL; activate in the console                | Human in the loop; risk of forgetting; OK for emergency / low-frequency.                          |
| Activation during the apply itself                          | `ZIA_ACTIVATION=true` — **discouraged, avoid**               | Fires one call per resource change against a 10/min, 40/hr endpoint. Legacy; may be removed.       |

Recommendation for production: **run the out-of-band `ziaActivator` binary as a dedicated pipeline stage after `terraform apply`.** It issues exactly one activation call, keeps timing under explicit control, and stays correct as the configuration grows because it does not depend on the resource graph.

```bash
make build13 && sudo make ziaActivator   # build once
terraform apply && ziaActivator          # activate once, after apply
```

Use `zia_activation_status` only where a single flat configuration owns every resource it must activate. Do not reach for `ZIA_ACTIVATION`.

## Canonical Pattern — `zia_activation_status` (flat configs only)

```hcl
resource "zia_url_filtering_rules" "block_gambling" {
  name            = "Block Gambling"
  state           = "ENABLED"
  action          = "BLOCK"
  order           = 1
  url_categories  = ["GAMBLING"]
  protocols       = ["ANY_RULE"]
  request_methods = ["CONNECT", "DELETE", "GET", "HEAD", "OPTIONS", "OTHER", "POST", "PUT", "TRACE"]
}

resource "zia_firewall_filtering_rule" "allow_engineering" {
  name        = "Allow Engineering"
  state       = "ENABLED"
  action      = "ALLOW"
  order       = 1
  enable_full_logging = true
  departments {
    id = [data.zia_department_management.engineering.id]
  }
}

resource "zia_activation_status" "this" {
  status = "ACTIVE"

  depends_on = [
    zia_url_filtering_rules.block_gambling,
    zia_firewall_filtering_rule.allow_engineering,
  ]
}
```

Rules:

- ✅ One `zia_activation_status` per Terraform configuration / state file.
- ✅ List **every** policy-affecting resource in `depends_on` so activation always runs after changes.
- ✅ Use the data source `data "zia_activation_status" "x" {}` for read-only inspection.
- ❌ Do not create multiple `zia_activation_status` resources in the same state — they will fight each other.

## Single `depends_on` List Is Tedious — `for_each` Helper

For configs with many rules, gather them programmatically:

```hcl
locals {
  policy_rules = concat(
    [for r in values(zia_url_filtering_rules.block) : r],
    [for r in values(zia_firewall_filtering_rule.allow) : r],
  )
}

resource "zia_activation_status" "this" {
  status = "ACTIVE"
  depends_on = local.policy_rules
}
```

This works because `depends_on` accepts resource references. Just make sure the list is built only from policy resources — adding non-policy resources adds nothing harmful but bloats the dependency graph.

## What Activation Actually Does

`status = "ACTIVE"` triggers the ZIA API's `/status/activate` endpoint, which promotes all draft policy changes to enforcement. It is essentially a "publish" button, and it publishes the whole tenant's pending state in one call.

Other valid `status` values exist for special cases (e.g. `PENDING` for read-only check), but for write operations always set `"ACTIVE"`.

**The endpoint is tightly rate limited: 10 POST requests per minute and 40 per hour.** This is why per-resource activation is the wrong model — one call per run sits comfortably inside the budget, while one call per resource does not.

### Activation Queues Behind Other Editors

Activation is not only tenant-wide, it is also not guaranteed to publish immediately. Per [Saving and Activating Changes](https://help.zscaler.com/legacy-zia/saving-and-activating-changes-admin-portal):

- If no other administrator is editing, the change is pushed to the Central Authority straight away.
- If **any** other administrator or API session has unactivated changes, the call is placed in **`Activation Queued`** and stays there until every editing administrator has activated. A queued activation **cannot be cancelled**.
- Super administrators can **Force Activate**, which immediately pushes *all* saved changes in the tenant — including work that is still mid-deployment.
- The portal's **Queued Activations** list names the administrators with pending activations. It is the fastest way to answer "we activated, so why is nothing live?"

This is why "activate at the end of each state" is not a valid design for a tenant with several configurations: each call waits for every other session, so publication timing is set by whichever run finishes last, and when the queue clears, pending changes from an in-flight or failed run are published too. For rule-based resources a partially created rule set can go live with incomplete ordering.

## Why `ZIA_ACTIVATION` Is Discouraged

Setting `ZIA_ACTIVATION=true` makes the provider activate in-flight, after every create, update, and delete. Because activation is tenant-wide, all of those calls except the last are redundant — each one publishes the same pending state the next one will publish again.

Against a 10/min and 40/hr limit, a configuration with a few dozen resources exhausts the hourly budget during a single apply. The run does not fail (rate-limited requests are retried automatically after the interval the API reports), but it slows to the pace of the activation limit rather than the pace of the actual work. Treat the variable as legacy; it may be removed in a future provider release.

## API Session Timeout — the Long-Run Trap

Session lifetime is governed by the API session timeout in Advanced Settings. Range **5 to 20 minutes, default 5** ([Configuring Advanced Settings](https://help.zscaler.com/zia/configuring-advanced-settings#session-timeout)).

It is adjustable two ways, and users often only know about the second:

- **ZIA Admin Portal** — **Administration > Advanced Settings** → **API Session Timeout Duration (In Minutes)**, under *Admin Portal Session Timeout*. Distinct from the UI session timeout field directly above it, which does not affect API sessions.
- **Terraform** — the `api_session_timeout` attribute on `zia_advanced_settings`.

**The platform activates pending changes when a session ends**, including when the session ends by timing out rather than by an explicit logout. Consequences for a run longer than the timeout:

- Pending changes are activated part-way through the apply, before the remaining resources have been written.
- The provider re-authenticates and the run continues, so there is no error — activation simply happened at a moment nobody chose.

A 30-minute apply against the default 5-minute timeout crosses this boundary several times. Mitigate by raising the timeout to its maximum:

```hcl
resource "zia_advanced_settings" "this" {
  api_session_timeout = 20
  # ... remaining attributes
}
```

This reduces how often a run crosses a session boundary but cannot eliminate it — the behaviour is native to the platform and the provider cannot override it. 20 minutes is a ceiling, not a guarantee, so the durable fix is to keep runs short by splitting large configurations across smaller states.

Do not diagnose this as a provider bug. If a user reports "changes activated before the apply finished" or "we never ran activation but it activated anyway", check the run duration against the configured API session timeout first, and confirm which of the two Advanced Settings fields they actually changed — raising the *UI* session timeout has no effect on API sessions.

**ZTC has no equivalent setting.** Where ZIA allows 5–20 minutes, ZTC exposes no way to adjust the API session lifetime at all, through the provider or the tenant ([Zscaler API documentation](https://help.zscaler.com/legacy-apis/configuring-postman-rest-api-client-3)). For ZTC, short runs are the only mitigation — do not suggest raising a timeout that does not exist.

## CI/CD Wiring

Recommended shape — activation as its own stage, so it runs once and its failure is distinguishable from an apply failure:

```yaml
- run: terraform plan -out=tfplan
- run: terraform apply -auto-approve tfplan
- name: Activate ZIA configuration
  run: ziaActivator
```

If instead the configuration manages activation in HCL, gate on its presence in the plan:

```yaml
- run: terraform plan -out=tfplan
- run: terraform show -no-color tfplan > tfplan.txt
- name: Check activation is in plan
  run: |
    if ! grep -q 'zia_activation_status.this' tfplan.txt; then
      echo '::warning::No activation in plan — changes will not be enforced.'
    fi
- run: terraform apply -auto-approve tfplan
```

This warns (not fails) if a plan modifies policy without an activation update. Tune the gate to your risk tolerance.

## Activation Failures

If `zia_activation_status` itself fails (`apply` errors out partway through):

1. **Check the error**. Most often it's a transient API issue — re-run `terraform apply`.
2. **Inspect the console**. The ZIA console shows pending draft changes if activation failed.
3. **If the underlying rule write succeeded but activation failed**, your apply is in a half-applied state. Re-running `terraform apply` will skip the already-applied rules and retry only activation.
4. **Never `terraform state rm zia_activation_status.this`** to "skip" it. It's a managed resource and removing it from state means subsequent plans won't activate at all.

## Multi-Tenant Activation

Each `provider "zia"` alias has its own activation lifecycle:

```hcl
resource "zia_activation_status" "tenant_a" {
  provider = zia.tenant_a
  status   = "ACTIVE"
  depends_on = [/* tenant_a resources */]
}

resource "zia_activation_status" "tenant_b" {
  provider = zia.tenant_b
  status   = "ACTIVE"
  depends_on = [/* tenant_b resources */]
}
```

These activate independently, because each tenant has its own write lock and activation queue. A failure on one does not block the other.

The reverse does **not** hold: several states pointing at the *same* tenant do not activate independently — see below.

## Several States, One Tenant

A common layout is one workspace per ZIA resource type, all targeting a single tenant. Splitting state that way is fine; applying those states **concurrently** is not, and activating per state does not work.

| Behaviour | Consequence for concurrent runs |
| --- | --- |
| Every write must acquire a **tenant-wide write lock** ("org barrier") | Concurrent runs contend; losers get `EDIT_LOCK_NOT_AVAILABLE`, `Resource Access Blocked`, or `Failed during enter Org barrier`. The provider retries, so it looks like a slow run — until retries are exhausted and the apply dies part-way, leaving partial state. |
| Activation is tenant-wide and **queues** behind other editors | A per-state activation waits for every other session, then publishes their pending work too, including from a run still in flight. |

Recommend this shape:

- ✅ Keep the state split — this is not an argument for one monolithic ZIA state.
- ✅ Run `plan` concurrently; reads do not take the write lock.
- ✅ Serialise `apply` with a CI concurrency key on the **tenant** (not the repo, workspace, or state path).
- ✅ Run `ziaActivator` **once**, after the final apply.
- ❌ Do not activate per state, and do not put a `zia_activation_status` resource in each state.
- ❌ Do not lower `-parallelism` to relieve contention — it does not reduce the number of competing runs, and the longer runtime increases exposure to the session-timeout activation described above.
- ❌ Do not cancel an in-flight apply so another can start; that is itself a cause of partial state.

Note this is **separate** from the rule-ordering rule that all rules of one type need one owner. That is about layout; this is about execution. States managing entirely disjoint resource types still share one write lock and one activation queue.

If genuinely parallel execution is required, only a separate tenant provides it.

## Common Pitfalls

| ❌ Pitfall                                                                                         | ✅ Fix                                                                                       |
| ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Apply succeeds, console shows draft changes, no enforcement.                                       | Add an activation step — `ziaActivator` after apply, or `zia_activation_status` with `depends_on`. |
| Multiple `zia_activation_status` resources in one state.                                          | Collapse to one. Activation is tenant-wide; more than one is always redundant.               |
| Forgot to update `depends_on` when adding a new rule resource — activation runs before the new rule's create. | Move to the out-of-band `ziaActivator`, which cannot fall out of step with the graph.        |
| `ZIA_ACTIVATION=true` set in a pipeline; applies get progressively slower.                        | Unset it and activate once with `ziaActivator`. The 10/min, 40/hr endpoint limit is being hit. |
| Manual activation in console + activation in HCL → race conditions.                               | Pick one: either the pipeline owns activation or humans do.                                  |
| Failed activation leaves draft changes; next apply seems to do nothing.                            | Re-apply — Terraform will retry the activation. Inspect the console to confirm.             |
| Changes activated mid-apply, or activated with no activation step at all, on a long run.          | Not a bug. The session hit `api_session_timeout` and the platform activates on session end. Raise it to 20 and shorten runs. |
| One `zia_activation_status` per state, several states on one tenant.                              | Activation has no per-state scope and queues behind other editors. Activate once, after the last apply. |
| Several states applying concurrently to one tenant; `EDIT_LOCK_NOT_AVAILABLE` or a very slow run. | Serialise `apply` on the tenant. Plans can stay parallel. Do **not** lower `-parallelism`. |
| Activation reported success but nothing went live.                                                | Another session was still editing, so the activation is queued. Check **Queued Activations** in the portal; serialise applies. |
