# ZPA — Resource Catalog

Canonical, minimum-viable HCL for the most-used `zpa_*` resources, plus composition recipes.

**Canonical schema source:** <https://registry.terraform.io/providers/zscaler/zpa/latest/docs>. The HCL below is grounded against the resource pages on that Registry. If you need a resource not listed here, fetch its Registry page (`/resources/<name_without_zpa_prefix>`) and ground new HCL in that page — never invent attribute names.

## Resource Index

| Resource                                       | Purpose                                                | Required minimum                                                             |
| ---------------------------------------------- | ------------------------------------------------------ | ---------------------------------------------------------------------------- |
| `zpa_app_connector_group`                      | Where ZPA reaches into the network                     | `name`, `latitude`, `longitude`, `location`                                  |
| `zpa_application_server`                       | A backend application server                           | `name`, `address`                                                            |
| `zpa_segment_group`                            | Group of application segments for policy targeting     | `name`, `enabled`                                                            |
| `zpa_server_group`                             | Group of application servers tied to app connectors    | `name`, `enabled`, `app_connector_groups { id = [...] }`                     |
| `zpa_application_segment`                      | Domain(s) + ports exposed via ZPA (TCP/UDP, no BA)     | `name`, `domain_names`, `tcp_port_ranges` or `udp_port_ranges`, `segment_group_id`, `server_groups { id = [...] }` |
| `zpa_application_segment_browser_access`       | Browser-access (BA) segment with cert                  | Same as above + `clientless_apps { ... certificate_id ... }`                 |
| `zpa_application_segment_inspection`           | App segment under AppProtection / AD Inspection         | Same as base + `common_apps_dto { apps_config { ... } }`                     |
| `zpa_application_segment_pra`                  | Privileged Remote Access (PRA) segment                 | Same as base + `common_apps_dto { apps_config { ... } }`                     |
| `zpa_policy_access_rule`                       | Allow / deny access policy rule                        | `name`, `action`, `policy_set_id` (data lookup), at least one `conditions`   |
| `zpa_policy_access_forwarding_rule`            | Forwarding policy rule                                 | Same shape as access rule, different `policy_set_id`                          |
| `zpa_policy_access_isolation_rule`             | Browser isolation policy rule                          | Same shape as access rule, isolation `action`, `policy_set_id`                |
| `zpa_policy_access_inspection_rule`            | Inspection policy rule                                 | Same shape as access rule                                                     |
| `zpa_microtenant_controller`                   | Create a microtenant                                   | `name`, `criteria_attribute`, `criteria_attribute_values`                     |

For policy rules, see [Policy Rules](policy-rules.md) — operand semantics are nontrivial.

---

## App Connector Group

Where ZPA places its connectors physically (geo) and operationally (upgrade window, version profile).

```hcl
resource "zpa_app_connector_group" "us_east_1" {
  name                     = "US-East-1"
  description              = "App connectors in us-east-1"
  enabled                  = true
  city_country             = "Ashburn, US"
  country_code             = "US"
  latitude                 = "39.0438"
  longitude                = "-77.4874"
  location                 = "Ashburn, VA, US"
  upgrade_day              = "SUNDAY"
  upgrade_time_in_secs     = "66600"
  override_version_profile = true
  version_profile_id       = "0"   # 0 = Default
  dns_query_type           = "IPV4_IPV6"
}
```

Notes:

- ❌ Do not omit `latitude`/`longitude`/`location` — they're required.
- ✅ `version_profile_id`: `0` = Default, `1` = Previous, `2` = New Release. Look these up via `data "zpa_customer_version_profile"` if you want symbolic.
- ❌ `country_code` must be ISO-3166 two-letter (`US`, `BR`, `DE`).

## Application Server

```hcl
resource "zpa_application_server" "crm_backend" {
  name        = "crm-backend"
  description = "CRM backend"
  address     = "crm.internal.example.com"
  enabled     = true
}
```

`address` is a single FQDN or IP. Multiple addresses → multiple `zpa_application_server` resources, then group them with `zpa_server_group`.

## Segment Group + Server Group + Application Segment (canonical composition)

This is the single most-asked-for ZPA recipe.

```hcl
resource "zpa_segment_group" "crm" {
  name        = "CRM"
  description = "CRM application group"
  enabled     = true
}

resource "zpa_server_group" "crm" {
  name              = "CRM Servers"
  description       = "CRM backend servers"
  enabled           = true
  dynamic_discovery = false

  app_connector_groups {
    id = [zpa_app_connector_group.us_east_1.id]
  }

  servers {
    id = [zpa_application_server.crm_backend.id]
  }
}

resource "zpa_application_segment" "crm" {
  name             = "CRM"
  description      = "CRM application segment"
  enabled          = true
  health_reporting = "ON_ACCESS"
  bypass_type      = "NEVER"
  is_cname_enabled = true

  domain_names    = ["crm.example.com"]
  tcp_port_ranges = ["443", "443"]   # ranges come in pairs: [from, to]

  segment_group_id = zpa_segment_group.crm.id

  server_groups {
    id = [zpa_server_group.crm.id]
  }
}
```

