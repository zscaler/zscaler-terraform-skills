# ZIA — Recent Provider Changes

*Auto-generated from `terraform-provider-zia/CHANGELOG.md` — last updated 2026-10-19.*

Curated subset of recent provider releases that affect HCL users. Internal SDK bumps, library upgrades, and pure refactors are filtered out. Always cross-reference the full upstream changelog at <https://github.com/zscaler/terraform-provider-zia/blob/master/CHANGELOG.md>.

## v4.8.13 — October 15, 2026

### Bug Fixes

- [PR #613](https://github.com/zscaler/terraform-provider-zia/pull/613) - Fixed deleting objects that are first detached from the rules that reference them (for example `zia_url_categories`, which is detached from URL filtering, SSL inspection, Sandbox, File Type Control, Bandwidth Classes, Firewall DNS, Firewall IPS, FTP control and DLP web rules) failing on tenants without a subscription to one of those rule types. When reading a rule type returns `403` (missing subscription such as `NOT_SUBSCRIBED`, or no access for the admin role), that rule type is now skipped, since nothing in it can reference the object. Other errors still fail the delete.
- [PR #613](https://github.com/zscaler/terraform-provider-zia/pull/613) - `zia_http_header_profile`: `user_agent` in `http_header_profile_criteria` accepted only the predefined browser values (`OPERA`, `FIREFOX`, ...), so a custom user agent string could not be set. It now accepts any string, for use with `user_agent_bitmap = "OTHER"`.

### Documentation

- [PR #613](https://github.com/zscaler/terraform-provider-zia/pull/613) - `zia_http_header_profile`: Added the missing arguments and attributes to the data source documentation, clarified that `user_agent` is the custom user agent string used with `user_agent_bitmap = "OTHER"`, and added a custom user agent example to the resource documentation.

## v4.8.12 — October 8, 2026

### Bug Fixes

- [PR #611](https://github.com/zscaler/terraform-provider-zia/pull/611) - `zia_dlp_web_rules`, `zia_endpoint_dlp_rules`, `zia_endpoint_dlp_sub_rules`, `zia_outbound_email_dlp`: Updates rejected by the API (for example `500 UNEXPECTED_ERROR` for an invalid `cloud_applications` value) now fail immediately with the API error. Previously every error was retried every 5 seconds until the update timeout, so an apply could run for 20 minutes or more and end with `context deadline exceeded` instead of the actual error. Updates now retry the same errors as creates.

## v4.8.11 — October 8, 2026

### Bug Fixes

- [PR #610](https://github.com/zscaler/terraform-provider-zia/pull/610) - `zia_dlp_web_rules`: Fixed `file_type_categories` drift on rules configured with `file_types`. The API returns the file type category derived from the configured file types, which the provider previously planned to remove on every run. `file_type_categories` is now computed when not configured, only the attribute set in the configuration is sent to the API, and setting both `file_types` and `file_type_categories` is rejected at plan time.
- [PR #610](https://github.com/zscaler/terraform-provider-zia/pull/610) - `zia_dlp_web_rules`: Fixed applies never finishing when the API stores a different rank for DLP rules than the one configured (observed with Admin Ranking disabled: rank `7` configured, rank `0` stored). Rule placement now uses the rank stored by the API, so DLP rules reach their declared order.
- [PR #610](https://github.com/zscaler/terraform-provider-zia/pull/610) - `zia_firewall_dns_rule`: Fixed rules with a redirect IP (for example `action = "REDIR_REQ"`) failing to be placed in their declared order with `Redirect IP address must be provided.`, and showing `redirect_ip` drift on every plan. After a rule has been updated, the API stops returning its redirect IP while still requiring it on updates; the provider now uses the configured `redirect_ip` in both cases.
- [PR #610](https://github.com/zscaler/terraform-provider-zia/pull/610) - `zia_url_filtering_rules`: `url_categories` is now required and must contain at least one value (use `["ANY"]` for all categories). The API rejects URL filtering rules without URL categories, so the error is now reported at plan time instead of during apply.
- [PR #610](https://github.com/zscaler/terraform-provider-zia/pull/610) - Fixed runs failing with `403 Resource Access Blocked` once the ZIA API session ends part-way through a long apply (API Session Timeout, 5 to 20 minutes). The provider now obtains a new session and retries the request automatically. Other `403` errors, such as missing permissions, still fail immediately.
- [PR #610](https://github.com/zscaler/terraform-provider-zia/pull/610) - Fixed a provider crash when updating rule-based resources (`zia_firewall_filtering_rule`, `zia_firewall_dns_rule`, `zia_firewall_ips_rule`, `zia_url_filtering_rules`, `zia_ssl_inspection_rules`, `zia_file_type_control_rules`, `zia_sandbox_rules`, `zia_forwarding_control_rule`, `zia_traffic_capture_rules`, `zia_cloud_app_control_rule`) if the list of existing rules could not be retrieved. The API error is now reported instead.

### Documentation

- [PR #610](https://github.com/zscaler/terraform-provider-zia/pull/610) - Added an "API Errors During Plan or Apply" section to the troubleshooting guide covering `403 Resource Access Blocked` (API client role or an ended API session), intermittent `401` errors with an empty code and message, activation hangs caused by `ZIA_ACTIVATION`, requests that stall until the operation timeout, and `Rule is not allowed at order N` after deleting a rule.
- [PR #610](https://github.com/zscaler/terraform-provider-zia/pull/610) - Added a recommendation to the provider documentation and the `zia_advanced_settings` resource to set the ZIA API Session Timeout to its maximum of 20 minutes before using the provider, since ZIA activates pending changes whenever an API session ends.

## v4.8.10 — October 5, 2026

### Bug Fixes

- [PR #609](https://github.com/zscaler/terraform-provider-zia/pull/609) - Fixed the `request_timeout` provider attribute rejecting values above `300` even though its default is `1800`; explicit values up to `1800` are now accepted, so users can lower the timeout from the default without also being prevented from choosing anything between the two.
- [PR #609](https://github.com/zscaler/terraform-provider-zia/pull/609) - Added missing eun template attributes to `zia_firewall_filtering_rule` resource
- [PR #609](https://github.com/zscaler/terraform-provider-zia/pull/609) - Added `BRAVE` to `user_agent_bitmap` and `user_agent` attributes in the resource `zia_http_header_profile`

### Documentation

- [PR #609](https://github.com/zscaler/terraform-provider-zia/pull/609) - Corrected the provider argument reference for `request_timeout` (the default is `1800` seconds; `0` selects the SDK's built-in 60-second timeout rather than disabling the timeout), and added a note explaining that rate limiting requires no configuration, that `max_retries` and `request_timeout` are the only supported tuning attributes, that neither affects request throughput, and that Zscaler Go SDK environment variables such as `ZSCALER_CLIENT_RATE_LIMIT_MAX_RETRIES` are not part of the provider's configuration and are ignored.

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
