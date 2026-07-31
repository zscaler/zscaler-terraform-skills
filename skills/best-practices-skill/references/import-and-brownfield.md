# Import and Brownfield Adoption

Most tenants already have configuration built through the Admin Portal. Never advise hand-writing HCL to describe an existing tenant — Zscaler ships a supported CLI for this.

## Route First: `zscaler-terraformer`

[`zscaler-terraformer`](https://github.com/zscaler/zscaler-terraformer) authenticates with the same credentials the providers use, reads the live tenant, and emits both the Terraform configuration and the state, so the first `plan` after import should be empty.

| Command | Purpose |
|---------|---------|
| `zscaler-terraformer generate` | Emit `.tf` stanzas only |
| `zscaler-terraformer import` | Emit stanzas **and** the `terraform import` commands to populate state |

```bash
# Whole product
zscaler-terraformer import --resources "zia"
zscaler-terraformer import --resources "zpa"

# One resource type — recommend this shape
zscaler-terraformer import --resources "zia_firewall_filtering_rule"

# With namespacing and validation
zscaler-terraformer --prefix "prod" --validate --progress import --resources "zia"
```

| Flag | Effect |
|------|--------|
| `--resources` | Product (`zia`, `zpa`) or a single resource type |
| `--prefix` | Namespaces generated resource addresses |
| `--validate` | Runs `terraform validate` over the output |
| `--progress` / `--no-progress` | Progress reporting on large tenants |
| `--collect-logs` | Log capture for a support case |
| `--use_legacy_client=true` | Legacy API framework instead of OneAPI |

Credentials follow the providers exactly: OneAPI via `ZSCALER_CLIENT_ID` / `ZSCALER_CLIENT_SECRET` / `ZSCALER_VANITY_DOMAIN` (plus `ZSCALER_CUSTOMER_ID` for ZPA), or legacy per-product variables. Always recommend environment variables over CLI flags so secrets stay out of shell history.

## Scope Limits — State These When Asked

| Product | Tool support |
|---------|--------------|
| ZIA | Yes |
| ZPA | Yes |
| ZTC | **No** — hand-written HCL plus `terraform import` |
| ZCC | **No** — hand-written HCL plus `terraform import` |

Other limits worth surfacing unprompted:

- **Write-only values cannot be recovered.** Passwords, pre-shared keys, and API keys are never returned by the API, so they must be re-supplied from a secret store after import. This is the usual cause of a non-empty first plan.
- **Generated HCL is correct but not idiomatic.** Flat resources, API-derived names, no variables, no `for_each`. It is a starting point, not the long-term source of truth — refactor toward [Module Patterns](module-patterns.md) and [Coding Practices](coding-practices.md).
- Tested against Terraform 1.x.

## Recommended Sequence

1. Import one low-risk resource type (rule labels, IP destination groups) into a scratch workspace to validate credentials and output shape.
2. Run `plan` and confirm it is empty. Investigate any diff before continuing.
3. Refactor the generated HCL — `for_each` maps, variables, module boundaries.
4. Adopt one resource type per pull request to keep reviews meaningful and blast radius small.
5. Re-supply secrets, then plan again.

Keep the default parallelism throughout, including large initial imports — see [Anti-Patterns](anti-patterns.md).

## Single-Object Import

When the HCL already exists and only one object needs adopting, the provider's own import support is enough. Most ZIA resources accept the numeric ID **or** the object name; some are ID-only, so check the Registry page.

```bash
terraform import zia_url_filtering_rules.block_gambling 12345
terraform import zia_location_management.hq "HQ-Toronto"
```

## Never `state rm` to Unwind a Bad Import

`terraform state rm` leaves the object live in the tenant and untracked, so the next apply tries to create it again — typically failing with `DUPLICATE_ITEM`, or worse, silently producing a duplicate. Use `removed {}` (Terraform 1.7+) to stop managing without destroying:

```hcl
removed {
  from = zia_url_filtering_rules.block_gambling
  lifecycle { destroy = false }
}
```

The one defensible `state rm` is a **predefined rule** you want to stop managing, since Terraform cannot destroy it anyway.

## Post-Import Constraints That Still Apply

- **Activation.** Importing does not activate anything, but the first apply afterwards will need it. See the ZIA skill's activation reference.
- **One owner per rule type.** If an import splits a rule type across two states, both will fight over ordering. See [State Management](state-management.md).
- **Contiguous rule order.** Imported rules carry the tenant's existing order values; keep them contiguous and `>= 1` in the HCL you commit.

## Related

- [Anti-Patterns](anti-patterns.md) — `state rm`, parallelism, hardcoded IDs
- [Module Patterns](module-patterns.md) — where generated code should end up
- [State Management](state-management.md) — ownership boundaries
- [Versioning](versioning.md) — `moved {}` for post-import refactors