Critical:

- ❌ `tcp_port_ranges` / `udp_port_ranges` are **paired**: `["443", "443"]` for a single port, `["8000", "8099"]` for a range. Never `["443"]`.
- ✅ `server_groups { id = [...] }` is a nested block, not a top-level attribute.
- ✅ `dynamic_discovery = false` when you want to pin to specific `servers`. `true` when ZPA should auto-discover via DNS resolution and the `servers` block is omitted.
- ❌ `is_cname_enabled = false` blocks CNAME-based access — leave `true` unless you have a specific reason.

### `health_reporting` values

| Value         | Use                                                       |
| ------------- | --------------------------------------------------------- |
| `NONE`        | No health checks — fastest, no visibility.                |
| `ON_ACCESS`   | Default. Health on first access.                          |
| `CONTINUOUS`  | Continuous probing — useful for critical apps.            |

### `bypass_type` values

| Value           | Use                                                                                  |
| --------------- | ------------------------------------------------------------------------------------ |
| `NEVER`         | Always go through ZPA (typical).                                                     |
| `ALWAYS`        | Bypass ZPA — direct access.                                                          |
| `ON_NET`        | Bypass ZPA when the user is on a recognized trusted network (`zpa_trusted_network`). |

## Browser Access Segment

When users hit the app via browser without a Client Connector. Requires a BA cert.

```hcl
resource "zpa_application_segment_browser_access" "wiki" {
  name             = "Wiki"
  enabled          = true
  health_reporting = "ON_ACCESS"
  bypass_type      = "NEVER"
  is_cname_enabled = true

  domain_names    = ["wiki.example.com"]
  tcp_port_ranges = ["443", "443"]

  segment_group_id = zpa_segment_group.wiki.id

  server_groups {
    id = [zpa_server_group.wiki.id]
  }

  clientless_apps {
    name                 = "wiki.example.com"
    application_protocol = "HTTPS"
    application_port     = "443"
    domain               = "wiki.example.com"
    certificate_id       = data.zpa_ba_certificate.wildcard.id
  }
}

data "zpa_ba_certificate" "wildcard" {
  name = "*.example.com"
}
```

✅ Every `clientless_apps.application_port` must also be in the segment's `tcp_port_ranges` (or `tcp_port_range` block); otherwise the API rejects it with `invalid.clientless.port`.

## Inspection Segment (AppProtection / AD Inspection)

The only resource that supports Auto App Protection and Active Directory Inspection.

```hcl
resource "zpa_application_segment_inspection" "jenkins" {
  name                     = "Jenkins"
  enabled                  = true
  bypass_type              = "NEVER"
  auto_app_protect_enabled = true
  domain_names             = ["jenkins.example.com"]
  tcp_port_ranges          = ["443", "443"]
  segment_group_id         = zpa_segment_group.apps.id

  server_groups {
    id = [zpa_server_group.apps.id]
  }

  common_apps_dto {
    apps_config {
      domain               = "jenkins.example.com"
      application_protocol = "HTTPS"
      application_port     = "443"
      app_types            = ["INSPECT"]
      trust_untrusted_cert = true
    }
  }
}
```

### Inspection segment rules

