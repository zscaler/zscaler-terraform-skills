# ZIA — Resource Catalog

Canonical, minimum-viable HCL for the most-used `zia_*` resources, plus composition recipes.

**Canonical schema source:** <https://registry.terraform.io/providers/zscaler/zia/latest/docs>. The HCL below is grounded against the resource pages on that Registry. If you need a resource not listed here, fetch its Registry page (`/resources/<name_without_zia_prefix>`) and ground new HCL in that page — never invent attribute names.

> **Plural / singular trap.** ZIA resource names are inconsistent. `zia_url_filtering_rules` is **plural**, `zia_firewall_filtering_rule` is **singular**. Always cross-check the exact name in the catalog table below.

## Resource Index (most-used)

| Resource                                       | Purpose                                                | Required minimum                                                             |
| ---------------------------------------------- | ------------------------------------------------------ | ---------------------------------------------------------------------------- |
| `zia_url_filtering_rules`                      | URL category filtering policy (allow/block/caution/isolate) | `name`, `state`, `action`, `order`, `url_categories`, `protocols`, `request_methods` |
| `zia_firewall_filtering_rule`                  | Network-layer firewall policy                          | `name`, `state`, `action`, `order` (+ at least one selector group)            |
| `zia_firewall_dns_rules`                       | DNS-layer filtering policy                             | `name`, `state`, `action`, `order`                                            |
| `zia_firewall_ips_rules`                       | IPS policy                                             | `name`, `state`, `action`, `order`                                            |
| `zia_ssl_inspection_rules`                     | TLS inspection policy                                  | `name`, `state`, `action`, `order`                                            |
| `zia_dlp_web_rules`                            | DLP policy on web traffic                              | `name`, `state`, `action`, `order`                                            |
| `zia_cloud_app_control_rule`                   | Per-SaaS-app policy (M365, GDrive, AI/ML, …)           | `name`, `state`, `order`, `type`, `actions`                                   |
| `zia_dlp_dictionary`                           | DLP dictionary (custom or cloned predefined)           | `name`, `dictionary_type`, `custom_phrase_match_type` (or pattern fields)     |
| `zia_dlp_engines`                              | DLP engine combining dictionaries                      | `name`, `engine_expression`                                                   |
| `zia_location_management`                      | A location (HQ, branch) for traffic forwarding         | `name`, `country` (full name, uppercase), `auth_required`, `tz`               |
| `zia_traffic_forwarding_gre_tunnel`            | GRE tunnel from a location                             | `source_ip`, `comment`                                                        |
| `zia_traffic_forwarding_vpn_credentials`       | IPSec VPN credentials                                  | `type`, `pre_shared_key` (write-only), `fqdn`                                 |
| `zia_admin_user`                               | ZIA admin account                                      | `login_name`, `username`, `email`, `role { id = ... }`, `password`            |
| `zia_user_management`                          | End user account                                       | `name`, `email`, `groups { id = [...] }`, `department { id = ... }`           |
| `zia_activation_status`                        | **Required** to push draft changes live                | `status = "ACTIVE"`                                                           |

For full rule mechanics see [Rules & Ordering](rules-and-ordering.md). For the activation lifecycle see [Activation](activation.md).

---

## URL Filtering — Allow Rule

```hcl
resource "zia_url_filtering_rules" "allow_engineering_dev_tools" {
  name        = "Engineering -> Dev Tools"
  description = "Allow Engineering to access dev tooling categories"
  state       = "ENABLED"
  action      = "ALLOW"
  order       = 1

  url_categories = ["PROFESSIONAL_SERVICES", "WEB_BANNER_ADS"]
  protocols      = ["HTTPS_RULE", "HTTP_RULE"]
  request_methods = [
    "CONNECT", "DELETE", "GET", "HEAD", "OPTIONS", "OTHER", "POST", "PUT", "TRACE"
  ]

  departments {
    id = [data.zia_department_management.engineering.id]
  }
}

data "zia_department_management" "engineering" {
  name = "Engineering"
}
```

Critical:

- ✅ `state = "ENABLED"` (or `"DISABLED"`) — string, not boolean.
- ✅ `action`: one of `ALLOW`, `BLOCK`, `CAUTION`, `ISOLATE`.
- ✅ `request_methods` is **required** for URL filtering rules — list explicit HTTP verbs.
- ✅ `protocols`: `HTTPS_RULE`, `HTTP_RULE`, `FTP_RULE`, `ANY_RULE`, etc.
- ❌ `order = 0` is rejected at plan time. See [Rules & Ordering](rules-and-ordering.md).

