# Module Patterns — Zscaler Terraform

Module shape, composition, and boundaries for Zscaler-Terraform repos.

## Decision Table — What Kind of Module?

| Goal                                                    | Use                                          | Example                                                                                |
| ------------------------------------------------------- | -------------------------------------------- | -------------------------------------------------------------------------------------- |
| Group of resources always created together              | **Resource module**                          | ZPA segment_group + server_group + application_segment for one app                      |
| All policy rules of one product for one tenant          | **Infrastructure module**                    | "All ZIA URL filtering rules for prod tenant"                                           |
| Per-environment top-level wiring                        | **Composition (root) module**                | `environments/prod/zpa/`, `environments/prod/zia/`                                      |
| Internal helper for one parent module                   | **Nested module** (`modules/<sub>/`)          | `modules/zpa-full-application/modules/segment-group/`                                  |
| One-off glue between two existing modules               | **Inline in root**, no module                | Don't create a module for 5 lines of cross-state references                             |

## Required Files (Every Module)

```text
my-module/
├── main.tf           # Primary resources
├── variables.tf      # Typed inputs with descriptions and validation
├── outputs.tf        # Exposed values for consumers
├── versions.tf       # required_version + required_providers (NO provider block)
└── README.md         # Usage + input/output table
```

Optional but common:

```text
├── locals.tf         # Computed/transformed values
├── data.tf           # Data sources
└── examples/         # Runnable examples
    ├── basic/
    └── complete/
```

❌ Reusable modules with `provider` blocks. The root composes providers; modules consume them.
❌ Resources spread across `main.tf` only when the file exceeds ~300 lines — split by resource family then.
✅ For complex modules, split: `segment_group.tf`, `server_group.tf`, `applications.tf`, `policies.tf`.

## Module Boundary Rules

The boundary is **purpose**, not product. Most single-purpose modules happen to touch one product, but a module implementing a feature that genuinely spans two products legitimately declares two providers.

- ❌ One module that bundles *unrelated* `zia_*` + `zpa_*` + `ztc_*` resources — different lifecycles, different activation, different tenants likely.
- ❌ A "kitchen-sink" Zscaler module that orchestrates every product feature.
- ✅ One module = one logical grouping created and destroyed together.
- ✅ Compose multiple focused modules in a root config.
- ✅ Multiple providers in one module **when one feature requires it** — declare both in `required_providers`, configure neither.

### Legitimate cross-product modules

Some ZIA resources are defined by identifiers that only the ZPA provider can supply, so a module implementing that integration needs both:

| Feature | ZIA resource | Needs from ZPA |
| --- | --- | --- |
| IP Source Anchoring | `zia_forwarding_control_zpa_gateway` | `external_id` of a server group and application segments (`zpa_server_group` / `zpa_application_segment`) |
| Forwarding to ZPA | `zia_forwarding_control_rule` (`forward_method = "ZPA"`) | the gateway above |

```hcl
# modules/zia-zpa-source-ip-anchoring/versions.tf — one purpose, two providers
terraform {
  required_providers {
    zia = { source = "zscaler/zia", version = "~> 4.0" }
    zpa = { source = "zscaler/zpa", version = "~> 4.0" }
  }
}
# no provider blocks — the root authenticates both tenants
```

The test: can you describe the module in one sentence without using the word "and"? If yes, the provider count does not matter.

❌ Splitting a cross-product feature into two modules purely to satisfy "one product per module" — you end up passing opaque IDs between them for no benefit.

Common naming for module directories: `zpa-application`, `zia-url-filtering`, `zia-zpa-source-ip-anchoring`, `ztc-traffic-forwarding`, `zcc-trusted-network`. Kebab-case, named for what the module does.

## Composition Pattern (Root Module)

```hcl
# environments/prod/zpa/main.tf

module "platform" {
  source = "../../../modules/zpa-platform"

  segment_group_name = "prod-internal-apps"
  connector_group_id = data.zpa_app_connector_group.prod.id
}

module "applications" {
  source   = "../../../modules/zpa-application"
  for_each = var.applications

  name             = each.key
  domain_names     = each.value.domains
  tcp_port_ranges  = each.value.ports
  segment_group_id = module.platform.segment_group_id
  server_group_id  = module.platform.server_group_id
}
```

