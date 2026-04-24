# Naming Conventions — Zscaler Terraform

Names exist in two namespaces — Terraform identifiers (in code/state) and Zscaler portal labels (visible in console). They follow different rules.

## Summary Table

| Element                    | Convention              | Example                                     |
| -------------------------- | ----------------------- | ------------------------------------------- |
| Terraform resource address | `snake_case`, singular  | `resource "zpa_application_segment" "crm"` |
| Zscaler portal name        | `kebab-case`, descriptive | `name = "prod-crm-api"`                    |
| Variable                   | `snake_case`            | `segment_group_id`                          |
| Output                     | `snake_case`            | `application_id`                            |
| Local                      | `snake_case`            | `resource_prefix`                           |
| Module directory           | kebab-case              | `zpa-application`                           |
| File                       | `snake_case.tf`         | `segment_group.tf`                          |

## Terraform Resource Addresses

Names that appear in `terraform state list` output. Optimize for **purpose-recall**: a maintainer reading the state should be able to tell what a resource is for from its address alone.

- ❌ `resource "zpa_application_segment" "this"` when there are siblings (every team uses `this` → no info).
- ❌ `resource "zpa_application_segment" "main"` (same problem).
- ❌ `resource "zpa_application_segment" "app1"` / `app2` / `app3` (no semantic content).
- ✅ `resource "zpa_application_segment" "crm_finance"` (names the **intent**).
- ✅ Reserve `"this"` for genuine **module-internal singletons** (e.g. `resource "zia_activation_status" "this"`).
- ✅ For `for_each`, use the plural noun: `resource "zpa_application_segment" "applications"`.

## Zscaler Portal Names (the `name` Attribute)

These appear in the Zscaler console. Optimize for **operator-recognizability**.

| Resource type             | Pattern                                                | Example                                         |
| ------------------------- | ------------------------------------------------------ | ----------------------------------------------- |
| ZPA application segment   | `<env>-<application>-<component>`                       | `prod-crm-api`                                  |
| ZPA segment group         | `<env>-<grouping>-sg`                                   | `prod-customer-facing-sg`                       |
| ZPA server group          | `<env>-<application>-servers`                           | `prod-webapp-servers`                           |
| ZPA access policy rule    | `<Action>-<Subject>-<Scope>`                            | `Allow-Engineering-Internal-Apps`               |
| ZIA URL filtering rule    | `<Action>-<Category>-<Scope>`                           | `Block-Gambling-All-Users`                      |
| ZIA firewall rule         | `FW-<Action>-<Protocol>-<Destination>`                  | `FW-Allow-HTTPS-Internal`                       |
| ZIA location              | `<Region>-<Site>`                                       | `us-east-headquarters`                          |
| ZTC location template     | `<Region>-<Type>-template`                              | `apac-branch-template`                          |
| ZTC traffic forwarding    | `TF-<Action>-<Destination>`                             | `TF-Forward-Internal-Traffic`                   |

❌ Spaces in portal names that cause CSV/log parsing issues downstream — prefer hyphens.
❌ Inconsistent casing across rules of the same type — pick one (Title-Case or kebab-case) per rule type and stick with it.
✅ Embed environment + project context so a portal admin can tell what a rule is for without opening it.
✅ Drive portal names from a `local.prefix = "${var.environment}-${var.project}"` so renames are one-line changes.

## Variable Naming

| Pattern                            | Indicates                | Example                          |
| ---------------------------------- | ------------------------ | -------------------------------- |
| `*_enabled`, `is_*`, `enable_*`    | Boolean (positive sense) | `enabled`, `is_cname_enabled`    |
| `*_id`, `*_ids`                    | Resource identifier(s)   | `segment_group_id`, `connector_group_ids` |
| `*_name`, `*_names`                | String name(s)           | `app_name`, `domain_names`       |
| Plural noun                        | List or map              | `applications`, `servers`        |
| `*_count`, `*_timeout`             | Number                   | `idle_timeout`                   |
| `*_config`                         | Object/map               | `application_config`             |

Rules:

- ❌ Negative-sense booleans (`disabled`, `not_enabled`) — invert the default in code, name the variable positively.
- ❌ Abbreviated names without context (`sg_id`, `acg_ids`, `ht`).
- ❌ Variables called `id` or `name` at the root level — too ambiguous unless inside a single-purpose module.
- ✅ Group related variables with shared prefixes (`network_*`, `health_*`, `server_*`).
- ✅ Suffix IDs with `_id` / `_ids` so callers know they're identifiers, not names.

## Output Naming

Outputs mirror the variables they correspond to where applicable.

```hcl
variable "segment_group_name" { type = string }

output "segment_group_id"   { value = zpa_segment_group.this.id }
output "segment_group_name" { value = zpa_segment_group.this.name }
```

For `for_each` resources, return a map keyed by the input key:

```hcl
output "application_ids" {
  description = "Map of application names to their ZPA IDs."
  value       = { for k, r in zpa_application_segment.apps : k => r.id }
}
```

❌ Outputs called `id` / `name` at the **root** module level (use the resource-prefixed form: `application_id`).
❌ Outputs that expose the entire resource (`output "app" { value = zpa_application_segment.this }`).
✅ Selective outputs that name what they expose (`application_id`, `application_name`, `segment_group_id`).
✅ For sensitive values (provisioning keys, OTPs): `sensitive = true`.

## Local Naming

```hcl
locals {
  prefix         = "${var.environment}-${var.project}"
  applications   = { for app in var.applications_list : app.name => app }
  servers_flat   = flatten([...])
  default_tags   = { Environment = var.environment, ManagedBy = "terraform" }
  effective_tags = merge(local.default_tags, var.custom_tags)
}
```

❌ Locals named after their type (`local.list`, `local.map`) — name them after their **purpose**.
✅ Group locals by purpose (naming, computed config, tags) within the `locals {}` block.

## Module Naming

Local modules: kebab-case directory name, prefix with the provider.

```hcl
module "zpa_application" {
  source = "./modules/zpa-application"
}

module "zia_url_filtering" {
  source = "./modules/zia-url-filtering"
}
```

Module **instance** names match the module's purpose:

- Single instance: name by purpose (`module "production_app"`).
- `for_each`: plural (`module "applications"`).
- Multi-environment in one config: include environment (`module "prod_policies"`, `module "staging_policies"`).

## File Naming

Standard files (don't rename):

| File             | Purpose                                                         |
| ---------------- | --------------------------------------------------------------- |
| `main.tf`        | Primary resources (or module composition).                       |
| `variables.tf`   | Input variable declarations.                                     |
| `outputs.tf`     | Output declarations.                                             |
| `versions.tf`    | `required_version` + `required_providers`.                       |
| `providers.tf`   | Provider blocks (root modules **only**).                         |
| `locals.tf`      | Local values.                                                    |
| `data.tf`        | Data sources.                                                    |

For larger modules, split by resource family:

```text
modules/zpa-complete/
├── main.tf              # Module composition
├── segment_group.tf     # zpa_segment_group resources
├── server_group.tf      # zpa_server_group + zpa_application_server resources
├── application.tf       # zpa_application_segment resources
├── policy.tf            # zpa_policy_* resources
├── variables.tf
├── outputs.tf
└── versions.tf
```

❌ One giant `main.tf` over ~300 lines — split by family.
❌ Files named after the team or author (`bobs_rules.tf`).
✅ File names match the resource family they contain (`segment_group.tf`).

## Cross-Provider Consistency

When resources span providers (e.g. ZPA app referenced by a ZIA gateway), drive both names from the same prefix so the relationship is visible in both consoles:

```hcl
locals {
  base_name = "${var.environment}-${var.project}"
}

resource "zpa_application_segment" "app" {
  name = "${local.base_name}-app"
}

resource "zia_forwarding_control_zpa_gateway" "gateway" {
  name = "${local.base_name}-zpa-gateway"
}
```

## Related

- [Module Patterns](module-patterns.md) — module directory naming.
- [Variables and Outputs](variables-and-outputs.md) — variable typing.
- [Coding Practices](coding-practices.md) — locals, formatting.