## URL Filtering — Block with Override

```hcl
resource "zia_url_filtering_rules" "block_gambling" {
  name        = "Block Gambling"
  state       = "ENABLED"
  action      = "BLOCK"
  order       = 2

  url_categories = ["GAMBLING"]
  protocols      = ["ANY_RULE"]
  request_methods = ["CONNECT", "GET", "POST"]

  block_override = true
  override_users  { id = [data.zia_user_management.compliance_officer.id] }
  override_groups { id = [data.zia_group_management.security_team.id] }
}
```

`block_override = true` requires at least one of `override_users` / `override_groups`.

## URL Filtering — Browser Isolation

```hcl
data "zia_cloud_browser_isolation_profile" "default_profile" {
  name = "BD_SA_Profile2_ZIA"
}

resource "zia_url_filtering_rules" "isolate_high_risk" {
  name        = "Isolate High Risk Categories"
  state       = "ENABLED"
  action      = "ISOLATE"
  order       = 3

  url_categories = ["MISCELLANEOUS_OR_UNKNOWN", "SOCIAL_NETWORKING"]
  protocols      = ["HTTPS_RULE", "HTTP_RULE"]
  request_methods = ["CONNECT", "DELETE", "GET", "HEAD", "OPTIONS", "OTHER", "POST", "PUT", "TRACE"]

  cbi_profile {
    id   = data.zia_cloud_browser_isolation_profile.default_profile.id
    name = data.zia_cloud_browser_isolation_profile.default_profile.name
    url  = data.zia_cloud_browser_isolation_profile.default_profile.url
  }
}
```

`action = "ISOLATE"` requires the `cbi_profile` nested block.

## Firewall Filtering — Standard Allow

```hcl
data "zia_department_management" "engineering" {
  name = "Engineering"
}

resource "zia_firewall_filtering_rule" "allow_engineering" {
  name                = "Allow Engineering"
  description         = "Allow Engineering department outbound"
  state               = "ENABLED"
  action              = "ALLOW"
  order               = 1
  enable_full_logging = true

  departments {
    id = [data.zia_department_management.engineering.id]
  }
}
```

Notes:

- `zia_firewall_filtering_rule` is **singular** (unlike `zia_url_filtering_rules`).
- Selector blocks: `departments { id = [...] }`, `groups { id = [...] }`, `users { id = [...] }`, `nw_application_groups { id = [...] }`, `nw_services { id = [...] }`, `dest_ip_groups { id = [...] }`, `src_ip_groups { id = [...] }`, `locations { id = [...] }`, `location_groups { id = [...] }`, `time_windows { id = [...] }`.
- ✅ `enable_full_logging = true` for security-relevant ALLOW rules.
- ❌ `dest_countries` requires ISO-3166 Alpha-2 codes (`["US", "BR"]`), not country names.

## DLP Web Rule

```hcl
data "zia_dlp_engines" "pci" {
  name = "PCI"
}

resource "zia_dlp_web_rules" "block_pci_to_personal_email" {
  name              = "Block PCI to Personal Email"
  description       = "Block PCI dictionary matches sent to personal email categories"
  state             = "ENABLED"
  action            = "BLOCK"
  order             = 1
  protocols         = ["HTTPS_RULE", "HTTP_RULE"]

  dlp_engines {
    id = [data.zia_dlp_engines.pci.id]
  }

  url_categories {
    id = [/* ID of WEBMAIL category */]
  }

  notification_template {
    id = data.zia_dlp_notification_templates.standard.id
  }
}

data "zia_dlp_notification_templates" "standard" {
  name = "Standard DLP Notification"
}
```

❌ `dlp_engines` selector requires the `id` list shape — not a flat attribute.
❌ DLP dictionary names with spaces fail lookup. ✅ Clone the predefined dictionary with a name using underscores or dashes (e.g. `social_security_numbers_us`).

## SSL Inspection Rule

```hcl
resource "zia_ssl_inspection_rules" "inspect_engineering" {
  name        = "Inspect Engineering Dept"
  state       = "ENABLED"
  order       = 1

  action {
    type                                = "DECRYPT"
    show_eun                            = true
    show_eunatp                         = true
    override_default_certificate        = false
    do_not_decrypt_sub_actions {
      bypass_other_policies = false
      server_certificates   = "ALLOW"
      ocsp_check            = true
      block_ssl_traffic_with_no_sni_enabled = false
      min_client_tls_version = "CLIENT_TLS_1_2"
      min_server_tls_version = "SERVER_TLS_1_2"
    }
  }

  departments {
    id = [data.zia_department_management.engineering.id]
  }
}
```

