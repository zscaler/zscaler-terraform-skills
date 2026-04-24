# Variables and Outputs — Zscaler Terraform

Variable typing, validation, sensitive handling, and outputs.

## Decision Table — Variable Shape

| Input shape                                     | Type                                                  | Example                                                                                                |
| ----------------------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Single value                                    | `string` / `number` / `bool`                          | `name`, `enabled`, `idle_timeout`                                                                      |
| Homogeneous list                                | `list(string)`, `list(number)`                        | `domain_names`, `tcp_port_ranges`                                                                      |
| Unique values, no order                         | `set(string)`                                         | `allowed_country_codes`                                                                                |
| Key/value lookup of strings                     | `map(string)`                                         | `tags`                                                                                                 |
| Two related fields per item                     | `list(object({...}))` or `map(object({...}))`         | `policy_conditions`                                                                                    |
| Many objects with stable keys                   | `map(object({...}))` (with `optional()`)              | `applications`, `servers`, `url_filtering_rules`                                                       |
| Truly heterogeneous structure                   | `any` (last resort, no validation)                    | `custom_attributes`                                                                                    |

## Hard Rules

- ❌ Two **parallel lists** of related data (`server_names` + `server_addresses`). Use one `map(object({...}))`.
- ❌ `type = string` for a JSON-encoded blob. Use the actual structured type so the schema is checkable.
- ❌ `type = any` unless you genuinely cannot constrain the shape.
- ❌ `default = ""` for a required identifier (treated as a real value, not "missing").
- ❌ Defaults for deployment-specific values (names, customer IDs, tenant IDs).
- ✅ `optional(<type>, <default>)` (Terraform 1.3+) for object fields with defaults.
- ✅ `default = null` for a truly optional field that downstream code conditionally consumes.
- ✅ `sensitive = true` for any credential, key, or value that should not appear in CLI output.

## Description Quality

- ❌ `description = "Bypass type"` (just restates the variable name).
- ✅ `description = "ZPA bypass mode: NEVER (always use ZPA), ON_NET (bypass when on corp network), ALWAYS (always bypass — not recommended for prod)."`

A good description explains:

1. What the value controls.
2. Allowed values (if a fixed enum) or shape (if structured).
3. Notable defaults or footguns.

## Object Types with Optional Fields (1.3+)

```hcl
variable "applications" {
  description = "Map of application configurations keyed by application name."
  type = map(object({
    domain_names    = list(string)
    tcp_port_ranges = optional(list(string), ["443", "443"])
    udp_port_ranges = optional(list(string), [])
    enabled         = optional(bool, true)
    description     = optional(string, "")
  }))
  default = {}
}
```

Pattern:

- Required fields have no `optional()`.
- Optional fields use `optional(<type>, <default>)` so callers can omit them.
- Default for the entire variable is `{}` (or `[]`) so the module is opt-in.

## Validation Blocks

### Enum

```hcl
variable "bypass_type" {
  type    = string
  default = "NEVER"

  validation {
    condition     = contains(["ALWAYS", "NEVER", "ON_NET"], var.bypass_type)
    error_message = "bypass_type must be ALWAYS, NEVER, or ON_NET."
  }
}
```

### List shape

```hcl
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

### Per-element validation

```hcl
variable "domain_names" {
  type = list(string)

  validation {
    condition     = length(var.domain_names) > 0
    error_message = "At least one domain_name must be specified."
  }

  validation {
    condition = alltrue([
      for d in var.domain_names :
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$", d)) || can(regex("^\\*\\.", d))
    ])
    error_message = "Each domain_name must be a valid hostname or wildcard (*.example.com)."
  }
}
```

### Cross-variable validation (use `lifecycle.precondition`)

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

Variable-validation blocks can only reference the single variable they belong to. Multi-variable checks belong in `lifecycle.precondition`.

## Sensitive Variables — Read [Security & Compliance](security-and-compliance.md) First

Quick rules:

- ❌ Credentials in `variable` blocks on Terraform `< 1.11` — they land in state, even with `sensitive = true`.
- ❌ Credentials in `terraform.tfvars` checked into git.
- ✅ Source from CI env vars; the provider reads them directly (no Terraform variable in the path).
- ✅ On Terraform `1.11+`: use `ephemeral = true` variables and `*_wo` write-only attributes when the provider exposes them.

```hcl
# Terraform 1.11+
variable "zia_api_key_wo" {
  type      = string
  ephemeral = true
}

