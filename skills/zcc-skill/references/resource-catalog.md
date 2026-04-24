# ZCC — Resource Catalog

Canonical, minimum-viable HCL for every `zcc_*` resource and data source. ZCC has a deliberately compact surface area — 4 resources and ~12 data sources.

**Canonical schema source:** <https://registry.terraform.io/providers/zscaler/zcc/latest/docs>. The HCL below is grounded against the resource pages on that Registry. For any attribute not shown here, fetch `/resources/<name_without_zcc_prefix>` from the Registry — never invent attribute names.

## Resource Index

| Resource                  | Lifecycle               | Purpose                                                            |
| ------------------------- | ----------------------- | ------------------------------------------------------------------ |
| `zcc_trusted_network`     | Standard CRUD           | Define a trusted network for evaluation by Client Connector.        |
| `zcc_forwarding_profile`  | Standard CRUD           | How Client Connector forwards traffic; references trusted networks. |
| `zcc_failopen_policy`     | **Singleton** (per company) | Manages the per-company fail-open policy. Create = update settings on the existing object; delete = remove from state only. |
| `zcc_web_app_service`     | **Existing-only**       | Update an already-existing web app service (bypass app). Create = locate by `app_name` and apply changes; delete = remove from state only. |

Every other ZCC concept (devices, users, admin roles, application profiles, custom/predefined IP apps, process-based apps, company info) is exposed as a **data source** only — see [Data Source Cheat Sheet](#data-source-cheat-sheet) below.

---

## `zcc_trusted_network`

```hcl
resource "zcc_trusted_network" "corp_office" {
  network_name    = "Corporate Office"
  active          = true

  # condition_type accepts BOTH 0 and 1 depending on what the API returns.
  # On create, set what you want; on update, omit to leave remote value unchanged.
  condition_type  = 0

  trusted_subnets = "10.0.0.0/8"
}
```

Schema:

| Attribute                   | Required? | Notes                                                                                       |
| --------------------------- | --------- | ------------------------------------------------------------------------------------------- |
| `network_name`              | Required  | Display name.                                                                                |
| `active`                    | Optional (bool) | Whether the trusted network is active.                                                  |
| `condition_type`            | Optional (number) | API quirk: accepts both `0` and `1`. Set what the GET returns. Omit on update to leave remote value unchanged. |
| `dns_search_domains`        | Optional  | Match field. Adding/changing triggers in-place update.                                      |
| `dns_servers`               | Optional  | Match field.                                                                                 |
| `hostnames`                 | Optional  | Match field.                                                                                 |
| `resolved_ips_for_hostname` | Optional  | Match field.                                                                                 |
| `ssid`                      | Optional  | Match field.                                                                                 |
| `trusted_dhcp_servers`      | Optional  | Trusted criteria string.                                                                     |
| `trusted_egress_ips`        | Optional  | Trusted criteria string.                                                                     |
| `trusted_gateways`          | Optional  | Trusted criteria string.                                                                     |
| `trusted_subnets`           | Optional  | Trusted criteria string (CIDR or comma-separated).                                          |
| `id`                        | Computed  | Trusted network identifier (set after create).                                               |
| `guid`                      | Computed  | GUID assigned by the API; sent automatically on PUT updates. **Do not set manually.**        |

Critical:

- ❌ Do not set `guid` in HCL — it's read-only and the provider sends it back on PUT internally.
- ❌ Do not assume `condition_type` is always `0` or always `1` — it's tenant/network-specific.
- ✅ Match field changes (DNS / hostnames / SSID / subnets) trigger in-place updates, not replacement.

---

## `zcc_forwarding_profile`

```hcl
resource "zcc_forwarding_profile" "road_warrior" {
  name                       = "road-warrior"
  active                     = true
  evaluate_trusted_network   = true
  trusted_network_ids        = [zcc_trusted_network.corp_office.id]
}
```

Schema (most-used; full list at <https://registry.terraform.io/providers/zscaler/zcc/latest/docs/resources/zcc_forwarding_profile>):

| Attribute                       | Required? | Notes                                                       |
| ------------------------------- | --------- | ----------------------------------------------------------- |
| `name`                          | Required  | Forwarding profile name.                                     |
| `active`                        | Optional  | Whether active.                                              |
| `condition_type`                | Optional  | Same `0`/`1` quirk as trusted network.                       |
| `dns_search_domains`            | Optional  |                                                             |
| `dns_servers`                   | Optional  |                                                             |
| `enable_lwf_driver`             | Optional  |                                                             |
| `enable_split_vpn_tn`           | Optional  |                                                             |
| `evaluate_trusted_network`      | Optional  |                                                             |
| `hostname`                      | Optional  |                                                             |
| `predefined_tn_all`             | Optional  |                                                             |
| `predefined_trusted_networks`   | Optional  |                                                             |
| `resolved_ips_for_hostname`     | Optional  |                                                             |
| `skip_trusted_criteria_match`   | Optional  |                                                             |
| `trusted_dhcp_servers`          | Optional  |                                                             |
| `trusted_egress_ips`            | Optional  |                                                             |
| `trusted_gateways`              | Optional  |                                                             |
| `trusted_subnets`               | Optional  |                                                             |
| `trusted_network_ids`           | Optional  | List of `zcc_trusted_network` IDs (numbers).                 |
| `trusted_networks`              | Optional  | List of trusted network names (strings) — alternative form.  |
| `id`                            | Computed  | Forwarding profile ID (numeric string).                      |

Critical:

- ✅ Prefer `trusted_network_ids` (typed numbers) over `trusted_networks` (strings) when you have the resource references — it's stricter and catches typos at plan time.
- ❌ Don't mix both `trusted_network_ids` and `trusted_networks` for the same logical reference — pick one.

---

## Singleton & Existing-Only Resources

These two have a non-standard lifecycle. **Internalize this before writing HCL for them.**

### `zcc_failopen_policy` (singleton)

```hcl
resource "zcc_failopen_policy" "this" {
  enable_fail_open                          = 1     # numbers, not bool
  enable_captive_portal_detection           = 1
  captive_portal_web_sec_disable_minutes    = 30
  enable_strict_enforcement_prompt          = 0
  strict_enforcement_prompt_delay_minutes   = 5
  enable_web_sec_on_proxy_unreachable       = "1"   # strings, not bool — yes really
  enable_web_sec_on_tunnel_failure          = "1"
  tunnel_failure_retry_count                = 3
}
```

Lifecycle:

- **Create**: applies the desired settings to the company's pre-existing fail-open policy object.
- **Update**: PUTs the new settings.
- **Delete**: removes from state only — the API object stays.

Critical:

- ❌ Multiple `resource "zcc_failopen_policy"` in the same state will fight each other (it's a singleton).
- ❌ Type confusion: `enable_fail_open` is a **Number** (`0`/`1`), `enable_web_sec_on_proxy_unreachable` is a **String** (`"0"`/`"1"`), `active` is a **String**. Check the schema in the resource catalog when in doubt.
- ✅ Use the sentinel value `failopen_policy` when importing if the provider resolves the singleton automatically: `terraform import zcc_failopen_policy.this failopen_policy`.

Schema:

| Attribute                                 | Type   | Notes                                  |
| ----------------------------------------- | ------ | -------------------------------------- |
| `active`                                  | String | "0" / "1"                              |
| `captive_portal_web_sec_disable_minutes`  | Number |                                        |
| `enable_captive_portal_detection`         | Number | 0 / 1                                  |
| `enable_fail_open`                        | Number | 0 / 1                                  |
| `enable_strict_enforcement_prompt`        | Number | 0 / 1                                  |
| `enable_web_sec_on_proxy_unreachable`     | String | "0" / "1"                              |
| `enable_web_sec_on_tunnel_failure`        | String | "0" / "1"                              |
| `strict_enforcement_prompt_delay_minutes` | Number |                                        |
| `strict_enforcement_prompt_message`       | String |                                        |
| `tunnel_failure_retry_count`              | Number |                                        |
| `id`, `company_id`, `created_by`, `edited_by` | Computed |                                  |

### `zcc_web_app_service` (existing-only)

```hcl
resource "zcc_web_app_service" "outlook_bypass" {
  app_name = "Outlook Bypass"   # MUST exist in tenant; this resource updates, not creates
  active   = true
}
```

Lifecycle:

- **Create**: locates the web app service by `app_name` and applies any field changes. **Does not create a new bypass app** — that's done out-of-band in the ZCC admin portal.
- **Update**: PUTs the new settings.
- **Delete**: removes from state only — the API object stays.

Critical:

- ❌ If `app_name` doesn't exist in the tenant, create fails with not-found. Create the app in the ZCC admin portal first.
- ❌ Do not try to "create a bypass app from scratch" with this resource — it's a management resource for existing objects.

Schema:

| Attribute              | Type    | Notes                                  |
| ---------------------- | ------- | -------------------------------------- |
| `app_name`             | String  | Required. Must match an existing tenant object. |
| `active`               | Boolean |                                        |
| `app_data_blob`        | Block   | Nested: `proto`, `port`, `ipaddr`, `fqdn` |
| `app_data_blob_v6`     | Block   | IPv6 version of above                  |
| `zapp_data_blob`       | String  |                                        |
| `zapp_data_blob_v6`    | String  |                                        |
| `id`, `app_version`, `app_svc_id`, `uid`, `created_by`, `edited_by`, `edited_timestamp`, `version` | Computed |  |

Composition:

```hcl
resource "zcc_web_app_service" "outlook_bypass" {
  app_name = "Outlook Bypass"
  active   = true

  app_data_blob {
    proto  = "TCP"
    port   = 443
    fqdn   = "outlook.office365.com"
  }
}
```

---

## Composition Recipe — Trusted Network + Forwarding Profile

```hcl
resource "zcc_trusted_network" "corp_office" {
  network_name    = "Corporate Office"
  active          = true
  condition_type  = 0
  trusted_subnets = "10.0.0.0/8"
  dns_search_domains = "corp.example.com"
}

resource "zcc_trusted_network" "branch_office" {
  network_name    = "Branch Office"
  active          = true
  condition_type  = 0
  trusted_subnets = "10.20.0.0/16"
}

resource "zcc_forwarding_profile" "road_warrior" {
  name                     = "road-warrior"
  active                   = true
  evaluate_trusted_network = true

  trusted_network_ids = [
    zcc_trusted_network.corp_office.id,
    zcc_trusted_network.branch_office.id,
  ]
}
```

This is the canonical ZCC pattern: **trusted networks define "where am I", the forwarding profile defines "what should I do based on where I am"**.

---

## Data Source Cheat Sheet

| When you need…                                  | Use                                                                              |
| ----------------------------------------------- | -------------------------------------------------------------------------------- |
| Existing trusted network (read-only lookup)     | `data "zcc_trusted_network" "x" { network_name = "..." }`                        |
| Existing forwarding profile                     | `data "zcc_forwarding_profile" "x" { name = "..." }`                             |
| The fail-open policy (read-only inspection)     | `data "zcc_failopen_policy" "x" {}`                                              |
| An existing web app service                     | `data "zcc_web_app_service" "x" { name = "..." }`                                |
| Admin user details                              | `data "zcc_admin_user" "x" { /* lookup criteria */ }`                            |
| All admin roles                                  | `data "zcc_admin_roles" "x" {}`                                                  |
| Devices enrolled                                | `data "zcc_devices" "x" {}`                                                      |
| Custom IP apps                                  | `data "zcc_custom_ip_apps" "x" {}`                                               |
| Predefined IP apps                              | `data "zcc_predefined_ip_apps" "x" {}`                                           |
| Process-based apps                              | `data "zcc_process_based_apps" "x" {}`                                           |
| Application profiles                            | `data "zcc_application_profiles" "x" {}`                                         |
| Company info                                    | `data "zcc_company_info" "x" {}`                                                 |

❌ Never hardcode IDs from the ZCC console — they change between tenants. ✅ Always go through a data source for cross-resource references.

❌ The data sources for **users / devices / apps** are read-only — there is no `resource "zcc_user"` or `resource "zcc_device"`. Users come from your IdP, devices from the agent enrollment flow, apps from the admin portal.