`action` is a nested block (not a string), with action-type-specific sub-blocks.

## Cloud App Control Rule

```hcl
data "zia_cloud_app_control_rule_actions" "ai_ml_actions" {
  type = "AI_ML"
}

resource "zia_cloud_app_control_rule" "deny_ai_ml_upload" {
  name        = "Deny AI/ML Upload"
  state       = "ENABLED"
  order       = 1
  type        = "AI_ML"
  rank        = 7
  description = "Deny upload to AI/ML apps for Engineering"

  applications = ["CHATGPT_AI", "CLAUDE_AI"]
  actions      = ["ALLOW_AI_ML_WEB_USE", "DENY_AI_ML_UPLOAD"]

  departments {
    id = [data.zia_department_management.engineering.id]
  }
}
```

❌ `actions` enum is **per `type`** — `DENY_AI_ML_UPLOAD` only exists when `type = "AI_ML"`. Use the `zia_cloud_app_control_rule_actions` data source to discover valid values.
❌ Some `actions` combinations are validated server-side as "conflicting." See [Troubleshooting: Conflicting API Actions](troubleshooting.md#conflicting-api-actions).

## Location Management

```hcl
resource "zia_location_management" "hq_san_jose" {
  name              = "HQ - San Jose"
  description       = "Corporate HQ in San Jose"
  country           = "UNITED_STATES"   # full uppercase name, not ISO code
  tz                = "AMERICA_LOS_ANGELES"
  auth_required     = true
  ssl_scan_enabled  = true
  ofw_enabled       = true
  ips_control       = true
  surrogate_ip      = true
  idle_time_in_minutes = 30
  display_time_unit    = "MINUTE"

  ip_addresses = ["198.51.100.10"]      # public IP of the location
}
```

❌ `country` here is **not** ISO-3166 — it's the full uppercase enum name (`UNITED_STATES`, `BRAZIL`, `GERMANY`). For firewall `dest_countries`, use ISO codes (`US`, `BR`, `DE`). Easy mistake; the provider validates each locally.
❌ `surrogate_ip = true` requires `idle_time_in_minutes` and `display_time_unit` — conditionally required.

## VPN Credentials (IPSec)

```hcl
variable "ipsec_psk" {
  type      = string
  sensitive = true
}

resource "zia_traffic_forwarding_vpn_credentials" "branch_office_1" {
  type           = "UFQDN"
  fqdn           = "branch1@acme.com"
  pre_shared_key = var.ipsec_psk
  comments       = "IPSec PSK for branch office 1"
}
```

❌ `pre_shared_key` is **write-only** at the API — it's not returned on GET. The provider preserves it from prior state on Read. Don't try to import it from outside Terraform; you'll see permanent drift.

## Admin User

```hcl
data "zia_admin_role_management" "exec_admin" {
  name = "Executive Insights App Admin"
}

variable "admin_password" {
  type      = string
  sensitive = true
}

resource "zia_admin_user" "alice" {
  login_name  = "alice@acme.com"
  username    = "Alice Engineer"
  email       = "alice@acme.com"
  password    = var.admin_password
  is_disabled = false
  comments    = "Created via Terraform"

  role {
    id = data.zia_admin_role_management.exec_admin.id
  }
}
```

❌ `password` is write-only — can't be imported. Rotate via Terraform by changing the variable, applying, and activating.

---

## Composition Recipes

### "Block social networking for Sales, allow Engineering"

```hcl
data "zia_department_management" "sales" {
  name = "Sales"
}

data "zia_department_management" "engineering" {
  name = "Engineering"
}

resource "zia_url_filtering_rules" "allow_engineering_social" {
  name   = "Allow Engineering -> Social"
  state  = "ENABLED"
  action = "ALLOW"
  order  = 1
  url_categories  = ["SOCIAL_NETWORKING"]
  protocols       = ["ANY_RULE"]
  request_methods = ["CONNECT", "DELETE", "GET", "HEAD", "OPTIONS", "OTHER", "POST", "PUT", "TRACE"]
  departments { id = [data.zia_department_management.engineering.id] }
}

resource "zia_url_filtering_rules" "block_sales_social" {
  name   = "Block Sales -> Social"
  state  = "ENABLED"
  action = "BLOCK"
  order  = 2
  url_categories  = ["SOCIAL_NETWORKING"]
  protocols       = ["ANY_RULE"]
  request_methods = ["CONNECT", "DELETE", "GET", "HEAD", "OPTIONS", "OTHER", "POST", "PUT", "TRACE"]
  departments { id = [data.zia_department_management.sales.id] }
}

resource "zia_activation_status" "this" {
  status = "ACTIVE"
  depends_on = [
    zia_url_filtering_rules.allow_engineering_social,
    zia_url_filtering_rules.block_sales_social,
  ]
}
```

✅ Allow rule before block rule (lower `order` = higher priority). Always activate.

### "Many rules with `for_each`"

```hcl
locals {
  block_categories = {
    gambling     = "GAMBLING"
    adult        = "ADULT_THEMES"
    drugs        = "DRUGS"
  }
}

resource "zia_url_filtering_rules" "block" {
  for_each = local.block_categories

  name            = "Block ${each.key}"
  state           = "ENABLED"
  action          = "BLOCK"
  order           = index(keys(local.block_categories), each.key) + 10  # contiguous from 10
  url_categories  = [each.value]
  protocols       = ["ANY_RULE"]
  request_methods = ["CONNECT", "DELETE", "GET", "HEAD", "OPTIONS", "OTHER", "POST", "PUT", "TRACE"]
}
```

✅ `for_each` over a map keeps addresses stable when you add categories. ❌ Do not use `count` over a list — removing the middle item churns every address.

### "GRE tunnel + VPN credentials + location"

See the Registry pages for [`zia_traffic_forwarding_gre_tunnel`](https://registry.terraform.io/providers/zscaler/zia/latest/docs/resources/zia_traffic_forwarding_gre_tunnel) and [`zia_location_management`](https://registry.terraform.io/providers/zscaler/zia/latest/docs/resources/zia_location_management) for the full attribute set; the composition shape is: location → vpn_credentials → gre_tunnel referencing both.

---

## Data Source Cheat Sheet

| When you need…                                  | Use                                                                              |
| ----------------------------------------------- | -------------------------------------------------------------------------------- |
| Existing department by name                     | `data "zia_department_management" "x" { name = "..." }`                          |
| Existing group                                  | `data "zia_group_management" "x" { name = "..." }`                               |
| Existing user                                   | `data "zia_user_management" "x" { name = "..." }`                                |
| URL category (predefined)                       | `data "zia_url_categories" "x" { id = "GAMBLING" }`                              |
| DLP engine                                      | `data "zia_dlp_engines" "x" { name = "..." }`                                    |
| DLP notification template                       | `data "zia_dlp_notification_templates" "x" { name = "..." }`                     |
| Firewall network application                    | `data "zia_firewall_filtering_network_application" "x" { id = "APNS" }`           |
| Firewall network service                        | `data "zia_firewall_filtering_network_service" "x" { name = "..." }`             |
| Cloud Browser Isolation profile                 | `data "zia_cloud_browser_isolation_profile" "x" { name = "..." }`                |
| Cloud app control valid actions for a type      | `data "zia_cloud_app_control_rule_actions" "x" { type = "AI_ML" }`               |
| Admin role                                      | `data "zia_admin_role_management" "x" { name = "..." }`                          |
| Activation status                               | `data "zia_activation_status" "x" {}`                                            |

❌ Never hardcode IDs from the ZIA console — they change between tenants. ✅ Always go through a data source.

### JMESPath filtering (advanced)

A select set of data sources support an optional `search` attribute for client-side JMESPath filtering after pagination:

| Data source                      | Filterable fields (camelCase, per JMESPath)                                       |
| -------------------------------- | --------------------------------------------------------------------------------- |
| `zia_group_management`           | `name`, `idpId`, `comments`                                                       |
| `zia_user_management`            | `name`, `email`, `department`, `adminUser`, `type`                                 |
| `zia_department_management`      | `name`, `idpId`, `comments`, `deleted`                                            |
| `zia_devices`                    | `name`, `osType`, `osVersion`, `deviceModel`, `ownerName`                         |
| `zia_cloud_applications`         | `app`, `appName`, `parent`, `parentName`                                          |
| `zia_location_groups`            | `name`, `groupType`, `comments`, `predefined`                                     |
| `zia_location_management`        | `name`, `country`, `sslScanEnabled`, `ofwEnabled`, `authRequired`, `profile`       |

```hcl
data "zia_user_management" "engineering_admins" {
  search = "[?department.name == 'Engineering' && adminUser == `true`]"
}
```

❌ Field names in the JMESPath expression are **camelCase** (`idpId`, not `idp_id`). ❌ JMESPath filtering narrows the result set **before** local name/ID matching — if the filter excludes the target, lookup fails with "not found."
