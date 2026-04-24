# ZTC — Resource Catalog

Canonical, minimum-viable HCL for the `ztc_*` resources, plus composition recipes.

**Canonical schema source:** <https://registry.terraform.io/providers/zscaler/ztc/latest/docs>. The HCL below is grounded against the resource pages on that Registry. If you need a resource not listed here, fetch its Registry page (`/resources/<name_without_ztc_prefix>`) and ground new HCL in that page — never invent attribute names.

## Resource Index

| Resource                                       | Purpose                                                       | Type                                                |
| ---------------------------------------------- | ------------------------------------------------------------- | --------------------------------------------------- |
| `ztc_edge_connector_group`                     | Compute fleet running connectors                              | **Data source only** (orchestrated by cloud)        |
| `ztc_location_management`                      | A site / VPC / VNet                                            | **Data source only** (orchestrated by cloud)        |
| `ztc_location_template`                        | Template for new locations                                     | Resource + data source                              |
| `ztc_forwarding_gateway`                       | Outbound gateway (DIRECT / ZIA)                                | Resource + data source                              |
| `ztc_dns_forwarding_gateway`                   | DNS-specific forwarding gateway                                | Resource + data source                              |
| `ztc_dns_gateway`                              | DNS resolution gateway (added in v0.1.8)                       | Resource + data source                              |
| `ztc_zia_forwarding_gateway`                   | ZIA-specific forwarding gateway                                | Resource + data source                              |
| `ztc_traffic_forwarding_rule`                  | Where traffic goes (with `order`)                              | Resource + data source                              |
| `ztc_traffic_forwarding_dns_rule`              | DNS traffic forwarding rule                                    | Resource + data source                              |
| `ztc_traffic_forwarding_log_rule`              | Logging policy for traffic                                     | Resource + data source                              |
| `ztc_network_services`                         | Network service object                                          | Resource + data source                              |
| `ztc_network_services_groups`                  | Group of network services                                      | Resource + data source                              |
| `ztc_ip_source_groups`                         | Source IP group                                                | Resource + data source                              |
| `ztc_ip_destination_groups`                    | Destination IP group                                           | Resource + data source                              |
| `ztc_ip_pool_groups`                           | IP pool group                                                   | Resource + data source                              |
| `ztc_workload_groups`                          | Workload classification (cross-references ZIA)                 | Resource + data source                              |
| `ztc_provisioning_url`                         | Per-edge bootstrap URL                                         | Resource                                             |
| `ztc_public_cloud_info`                        | Public cloud account info                                       | **Data source only**                                |
| `ztc_supported_regions`                        | Cloud regions supported by ZTC                                 | **Data source only**                                |
| `ztc_activation_status`                        | **Required** to push draft changes live                        | Resource (singleton)                                |

---

## Cloud-Orchestrated Objects

In ZTC, **edge connector groups** and **locations** are typically created automatically when a cloud connector is deployed in AWS / Azure / GCP via the Zscaler cloud orchestration. The Terraform provider exposes them only as **data sources** — there is no `resource "ztc_edge_connector_group"`, and `resource "ztc_location_management"` should not be used for orchestrated locations.

```hcl
data "ztc_location_management" "aws_vpc" {
  name = "AWS-CAN-ca-central-1-vpc-05c7f364cf47c2b93"
}

data "ztc_edge_connector_group" "aws_vpc_a" {
  name = "zs-cc-vpc-096108eb5d9e68d71-ca-central-1a"
}

output "aws_vpc_id" {
  value = data.ztc_location_management.aws_vpc.id
}
```

❌ Do not `resource "ztc_location_management"` to "create" a location that already exists in cloud orchestration. ✅ Use the data source and reference the existing ID. If you genuinely need a Terraform-managed location (rare), use `ztc_location_template` to define a template, then provision via cloud orchestration that consumes it.

## Forwarding Gateway

```hcl
resource "ztc_forwarding_gateway" "to_zia" {
  name           = "ZIA_GW01"
  description    = "Outbound to ZIA via Cloud Connector"
  fail_closed    = true
  primary_type   = "AUTO"
  secondary_type = "AUTO"
  type           = "ZIA"
}
```

Notes:

- `type` enum: `ZIA`, `DIRECT`, etc. — see provider docs for full list per release.
- `fail_closed = true` blocks traffic on gateway failure (recommended for security-sensitive flows). `false` allows fail-open (recommended only for non-critical flows where availability outweighs filtering).
- `primary_type` / `secondary_type`: `AUTO` lets the connector pick; can be pinned to specific types.

## DNS Gateway (v0.1.8+)

```hcl
resource "ztc_dns_gateway" "corporate" {
  name        = "Corporate DNS"
  description = "Internal corporate DNS resolver"
  # …
}
```

