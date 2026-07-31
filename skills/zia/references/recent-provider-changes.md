# ZIA — Recent Provider Changes

*Auto-generated from `terraform-provider-zia/CHANGELOG.md` — last updated 2026-07-27.*

Curated subset of recent provider releases that affect HCL users. Internal SDK bumps, library upgrades, and pure refactors are filtered out. Always cross-reference the full upstream changelog at <https://github.com/zscaler/terraform-provider-zia/blob/master/CHANGELOG.md>.

## v4.8.0 — July, 20 2026

### NEW - RESOURCES AND DATA SOURCES

- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - Added the resource and data source `zia_dlp_global_options` - Retrieves and updates the existing DLP Advanced Settings.
- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - Added the resource and data source `zia_dns_application_groups` - Creates and retrieves DNS application groups.
- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - Added the resource and data source `zia_endpoint_dlp_custom_apps` - Creates and retrieves custom Endpoint DLP applications.
- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - Added the resource and data source `zia_endpoint_dlp_rules` - Creates and retrieves Endpoint DLP policy rules.
- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - Added the resource and data source `zia_outbound_email_dlp` - Creates and retrieves Outbound Email DLP policy rules.
- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - Added the resource `zia_endpoint_dlp_application_group` - Creates and manages Endpoint DLP application groups.
- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - Added the resource `zia_endpoint_dlp_resource` - Creates and manages Endpoint DLP resources.
- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - Added the resource `zia_endpoint_dlp_resource_group` - Creates and manages Endpoint DLP resource groups (tags).
- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - Added the resource `zia_endpoint_dlp_sub_rules` - Creates and manages exception (sub) rules under an Endpoint DLP policy rule.
- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - Added the data source `zia_endpoint_dlp_application` - Retrieves an Endpoint DLP application by name or ID.
- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - Added the data source `zia_dlp_endpoint_resource_channels` - Retrieves DLP resources configured for a specific channel.
- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - Added the data source `zia_dlp_endpoint_resource_group_tag` - Retrieves DLP endpoint resource tags defined for a channel.
- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - Added the data source `zia_eun_template_product` - Retrieves browser-based and Zscaler Client Connector notification templates by policy type.
- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - Added the data source `zia_eun_user_confirmation_template_product` - Retrieves user confirmation notification templates by policy type.

### Enhancements

- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - The resources ``zia_ssl_inspection_rules`, `zia_firewall_filtering_rule`, `zia_firewall_dns_rule` now support the following attributes to configure policy rule conditions based on endpoint applications, endpoint application tags, and endpoint application threat levels:

## v4.7.26 — June, 26 2026

### Enhancements

- [PR #583](https://github.com/zscaler/terraform-provider-zia/pull/583) - Added new Resource and Data sources for HTTP Header Control
- [PR #583](https://github.com/zscaler/terraform-provider-zia/pull/583) - The `zia_url_categories` resource now automatically detaches a custom URL category from any rules that reference it before deleting the category. This removes the need to manually remove the category from rules first and avoids the API error returned when deleting a category that is still in use.

## v4.7.25 — June, 23 2026

### Enhancements

- [PR #582](https://github.com/zscaler/terraform-provider-zia/pull/582) Added new datasource `zia_adaptive_access_profile`.

### Bug Fixes

- [PR #582](https://github.com/zscaler/terraform-provider-zia/pull/582) - Fixed a crash in the `zia_user_management` data source when reading a user that belongs to one or more groups.

## v4.7.24 — June, 1 2026

### Bug Fixes

- [PR #579](https://github.com/zscaler/terraform-provider-zia/pull/579) - Fixed the `zia_user_management` resource to read the user's `name` and `email` from the user list instead of the single-user lookup. On tenants migrated to Zidentity the single-user lookup returned these fields in an encoded form, which produced a perpetual in-place update on every `terraform plan`.
- [PR #579](https://github.com/zscaler/terraform-provider-zia/pull/579) - Fixed a crash in the `zia_user_management` resource when reading a user that belongs to one or more groups.

## v4.7.23 — May, 28 2026

### Bug Fixes

- [PR #578](https://github.com/zscaler/terraform-provider-zia/pull/578) - Fixed a regression in the `zia_url_categories` resource where `terraform plan` could fail immediately after `terraform import` (or any time the API returned the `urls` list in a different order than the one declared in HCL) on v4.7.22. Imports of large existing custom URL categories now plan cleanly, and re-ordering URLs in the configuration continues to produce no diff. Follow-up to [issue #575](https://github.com/zscaler/terraform-provider-zia/issues/575).
- [PR #578](https://github.com/zscaler/terraform-provider-zia/pull/578) - Removed `MaxItems` from attribute `tenancy_profile_ids` and `cloud_app_instances` in the resource `zia_cloud_app_control_rule` to allow API own limit delegation. To find the exact number of tenant profiles or cloud app instances allowed per rule, please consult the [API documentation](https://automate.zscaler.com/docs/api-reference-and-guides/api-reference/zia/cloud-app-control-policy/web-application-rule-resource-add-rule)

## v4.7.22 — May, 27 2026

### Enhancements

- [PR #576](https://github.com/zscaler/terraform-provider-zia/pull/576) - Added a `search` argument to the `zia_cloud_app_control_rule_actions` data source for client-side [JMESPath](https://jmespath.org/) filtering of the available action list. The expression operates on the action strings (for example, `"[?starts_with(@, 'ALLOW_')]"`) and is applied before the ISOLATE split and the `action_prefixes` filter, so every output attribute reflects the narrowed set.
- [PR #576](https://github.com/zscaler/terraform-provider-zia/pull/576) - Added New Datasource `zia_supported_browser_version` to retrieve a list of all supported browsers and their versions
- [PR #576](https://github.com/zscaler/terraform-provider-zia/pull/576) - Added support for Smart Isolation configuration in the resource `zia_browser_control_policy`

### Bug Fixes

- [PR #576](https://github.com/zscaler/terraform-provider-zia/pull/576) - Significantly reduced refresh, plan, and apply time on `zia_url_categories` resources holding large numbers of URLs. In our reproducer with a single custom category containing 20,000 URLs, fresh-create dropped from several minutes to around 35 seconds and refresh dropped from many minutes to around 20 seconds. Re-ordering URLs in the configuration (or the API returning them in a different order) no longer produces a diff. Addresses [issue #575](https://github.com/zscaler/terraform-provider-zia/issues/575).

### Documentation

- [PR #576](https://github.com/zscaler/terraform-provider-zia/pull/576) - Expanded the JMESPath examples in the `zia_cloud_applications` data source documentation with category matches, friendly-name substring search, AND/OR composition, projection, and exact-name lookups.
- [PR #576](https://github.com/zscaler/terraform-provider-zia/pull/576) - Added a new "Dynamically Resolving `applications` and `actions`" section to the `zia_cloud_app_control_rule` resource documentation, showing how to pull both the application list and the action list from their data sources (with and without JMESPath) so rules self-update as Zscaler adjusts its cloud-application catalog.
- [PR #576](https://github.com/zscaler/terraform-provider-zia/pull/576) - Added dynamic `cloud_applications` / `applications` resolution examples to the `zia_dlp_web_rules`, `zia_ssl_inspection_rules`, `zia_firewall_dns_rule`, and `zia_file_type_control_rules` resource documentation.

## v4.7.21 — May, 12 2026

### Enhancements

- [PR #569](https://github.com/zscaler/terraform-provider-zia/pull/569) - Enhanced the `zia_firewall_filtering_rule` data source to return a list of rules via the new `rules` block when no single-rule lookup is supplied, so multiple rules can be iterated with `for_each`. Added optional filter arguments (`rule_name`, `rule_label`, `rule_action`, `department`, `device_group`, `nw_application`, and others) and a `search` argument for client-side [JMESPath](https://jmespath.org/) filtering. Single-rule lookup still works — use `rule_id` for the numeric lookup (previously `id`) or `name` for the name lookup. Addresses [issue #568](https://github.com/zscaler/terraform-provider-zia/issues/568).

### New Resources

- [PR #569](https://github.com/zscaler/terraform-provider-zia/pull/569) - Added new resource `zia_ips_signature_rules` to create and manage custom IPS signature rules. `rule_text` is validated by the Zscaler validation endpoint on every create and update, and any syntax error is surfaced before state is committed.

### New Data Sources

- [PR #569](https://github.com/zscaler/terraform-provider-zia/pull/569) - Added new data source `zia_ips_signature_rules` to look up a custom IPS signature rule by `id` or `name`.

## v4.7.20 — May, 7 2026

### Enhancements

- [PR #567](https://github.com/zscaler/terraform-provider-zia/pull/567) - Significantly reduced apply time and API call volume when creating, updating, or reordering large numbers of rules across all rule-based resources: `zia_ssl_inspection_rules`, `zia_url_filtering_rules`, `zia_firewall_filtering_rule`, `zia_firewall_dns_rules`, `zia_firewall_ips_rules`, `zia_cloud_app_control_rules`, `zia_dlp_web_rules`, `zia_forwarding_control_rule`, `zia_nat_control_rules`, `zia_sandbox_rules`, `zia_bandwidth_control_rules`, `zia_traffic_capture_rules`, `zia_file_type_control_rules`, `zia_casb_dlp_rules`, `zia_casb_malware_rules`. Also resolved the `INVALID_INPUT_ARGUMENT: Rule is not allowed at order N` errors that could occur when bulk-creating rules in parallel ([SUP-3988](https://help.zscaler.com/)). Bumped the underlying Zscaler Go SDK to v3.8.33 for related rate-limit and cache-invalidation fixes.

## v4.7.19 — May, 1 2026

### Enhancements

- [PR #564](https://github.com/zscaler/terraform-provider-zia/pull/564) - Added support for looking up users by `email` in the `zia_user_management` data source. The lookup matches the `email` field exactly and case-insensitively against the API result set.
- [PR #564](https://github.com/zscaler/terraform-provider-zia/pull/564) - Fixed `search` (JMESPath) interaction with `name`/`email` lookups in `zia_user_management`. When `search` is set, the provider now bypasses the API-side `name=<lookup>` query parameter so the JMESPath expression is applied against the full user population, rather than a slice already narrowed by the lookup value. Improved the "user not found" error message to surface the active `search` expression and the resulting candidate-pool size when a JMESPath filter is in effect, making misconfigured expressions (e.g. referencing `department.email` instead of `department.name`) easier to diagnose.

### Important Note - New Feature

- [API Session Timeout](https://help.zscaler.com/zia/release-upgrade-summary-2026#:~:text=Feature%20Available-,API%20Session%20Timeout,-When%20configuring%20advanced) - A new field, `api_session_timeout`, is available for the AdvancedSettings model in the /advancedSettings APIs. This configuration allows you to specify how long API-initiated sessions can be inactive before they are forced to reauthenticate. The timeout duration can range from 5 to 20 minutes. The attribute `api_session_timeout` is available via the resource `zia_advanced_settings`

## v4.7.18 — April, 17 2026

### Bug Fixes

- [PR #563](https://github.com/zscaler/terraform-provider-zia/pull/563) - Removed `country` and `tz` validation from resource `zia_location_management` to align with recent API changes.
