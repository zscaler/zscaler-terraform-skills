# Coding Practices — Zscaler Terraform

HCL style, locals, looping, dynamic blocks, validation. Generic Terraform style applies; this reference focuses on the patterns that are particularly load-bearing for Zscaler resources.

## Decision Table — `count` vs `for_each` vs `dynamic`

| Goal                                                                | Use                                  | Why                                                       |
| ------------------------------------------------------------------- | ------------------------------------ | --------------------------------------------------------- |
| Conditionally create one resource (toggle)                          | `count = condition ? 1 : 0`          | Singleton on/off.                                         |
| Multiple named resources from a list                                | `for_each = toset(list)`             | Stable address per name on add/remove.                    |
| Multiple named resources from a map                                 | `for_each = map`                     | Named access (`each.key`, `each.value`).                  |
| Variable-length nested block (e.g. ZPA policy operands)             | `dynamic "operands"`                 | Block count comes from input, not static.                 |
| Always-one nested block                                             | Static block                         | `dynamic` adds noise without value.                       |
| List of N resources where order changes daily                        | **None** — restructure inputs as map | `count` over a list shifts every address on edit.         |

## Hard Rules

- ❌ `count = length(var.applications)` over a list of names — removing the middle entry shifts every downstream address.
- ❌ `for_each` over a value that's unknown at plan time (output of another resource that produces a computed list). Refactor to use a map keyed on inputs you do know.
- ❌ `dynamic` block where the block is always present exactly once.
- ❌ Hardcoded resource IDs (`segment_group_id = "72058304855457833"`). Use a data source or accept as a variable.
- ✅ `for_each = { for x in var.servers : x.name => x }` to convert a list to a map for stable addressing.
- ✅ `count = var.create_optional_resource ? 1 : 0` for the on/off toggle. Reference as `resource.foo.this[0].id` with a `try()` if conditional.

## Formatting

- `terraform fmt -recursive` runs in pre-commit and CI (`terraform fmt -check -recursive`).
- 2-space indentation. Don't fight `terraform fmt`.
- Block ordering inside a `resource`:
  1. Meta-arguments (`provider`, `count`, `for_each`, `depends_on`).
  2. Required arguments.
  3. Optional arguments.
  4. Nested blocks.
  5. `lifecycle {}`.

## Locals — When to Use

Use `locals {}` for:

- Computed values from variables (`prefix = "${var.environment}-${var.project}"`).
- Reshaping inputs (list → map for `for_each`, flatten nested structures).
- Reused expressions (don't repeat a 4-line expression in three resources).

```hcl
locals {
  prefix       = "${var.environment}-${var.project}"
  applications = { for app in var.applications_list : app.name => app }
  servers_flat = flatten([
    for app_key, app in var.applications : [
      for server in app.servers : {
        key      = "${app_key}-${server.name}"
        app_key  = app_key
        server   = server
      }
    ]
  ])
}
```

❌ Locals for trivial values that should be variables (`local.app_name = "my-app"`).
❌ Locals for renaming a variable cosmetically (`local.name = var.name`).

## Dynamic Blocks (ZPA Policy Operands Use Case)

```hcl
resource "zpa_policy_access_rule_v2" "this" {
  name   = var.rule_name
  action = var.action

  dynamic "conditions" {
    for_each = var.conditions
    content {
      operator = conditions.value.operator

      dynamic "operands" {
        for_each = conditions.value.operands
        content {
          object_type = operands.value.object_type
          lhs         = operands.value.lhs
          rhs         = operands.value.rhs
        }
      }
    }
  }
}
```

Use this shape when authoring complex ZPA policy modules. The double-`dynamic` reflects the policy schema (rule → conditions → operands).

## Variable Validation

Inline validation catches misuse at plan time, before any API call:

```hcl
variable "bypass_type" {
  description = "ZPA bypass mode: ALWAYS / NEVER / ON_NET."
  type        = string
  default     = "NEVER"

  validation {
    condition     = contains(["ALWAYS", "NEVER", "ON_NET"], var.bypass_type)
    error_message = "bypass_type must be ALWAYS, NEVER, or ON_NET."
  }
}

variable "tcp_port_ranges" {
  description = "Pairs [from, to, from, to, ...]."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.tcp_port_ranges) % 2 == 0
    error_message = "tcp_port_ranges must contain an even number of entries."
  }
}
```

Multi-variable validation goes in a `lifecycle.precondition`:

```hcl
resource "zpa_application_segment" "this" {
  # ...

  lifecycle {
    precondition {
      condition     = length(var.tcp_port_ranges) > 0 || length(var.udp_port_ranges) > 0
      error_message = "At least one of tcp_port_ranges or udp_port_ranges must be set."
    }
  }
}
```

## Dependency Management

- ✅ Implicit dependencies via reference: `segment_group_id = zpa_segment_group.this.id`.
- ✅ Explicit `depends_on` only when there's no direct attribute reference (e.g. activation depends on every rule).
- ❌ `depends_on = [...]` with resources you already reference — redundant noise.
- ❌ `depends_on` on a data source to "force" re-read each plan — use `terraform_data.trigger` if you genuinely need to invalidate.

## Optional Resources & Conditional References

```hcl
variable "create_inspection_profile" {
  type    = bool
  default = false
}

resource "zpa_inspection_profile" "optional" {
  count = var.create_inspection_profile ? 1 : 0

  name = "${var.app_name}-inspection"
}

resource "zpa_application_segment_inspection" "this" {
  count = var.create_inspection_profile ? 1 : 0

  inspection_app_id = zpa_inspection_profile.optional[0].id
}
```

Or use `try()` / `coalesce()` to consume the optional resource:

```hcl
locals {
  inspection_app_id = try(zpa_inspection_profile.optional[0].id, null)
}
```

## Provider Block Hygiene

- ❌ Provider blocks inside reusable modules.
- ❌ `provider "zpa" { client_secret = "literal-string" }` — see [Security & Compliance](security-and-compliance.md).
- ❌ `provider "zpa" {}` in the root with `client_id = var.client_id` on Terraform `< 1.11` — variable lands in state.
- ✅ Empty `provider "zpa" {}` in the root, all credentials sourced from CI env vars.
- ✅ Multi-cloud via `alias`:

```hcl
provider "zpa" {
  alias = "commercial"
}

provider "zpa" {
  alias = "gov"
  use_legacy_client = true
}

resource "zpa_application_segment" "in_gov" {
  provider = zpa.gov
  # ...
}
```

## Related

- [Variables and Outputs](variables-and-outputs.md) — typing, optional fields, sensitive handling.
- [Naming Conventions](naming-conventions.md) — local / variable / resource naming.
- [Anti-Patterns](anti-patterns.md) — full enumeration of mistakes to avoid.