Available from provider v0.1.8 onward. Pin to that version or higher.

## Traffic Forwarding Rule — Direct Egress

```hcl
data "ztc_location_management" "aws_vpc" {
  name = "AWS-CAN-ca-central-1-vpc-05c7f364cf47c2b93"
}

data "ztc_ip_destination_groups" "branch_a_subnets" {
  name = "branch_a_subnets"
}

data "ztc_ip_source_groups" "vpc_a_clients" {
  name = "vpc_a_clients"
}

data "ztc_network_service" "icmp_any" {
  name = "ICMP_ANY"
}

resource "ztc_traffic_forwarding_rule" "direct_to_branch_a" {
  name           = "DIRECT_to_branch_a"
  description    = "Direct egress from VPC-A to branch A subnets"
  order          = 1
  rank           = 7
  state          = "ENABLED"
  type           = "EC_RDR"
  forward_method = "DIRECT"
  src_ips        = ["10.20.0.0/16"]
  dest_addresses = ["10.30.0.0/16"]
  wan_selection  = "BALANCED_RULE"
  dest_countries = ["CA", "US"]

  src_ip_groups   { id = [data.ztc_ip_source_groups.vpc_a_clients.id] }
  dest_ip_groups  { id = [data.ztc_ip_destination_groups.branch_a_subnets.id] }
  nw_services     { id = [data.ztc_network_service.icmp_any.id] }
  locations       { id = [data.ztc_location_management.aws_vpc.id] }
}
```

Critical:

- ✅ `state = "ENABLED"` (string, not boolean).
- ✅ `order >= 1`, contiguous across rules of the same type.
- ✅ `rank` controls processing priority within the same `order` (default `7`).
- ✅ `forward_method`: `DIRECT`, `ZIA`, `GEOIP` (added in provider v4.7.15 of ZIA — verify ZTC version supports it), etc.
- ✅ `wan_selection`: `BALANCED_RULE`, etc. — see provider docs for full enum.
- ❌ `dest_countries` requires ISO 3166-1 Alpha-2 codes (`["CA", "US"]`), not country names.

## Traffic Forwarding Rule — Through ZIA Gateway

```hcl
resource "ztc_forwarding_gateway" "zia_gw" {
  name           = "ZIA_GW01"
  fail_closed    = true
  primary_type   = "AUTO"
  secondary_type = "AUTO"
  type           = "ZIA"
}

resource "ztc_traffic_forwarding_rule" "zia_for_internet" {
  name           = "Internet_via_ZIA"
  order          = 2
  rank           = 7
  state          = "ENABLED"
  type           = "EC_RDR"
  forward_method = "ZIA"

  proxy_gateway {
    id   = ztc_forwarding_gateway.zia_gw.id
    name = ztc_forwarding_gateway.zia_gw.name
  }

  locations {
    id = [data.ztc_location_management.aws_vpc.id]
  }
}
```

❌ The `proxy_gateway` block requires both `id` **and** `name` — the API returns drift if `name` is omitted. ✅ Always derive `name` from the resource attribute, not a string literal.

## Network Services & Groups

```hcl
resource "ztc_network_services" "ssh_high_port" {
  name        = "Corporate Custom SSH TCP_10022"
  description = "SSH on non-standard port"
  type        = "CUSTOM"

  src_tcp_ports {
    start = 1024
    end   = 65535
  }

  dest_tcp_ports {
    start = 10022
    end   = 10022
  }
}

resource "ztc_network_services_groups" "corp_ssh" {
  name = "Corporate Custom SSH TCP_10022"
  services {
    id = [ztc_network_services.ssh_high_port.id]
  }
}
```

- ❌ Do not declare a custom service with the same name as a predefined one — `DUPLICATE_ITEM`.
- ✅ Port ranges as nested blocks with `start` / `end`.

## IP Source / Destination Groups

```hcl
resource "ztc_ip_source_groups" "vpc_a_clients" {
  name        = "vpc_a_clients"
  description = "All client IPs in VPC-A"
  ip_addresses = ["10.20.0.0/16"]
}

resource "ztc_ip_destination_groups" "branch_a_subnets" {
  name        = "branch_a_subnets"
  description = "Branch A subnets"
  type        = "DSTN_IP"
  addresses   = ["10.30.0.0/16"]
}
```

- ❌ `ip_destination_groups.type` is required (`DSTN_IP`, `DSTN_FQDN`, `DSTN_DOMAIN`, `DSTN_OTHER`). Plan-time validation rejects empty.

## Workload Groups (Cross-Reference with ZIA)

ZTC and ZIA share the workload group concept. From ZTC, you typically **read** ZIA workload groups via the `zia_workload_groups` data source from the ZIA provider:

