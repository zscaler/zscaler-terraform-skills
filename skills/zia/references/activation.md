# ZIA — Activation

ZIA changes are **draft** at the API level until activated. A successful `terraform apply` only writes draft state; it does not push policy to enforcement points.

## Decision Table — Pick the Activation Pattern

| Goal                                              | Use                                            | Tradeoff                                                                  |
| ------------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------- |
| Atomic per-apply activation in CI/CD              | `zia_activation_status` resource in HCL        | If activation fails, you have draft changes to roll back manually.        |
| Manual activation by a human after change review  | No activation resource in HCL                  | Human in the loop; risk of forgetting; OK for emergency / low-frequency.  |
| Periodic activation (batch nightly)               | Out-of-band cron / scheduled GH Action         | Decouples apply from activation; harder to reason about per-PR effects.   |

Recommendation for production: **manage `zia_activation_status` in HCL** and rely on Terraform's dependency graph to activate after every relevant change.

## Canonical Pattern

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

`status = "ACTIVE"` triggers the ZIA API's `/status/activate` endpoint, which promotes all draft policy changes to enforcement. It is essentially a "publish" button.

Other valid `status` values exist for special cases (e.g. `PENDING` for read-only check), but for write operations always set `"ACTIVE"`.

## CI/CD Wiring

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

These activate independently. A failure on one does not block the other (within Terraform's parallelism model).

## Common Pitfalls

| ❌ Pitfall                                                                                         | ✅ Fix                                                                                       |
| ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Apply succeeds, console shows draft changes, no enforcement.                                       | Add `zia_activation_status` with `depends_on`.                                              |
| Multiple `zia_activation_status` resources in one state.                                          | Collapse to one. Use `depends_on` to gate.                                                  |
| Forgot to update `depends_on` when adding a new rule resource — activation runs before the new rule's create. | Always add new policy resources to the activation `depends_on` list.                        |
| Manual activation in console + `zia_activation_status` in HCL → race conditions.                  | Pick one: either Terraform owns activation or humans do.                                    |
| Failed activation leaves draft changes; next apply seems to do nothing.                            | Re-apply — Terraform will retry the activation. Inspect the console to confirm.             |