provider "zia" {
  api_key_wo = var.zia_api_key_wo  # if/when the provider exposes the *_wo variant
}
```

For values that are not credentials but should be redacted from logs (provisioning keys, one-time tokens):

```hcl
output "provisioning_key" {
  description = "App connector provisioning key — record once, never log."
  value       = zpa_provisioning_key.this.provisioning_key
  sensitive   = true
}
```

## Defaults — When and When Not

| Use a default                            | Don't use a default                        |
| ---------------------------------------- | ------------------------------------------ |
| Common configuration value (`enabled = true`) | Deployment-specific (names, IDs, tenants)   |
| Feature flag with a typical setting (`bypass_type = "NEVER"`) | Required fields with no sensible fallback   |
| Optional enhancement off-by-default       | Anything that could silently change behavior |
| `null` for "do nothing" optional fields   | Empty string `""` as a stand-in for missing |

## Output Design

### Standard outputs every module exposes

```hcl
output "id" {
  description = "ID of the primary resource."
  value       = zpa_application_segment.this.id
}

output "name" {
  description = "Name of the primary resource."
  value       = zpa_application_segment.this.name
}
```

### `for_each` collections — return a keyed map

```hcl
output "application_ids" {
  description = "Map of application names to their ZPA IDs."
  value       = { for k, r in zpa_application_segment.apps : k => r.id }
}

output "application_names" {
  description = "List of created application portal names."
  value       = [for r in zpa_application_segment.apps : r.name]
}
```

### Selective structured output for downstream consumers

```hcl
output "application_info" {
  description = "Subset of application attributes needed by downstream modules."
  value = {
    id               = zpa_application_segment.this.id
    name             = zpa_application_segment.this.name
    enabled          = zpa_application_segment.this.enabled
    segment_group_id = zpa_application_segment.this.segment_group_id
    domain_names     = zpa_application_segment.this.domain_names
  }
}
```

### Hard rules

- ❌ `output "all" { value = zpa_application_segment.this }` — exposes every attribute, leaks abstraction, churns when the schema changes.
- ❌ Outputs containing credentials or any field marked `sensitive` upstream without `sensitive = true`.
- ❌ Outputs called `id` / `name` at the **root** module level (too ambiguous; use resource-prefixed names).
- ✅ Selective, named outputs. Each output earns its place by being something a downstream consumer actually needs.
- ✅ Mirror variable names where applicable (`segment_group_name` in → `segment_group_name` out).

## Zscaler-Flavored Variable Templates

Quick-paste templates for common Zscaler resource modules. Copy, then trim.

### ZPA application segment input

```hcl
variable "application_config" {
  description = "ZPA application segment configuration."
  type = object({
    name             = string
    description      = optional(string, "")
    enabled          = optional(bool, true)
    domain_names     = list(string)
    tcp_port_ranges  = optional(list(string), ["443", "443"])
    udp_port_ranges  = optional(list(string), [])
    health_reporting = optional(string, "ON_ACCESS")
    bypass_type      = optional(string, "NEVER")
    is_cname_enabled = optional(bool, true)
  })
}
```

### ZPA access policy input

```hcl
variable "access_policy" {
  description = "ZPA access policy rule."
  type = object({
    name        = string
    description = optional(string, "")
    action      = string  # ALLOW / DENY
    rule_order  = optional(number)
    conditions = optional(list(object({
      operator = string  # AND / OR
      operands = list(object({
        object_type = string
        lhs         = string
        rhs         = string
      }))
    })), [])
  })

  validation {
    condition     = contains(["ALLOW", "DENY"], var.access_policy.action)
    error_message = "access_policy.action must be ALLOW or DENY."
  }
}
```

### ZIA URL filtering rule(s) input

```hcl
variable "url_filtering_rules" {
  description = "Map of ZIA URL filtering rules keyed by rule name."
  type = map(object({
    description    = optional(string, "")
    state          = optional(string, "ENABLED")
    action         = string  # ALLOW / CAUTION / BLOCK
    order          = number
    url_categories = optional(list(string), [])
    protocols      = optional(list(string), ["ANY_RULE"])
    locations      = optional(list(string), [])
    groups         = optional(list(string), [])
    departments    = optional(list(string), [])
    users          = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, rule in var.url_filtering_rules :
      contains(["ALLOW", "CAUTION", "BLOCK"], rule.action)
    ])
    error_message = "Each url_filtering_rules[*].action must be ALLOW, CAUTION, or BLOCK."
  }
}
```

## Related

- [Coding Practices](coding-practices.md) — variable usage in resources.
- [Naming Conventions](naming-conventions.md) — variable / output naming.
- [Security & Compliance](security-and-compliance.md) — sensitive value handling.