```hcl
terraform {
  required_providers {
    ztc = { source = "zscaler/ztc", version = "~> 0.1.8" }
    zia = { source = "zscaler/zia", version = "~> 4.0" }
  }
}

data "zia_workload_groups" "prod" {
  name = "WORKLOAD_GROUP_PROD"
}

resource "ztc_traffic_forwarding_rule" "prod_workload_zia" {
  name           = "Prod workload via ZIA"
  order          = 1
  state          = "ENABLED"
  type           = "EC_RDR"
  forward_method = "ZIA"

  src_workload_groups {
    id = [data.zia_workload_groups.prod.id]
  }

  proxy_gateway {
    id   = ztc_forwarding_gateway.zia_gw.id
    name = ztc_forwarding_gateway.zia_gw.name
  }
}
```

This is a deliberate cross-product reference — workloads are defined once in ZIA and consumed by both ZIA rules and ZTC rules.

## Activation

```hcl
resource "ztc_activation_status" "this" {
  status = "ACTIVE"

  depends_on = [
    ztc_traffic_forwarding_rule.direct_to_branch_a,
    ztc_traffic_forwarding_rule.prod_workload_zia,
    ztc_forwarding_gateway.zia_gw,
  ]
}
```

- ✅ One `ztc_activation_status` per Terraform configuration.
- ✅ List every config-affecting resource in `depends_on`.
- See [Rules & Ordering: Activation](rules-and-ordering.md#activation) for full mechanics.

---

## Composition Recipes

### "Two VPCs sharing one set of forwarding rules"

```hcl
data "ztc_location_management" "vpc_a" { name = "AWS-CAN-ca-central-1-vpc-A" }
data "ztc_location_management" "vpc_b" { name = "AWS-CAN-ca-central-1-vpc-B" }

resource "ztc_traffic_forwarding_rule" "internet_via_zia" {
  name           = "Internet via ZIA"
  order          = 1
  state          = "ENABLED"
  type           = "EC_RDR"
  forward_method = "ZIA"

  locations {
    id = [
      data.ztc_location_management.vpc_a.id,
      data.ztc_location_management.vpc_b.id,
    ]
  }

  proxy_gateway {
    id   = ztc_forwarding_gateway.zia_gw.id
    name = ztc_forwarding_gateway.zia_gw.name
  }
}
```

✅ One rule referencing multiple locations is cleaner than duplicating per-location rules.

### "Per-VPC isolation with `for_each`"

```hcl
locals {
  vpcs = {
    vpc_a = "AWS-CAN-ca-central-1-vpc-A"
    vpc_b = "AWS-CAN-ca-central-1-vpc-B"
  }
}

data "ztc_location_management" "by_vpc" {
  for_each = local.vpcs
  name     = each.value
}

resource "ztc_traffic_forwarding_rule" "per_vpc_internet" {
  for_each = local.vpcs

  name           = "Internet ${each.key}"
  order          = index(keys(local.vpcs), each.key) + 10
  state          = "ENABLED"
  type           = "EC_RDR"
  forward_method = "ZIA"

  locations {
    id = [data.ztc_location_management.by_vpc[each.key].id]
  }

  proxy_gateway {
    id   = ztc_forwarding_gateway.zia_gw.id
    name = ztc_forwarding_gateway.zia_gw.name
  }
}
```

✅ `for_each` over a map preserves stable addresses when adding/removing VPCs. ✅ Compute `order` from the key index to keep rules contiguous.

---

## Data Source Cheat Sheet

| When you need…                                  | Use                                                                              |
| ----------------------------------------------- | -------------------------------------------------------------------------------- |
| An orchestrated edge connector group            | `data "ztc_edge_connector_group" "x" { name = "..." }`                           |
| An orchestrated location                        | `data "ztc_location_management" "x" { name = "..." }`                            |
| A network service                               | `data "ztc_network_service" "x" { name = "..." }` (singular)                      |
| A network services group                        | `data "ztc_network_services_groups" "x" { name = "..." }`                        |
| An IP destination group                         | `data "ztc_ip_destination_groups" "x" { name = "..." }`                          |
| An IP source group                              | `data "ztc_ip_source_groups" "x" { name = "..." }`                               |
| Workload groups defined in ZIA                  | `data "zia_workload_groups" "x" { name = "..." }` (from the **ZIA** provider)    |
| Cloud account info                              | `data "ztc_public_cloud_info" "x" { /* ... */ }`                                  |
| Supported regions for a cloud                   | `data "ztc_supported_regions" "x" { /* ... */ }`                                  |

❌ Never hardcode IDs from the ZTC console — they change between tenants and after re-orchestration. ✅ Always go through a data source.