- ✅ One `common_apps_dto` block; one `apps_config` block per app inside it. Removing an `apps_config` block deletes that app (provider `v4.4.12`+).
- ✅ Each `apps_config.domain` must be in `domain_names`; each `application_port` in the port ranges.
- ✅ `application_protocol` (`HTTP` / `HTTPS`) is required in every `apps_config`, even with `auto_app_protect_enabled = true` — the API rejects requests without it.
- ✅ `certificate_id` is required for `HTTPS` when `auto_app_protect_enabled` is unset or `false` (`v4.4.12`+ enforces at plan time). ❌ Never set it for `HTTP`.
- ✅ `trust_untrusted_cert = true` = Admin Portal "Use Untrusted Certificates".
- ❌ `auto_app_protect_enabled` and `adp_enabled` together — mutually exclusive.
- ❌ Two `common_apps_dto` blocks — only the first is sent; the plan never converges.
- ❌ AppProtection on a `zpa_application_segment` — see [Troubleshooting: AppProtection Segment](troubleshooting.md#appprotection-segment-disappears-after-an-update).

## Microtenant

```hcl
resource "zpa_microtenant_controller" "tenant_x" {
  name                       = "TenantX"
  description                = "Microtenant for TenantX"
  enabled                    = true
  criteria_attribute         = "AuthDomain"
  criteria_attribute_values  = ["tenantx.example.com"]
}

output "tenant_x_microtenant_id" {
  value = zpa_microtenant_controller.tenant_x.id
}
```

Then plumb the resulting ID into every resource you want scoped to that microtenant. See [Auth & Providers: Microtenant Configuration](auth-and-providers.md#microtenant-configuration).

---

## Composition Recipes

### "Expose internal HTTPS app to a SCIM group"

```hcl
data "zpa_idp_controller" "okta" {
  name = "Okta"
}

data "zpa_scim_groups" "engineering" {
  name     = "Engineering"
  idp_name = "Okta"
}

# (Build the segment as in the canonical composition above.)

data "zpa_policy_type" "access" {
  policy_type = "ACCESS_POLICY"
}

resource "zpa_policy_access_rule" "eng_to_crm" {
  name          = "Engineering -> CRM"
  description   = "Allow Engineering SCIM group to CRM"
  action        = "ALLOW"
  operator      = "AND"
  policy_set_id = data.zpa_policy_type.access.id

  conditions {
    operator = "OR"
    operands {
      object_type = "APP"
      lhs         = "id"
      rhs         = zpa_application_segment.crm.id
    }
  }

  conditions {
    operator = "OR"
    operands {
      object_type = "SCIM_GROUP"
      lhs         = data.zpa_idp_controller.okta.id
      rhs         = data.zpa_scim_groups.engineering.id
      idp_id      = data.zpa_idp_controller.okta.id
    }
  }
}
```

For the full operand matrix and rule mechanics, see [Policy Rules](policy-rules.md).

### "Many segments behind one server group"

When several apps share the same backend infrastructure:

```hcl
locals {
  segments = {
    crm  = { domains = ["crm.example.com"],  port = "443" }
    wiki = { domains = ["wiki.example.com"], port = "443" }
    grafana = { domains = ["grafana.example.com"], port = "3000" }
  }
}

resource "zpa_application_segment" "internal" {
  for_each = local.segments

  name             = each.key
  enabled          = true
  health_reporting = "ON_ACCESS"
  bypass_type      = "NEVER"
  is_cname_enabled = true
  domain_names     = each.value.domains
  tcp_port_ranges  = [each.value.port, each.value.port]

  segment_group_id = zpa_segment_group.internal.id

  server_groups {
    id = [zpa_server_group.internal.id]
  }
}
```

✅ `for_each` over a map keeps resource addresses stable when you add/remove apps. ❌ Do not use `count` over a list — removing the middle item churns every address after it.

---

## Data Source Cheat Sheet

| When you need…                              | Use                                                                              |
| ------------------------------------------- | -------------------------------------------------------------------------------- |
| Existing app connector group by name        | `data "zpa_app_connector_group" "x" { name = "..." }`                            |
| Existing segment group by name              | `data "zpa_segment_group" "x" { name = "..." }`                                  |
| Existing IdP controller (Okta, Azure AD)    | `data "zpa_idp_controller" "x" { name = "..." }`                                 |
| SCIM group from an IdP                      | `data "zpa_scim_groups" "x" { name = "...", idp_name = "..." }`                  |
| SCIM group name shared across IAM IdPs (ZIdentity) | Add `iam_idp_name = "..."` (or `iam_idp_id`) — `v4.4.13`+; fails listing candidates if still ambiguous |
| SCIM attribute from an IdP                  | `data "zpa_scim_attribute_header" "x" { name = "...", idp_name = "..." }`        |
| SAML attribute                              | `data "zpa_saml_attribute" "x" { name = "..." }`                                 |
| Posture profile                             | `data "zpa_posture_profile" "x" { name = "..." }` (use `.posture_udid` for rule) |
| Trusted network                             | `data "zpa_trusted_network" "x" { name = "..." }` (use `.network_id` for rule)   |
| Policy type (to get `policy_set_id`)        | `data "zpa_policy_type" "x" { policy_type = "ACCESS_POLICY" }`                   |
| BA certificate                              | `data "zpa_ba_certificate" "x" { name = "..." }`                                 |
| Existing microtenant by name                | `data "zpa_microtenant_controller" "x" { name = "..." }`                         |

❌ Never hardcode IDs from the ZPA console — they change between tenants. ✅ Always go through a data source.

---

## Module Layout for ZPA-Heavy Configs

```text
environments/
  prod/
    main.tf            # provider, locals
    apps/              # one folder per app team or per business unit
      crm/main.tf
      wiki/main.tf
    policies/main.tf   # policy rules referencing ../apps via data sources
modules/
  zpa-app-segment/     # opinionated wrapper: takes domains + port, produces seg group + server group + segment + access rule
```

Split state per business unit when you have >100 segments or independent release cadences. See `terraform-skill/references/state-management.md` for the broader state pattern (this skill defers to it).
