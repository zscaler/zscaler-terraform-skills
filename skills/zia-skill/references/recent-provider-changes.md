# ZIA — Recent Provider Changes

*Auto-generated from `terraform-provider-zia/CHANGELOG.md` — last updated 2026-04-23.*

Curated subset of recent provider releases that affect HCL users. Internal SDK bumps,
library upgrades, and pure refactors are filtered out. Always cross-reference the full
upstream changelog at <https://github.com/zscaler/terraform-provider-zia/blob/master/CHANGELOG.md>.

## v4.7.18 — April, 17 2026

### Bug Fixes

- [PR #563](https://github.com/zscaler/terraform-provider-zia/pull/563) - Removed `country` and `tz` validation from resource `zia_location_management` to align with recent API changes.

## v4.7.17 — April, 13 2026

### Bug Fixes

- [PR #561](https://github.com/zscaler/terraform-provider-zia/pull/561) - Removed file type validation from resource `zia_sandbox_rules`

## v4.7.16 — April, 7 2026

### Enhancements

- [PR #560](https://github.com/zscaler/terraform-provider-zia/pull/560) - Added optional `search` attribute to data sources for JMESPath client-side filtering. Supported data sources: `zia_group_management`, `zia_user_management`, `zia_department_management`, `zia_devices`, `zia_cloud_applications`, `zia_location_groups`, `zia_location_management`. The `search` attribute accepts a [JMESPath](https://jmespath.org/) expression applied after pagination completes, enabling advanced filtering (e.g., `contains`, equality, boolean, nested field access) before local name/ID matching. Fully backward compatible — omitting `search` preserves existing behavior.

## v4.7.15 — April, 2 2026

### Enhancements

- [PR #556](https://github.com/zscaler/terraform-provider-zia/pull/556) - Updated `zia_forwarding_control_rule` Included support to the new `forward_method` `GEOIP`. ([issue #551](https://github.com/zscaler/terraform-provider-zia/issues/544)).

## v4.7.14 — March, 27 2026

### Enhancements

- [PR #554](https://github.com/zscaler/terraform-provider-zia/pull/554) - `zia_firewall_dns_rule`: validate at plan time and on create/update that `res_categories` and `dest_ip_categories` contain the same URL category IDs whenever either is set (aligned with ZIA admin UI and API requirements); documented in the resource page ([issue #551](https://github.com/zscaler/terraform-provider-zia/issues/551)).

## v4.7.13 — March, 23 2026

### Bug Fixes

- [PR #548](https://github.com/zscaler/terraform-provider-zia/pull/548) - `zia_dlp_web_rules`: reorder callbacks no longer send both `fileTypes` and `fileTypeCategories` in the PUT body; when categories are present, `fileTypes` is cleared so the API accepts the request.
- [PR #548](https://github.com/zscaler/terraform-provider-zia/pull/548) - `zia_dlp_web_rules`: reorder callbacks zero `lastModifiedTime` and omit `lastModifiedBy` before order updates to avoid `STALE_CONFIGURATION_ERROR` (same pattern as other rule resources).
- [PR #548](https://github.com/zscaler/terraform-provider-zia/pull/548) - `zia_dlp_web_rules`: `expandSubRules` now uses `[]dlp_web_rules.WebDLPRules`, matching the SDK model for nested sub-rules.
- [PR #549](https://github.com/zscaler/terraform-provider-zia/pull/549) - Added newely supported attributes `virtual_zens` and `virtual_zen_clusters` to resource `zia_location_management`
- [PR #549](https://github.com/zscaler/terraform-provider-zia/pull/549) - Added additional configuration examples for `zia_virtual_service_edge_cluster` and `zia_virtual_service_edge_node`

## v4.7.12 — March, 20 2026

### Bug Fixes

- [PR #546](https://github.com/zscaler/terraform-provider-zia/pull/546) - Removed unconditionally terminated `for` loop in Create functions for `zia_file_type_control_rules` and `zia_ssl_inspection_rules`.
- [PR #546](https://github.com/zscaler/terraform-provider-zia/pull/546) - Fixed tautological `nil == nil` condition in data source `zia_file_type_categories`.

## v4.7.11 — March, 11 2026

### Bug Fixes

- [PR #542](https://github.com/zscaler/terraform-provider-zia/pull/542) - Upgraded provider to Zscaler SDK GO v3.8.27[https://github.com/zscaler/zscaler-sdk-go/releases/tag/v3.8.27], to how the attribute `cbi_profile` is handlded within the resource `zia_url_filtering_rule`

## v4.7.10 — March, 9 2026

### Bug Fixes

- [PR #541](https://github.com/zscaler/terraform-provider-zia/pull/541) - Added `order` field input validation (`IntAtLeast(1)`) to all rule-based resources to prevent negative or zero order values that could result in corrupted, undeletable rules.

## v4.7.9 — March, 5 2026

### Enhancements

- [PR #538](https://github.com/zscaler/terraform-provider-zia/pull/538) - Added new data source `zia_dedicated_ip_proxy` for retrieving Dedicated IP Gateway information from the forwarding control policy. Supports lookup by ID or name. See [documentation](https://registry.terraform.io/providers/zscaler/zia/latest/docs/data-sources/zia_dedicated_ip_proxy) for details.