Rules:

- ❌ Module passes secrets between modules (`client_secret = module.auth.secret`). Secrets come from CI env vars, not module outputs.
- ❌ Modules calling other modules **as siblings** in the root — that's composition, not nesting.
- ✅ Reference outputs (`module.platform.segment_group_id`) — Terraform infers ordering.
- ✅ Use `for_each` over a `map` of inputs to instance multiple module copies.

## Nested Modules (`modules/<name>/`)

When a module is internal to another module, ship it under `modules/<name>/` next to the parent's `main.tf`. Use only when:

1. The component has standalone value (could one day be promoted to a top-level module).
2. The logic is complex enough to warrant isolation.
3. The component might be reused by sibling parent modules.

Otherwise, keep the logic inline in the parent module's `main.tf`. Don't nest "for the sake of structure."

## `examples/` Directory

Every reusable module ships at least one runnable example.

```text
examples/
├── basic/                      # Smallest config that runs
│   ├── main.tf                  # source = "../../"
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── README.md
└── complete/                   # Every supported variable set
    ├── main.tf
    └── ...
```

Rules:

- ❌ Examples that won't `terraform plan` cleanly with the example tfvars.
- ❌ Examples that depend on hardcoded IDs from your own tenant (use data sources or accept IDs as variables).
- ✅ `terraform.tfvars.example` checked in, `terraform.tfvars` gitignored.
- ✅ Each example has its own `README.md` with run instructions.
- ✅ CI runs `terraform validate` against every `examples/*/`.

## Outputs — What to Expose

Default outputs every module should expose:

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

For `for_each`-instanced resources:

```hcl
output "ids" {
  description = "Map of input keys to resource IDs."
  value       = { for k, r in zpa_application_segment.apps : k => r.id }
}
```

Rules:

- ❌ `output "all" { value = zpa_application_segment.this }` — exposes every attribute, leaks abstraction.
- ❌ Outputs containing credentials or secret material.
- ✅ Selective outputs of identifiers downstream consumers actually need.
- ✅ Mark provisioning keys, OTP-style values as `sensitive = true`.

## Cross-State Composition (Read From Another State)

When a module in state A needs an ID from state B (different team, different blast radius):

```hcl
data "terraform_remote_state" "zpa_platform" {
  backend = "s3"
  config = {
    bucket = "acme-tfstate-prod"
    key    = "zscaler/zpa/platform.tfstate"
    region = "us-east-1"
  }
}

resource "zia_forwarding_control_zpa_gateway" "this" {
  name = "zpa-gw-crm"
  type = "ZPA"

  zpa_server_group {
    external_id = data.terraform_remote_state.zpa_platform.outputs.crm_server_group_id
    name        = data.terraform_remote_state.zpa_platform.outputs.crm_server_group_name
  }

  zpa_app_segments {
    external_id = data.terraform_remote_state.zpa_platform.outputs.crm_app_segment_id
    name        = data.terraform_remote_state.zpa_platform.outputs.crm_app_segment_name
  }
}
```

`zpa_server_group` and `zpa_app_segments` are blocks, each requiring both `external_id` and `name`, so the ZPA-side state must export both values. If the two products are owned by the same team, skip the remote-state hop and read the ZPA data sources directly in one module — see [Module Boundary Rules](#module-boundary-rules).

❌ Merging two states to avoid the cross-reference.
✅ One state per ownership boundary; `terraform_remote_state` for ID handoff. See [State Management](state-management.md).

## Lifecycle Rules in Modules

- ❌ `lifecycle { prevent_destroy = true }` in a reusable module — caller can't override; surfaces as a footgun.
- ❌ `lifecycle { ignore_changes = ["*"] }` — masks drift forever.
- ✅ `lifecycle { create_before_destroy = true }` for resources where downtime matters and the API supports it.
- ✅ `lifecycle { precondition { ... } }` for cross-variable validation that variable-validation blocks can't express.

## Related

- [Coding Practices](coding-practices.md) — `for_each` vs `count`, locals, dynamic blocks.
- [Naming Conventions](naming-conventions.md) — module / file / variable naming.
- [State Management](state-management.md) — when to split modules across states.
