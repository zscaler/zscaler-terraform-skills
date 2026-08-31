# ZIA — Recent Provider Changes

*Auto-generated from `terraform-provider-zia/CHANGELOG.md` — last updated 2026-08-31.*

Curated subset of recent provider releases that affect HCL users. Internal SDK bumps, library upgrades, and pure refactors are filtered out. Always cross-reference the full upstream changelog at <https://github.com/zscaler/terraform-provider-zia/blob/master/CHANGELOG.md>.

## v4.8.8 — August, 26 2026

### Bug Fixes

- [PR #603](https://github.com/zscaler/terraform-provider-zia/pull/603) - Added new ZIA  attribute to resource and datasource `zia_cloud_app_control_rule`

## v4.8.7 — August,17 2026

### Bug Fixes

- [PR #602](https://github.com/zscaler/terraform-provider-zia/pull/602) - Fixed a hang affecting all rule-based resources (e.g. `zia_firewall_filtering_rule`, `zia_cloud_app_control_rule`) when the configured rule orders cannot be satisfied by the service — for example when rules not managed by Terraform occupy positions inside the configured order range, or duplicate order values exist in the tenant. Previously the apply could run for hours repeatedly re-applying the same rule orders until the operation timed out; the provider now detects the situation, stops after a bounded number of attempts, and completes the apply with a warning naming the affected rules and their configured versus actual positions (visible with `TF_LOG=INFO` or higher). The remaining differences appear in the next `terraform plan`. Rule order updates are now also logged individually to simplify troubleshooting.

### Features

- [PR #602](https://github.com/zscaler/terraform-provider-zia/pull/602) - Added the provider attribute `skip_credentials_validation` (env var `ZSCALER_SKIP_CREDENTIALS_VALIDATION`). When enabled, the provider skips credential validation and API client initialization so that configurations where every `zia_*` resource and data source is conditionally disabled (e.g., `count = 0`) can plan and apply without credentials — e.g., multi-environment deployments where Zscaler is not present in every environment. A warning is emitted at configure time, and any resource or data source that does attempt an API call fails with an explanatory error instead of a panic. See ([ZPA Issue #684](https://github.com/zscaler/terraform-provider-zpa/issues/684)) for the motivating use case.

## v4.8.6 — August, 7 2026

### Enhancements

- [PR #601](https://github.com/zscaler/terraform-provider-zia/pull/601) - Added new resource `zia_pac_files` to create and manage hosted PAC files, including PAC content validation, versioned content changes, and version status transitions (`DEPLOYED`, `STAGE`, `LKG`, `UNSTAGED`). The initial version of a PAC file is always deployed; content changes are saved as new versions of the same PAC file and transitioned to the declared status.
- [PR #601](https://github.com/zscaler/terraform-provider-zia/pull/601) - Added new data source `zia_pac_files` to retrieve the list of hosted PAC files in deployed state, including default and custom PAC files. A single PAC file can be retrieved by `id` or `name`, and the PAC file content can be omitted from the results via the `filter` attribute.
- [PR #601](https://github.com/zscaler/terraform-provider-zia/pull/601) - Enhanced the data source `zia_cloud_app_control_rule_actions` to return the complete set of actions supported for the specified applications and rule type. Previously, some newer actions (e.g., `ALLOW_FILE_SHARE_UPLOAD`, `ALLOW_FILE_SHARE_VIEW`) were missing from the results, requiring users to hard-code actions from the API documentation. On clouds where the complete action list is not yet available, the data source automatically falls back to the original action lookup. This addresses [issue #522](https://github.com/zscaler/terraform-provider-zia/issues/522)

## v4.8.5 — August, 6 2026

### Bug Fixes

- [PR #600](https://github.com/zscaler/terraform-provider-zia/pull/600) - Fixed the resource `zia_url_filtering_and_cloud_app_settings`, which rejected updates with `Request body is invalid.` and could not turn a setting back off. Updates now carry every supported setting, so disabling one takes effect; the retired Skype attribute is no longer sent; and `safe_search_apps` is sent only when applications are specified. The `safe_search_apps` attribute also adopts the value returned by the service when it is not declared in the configuration, which removes a plan difference that reappeared on every run.
- [PR #600](https://github.com/zscaler/terraform-provider-zia/pull/600) - Added new ZIA URL Filtering and Cloud App Sdettings attributes:

## v4.8.4 — August, 5 2026

### Bug Fixes

- [PR #599](https://github.com/zscaler/terraform-provider-zia/pull/599) - Fixed resource zia_browser_control_policy to support tenants without a Cloud Browser Isolation profile where the service still returns a smart_isolation_profile object with every member empty. That was recorded in state as a profile the user never declared, so the next plan tried to remove it and called
- [PR #599](https://github.com/zscaler/terraform-provider-zia/pull/599) - Fixed rule ordering in the resource `zia_cloud_app_control_rule` when rules with different `type` values are applied in the same configuration. Cloud App Control rules are ordered independently per rule type; previously, when rules of more than one type were created concurrently, only one type was guaranteed to converge to the declared `order`, and rules of the other type(s) could be left in an arbitrary order. Each rule type is now reordered independently, so the final order in ZIA and in the Terraform state matches the configured `order` for every type.

## v4.8.3 — July, 31 2026

### Enhancements

- [PR #594](https://github.com/zscaler/terraform-provider-zia/pull/594) - Added new Data source `zia_ips_categories` to retrive built-in IPS Categories. This resource can then be used within the following resources: `zia_firewall_dns_rule` and `zia_firewall_ips_rule` to fullfil the attributes: `res_categories` and `dest_ip_categories`

## v4.8.2 — July, 31 2026

### Bug Fixes

- [PR #593](https://github.com/zscaler/terraform-provider-zia/pull/593) - Removed local validation on resource `zia_firewall_dns_rule` that forced both attribute values `dest_ip_categories` and `res_categories` to match due to old API requirement.
- [PR #593](https://github.com/zscaler/terraform-provider-zia/pull/593) - Upgraded to [Zscaler-SDK-GO v3.8.44](https://github.com/zscaler/zscaler-sdk-go/releases/tag/v3.8.44) to fix mispelled attribute `isWebEunEnabled` to the expected API value `isWebEUNEnabled` in firewall dns control policies struct which is non-standard camelCase style to prevent payload error during POST/PUT requests.

## v4.8.1 — July, 30 2026

### NEW - RESOURCES AND DATA SOURCES

- [PR #592](https://github.com/zscaler/terraform-provider-zia/pull/592) - Added the resource and data source `zia_ueba_alert_definitions` - Creates and retrieves alert definitions. [Configuring an Alert Rule](https://help.zscaler.com/zia/configuring-alert-rule)

### Enhancements

- [PR #592](https://github.com/zscaler/terraform-provider-zia/pull/592) - Removed an internal request-serialization layer that caused the resources `zia_url_categories`, `zia_auth_settings_urls`, and `zia_security_policy_settings` to be created and updated one at a time across an entire configuration. Deployments that create or update large numbers of URL categories now run concurrently and complete significantly faster.

### Deprecations

- [PR #592](https://github.com/zscaler/terraform-provider-zia/pull/592) - Deprecated the `parallelism` provider attribute. The attribute has no effect and will be removed in a future major release; remove it from the provider block. Rate limiting requires no configuration: when a limit is exceeded, the API returns the interval to wait and the provider retries the request automatically.

### Documentation

- [PR #592](https://github.com/zscaler/terraform-provider-zia/pull/592) - Removed all guidance recommending that Terraform's `-parallelism` flag be lowered for bulk operations. The flag applies to an entire run and cannot be scoped to individual resource types, and lowering it severely slows deployments of rule-based resources, where rule placement is reconciled for each batch of concurrently created rules.
- [PR #592](https://github.com/zscaler/terraform-provider-zia/pull/592) - Corrected the documented default for the `max_retries` provider attribute, which is `100` and was previously documented as `5`.

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

- [PR #587](https://github.com/zscaler/terraform-provider-zia/pull/587) - The resources `zia_ssl_inspection_rules`, `zia_firewall_filtering_rule`, `zia_firewall_dns_rule` now support the following attributes to configure policy rule conditions based on endpoint applications, endpoint application tags, and endpoint application threat levels:

## v4.7.26 — June, 26 2026

### Enhancements

- [PR #583](https://github.com/zscaler/terraform-provider-zia/pull/583) - Added new Resource and Data sources for HTTP Header Control
- [PR #583](https://github.com/zscaler/terraform-provider-zia/pull/583) - The `zia_url_categories` resource now automatically detaches a custom URL category from any rules that reference it before deleting the category. This removes the need to manually remove the category from rules first and avoids the API error returned when deleting a category that is still in use.
