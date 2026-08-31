# ZPA — Recent Provider Changes

*Auto-generated from `terraform-provider-zpa/CHANGELOG.md` — last updated 2026-08-31.*

Curated subset of recent provider releases that affect HCL users. Internal SDK bumps, library upgrades, and pure refactors are filtered out. Always cross-reference the full upstream changelog at <https://github.com/zscaler/terraform-provider-zpa/blob/master/CHANGELOG.md>.

## v4.4.11 — August 18, 2026

### Features

- [PR #686](https://github.com/zscaler/terraform-provider-zpa/pull/686) - Added ([Issue #684](https://github.com/zscaler/terraform-provider-zpa/issues/684)) the provider attribute `skip_credentials_validation` (env var `ZSCALER_SKIP_CREDENTIALS_VALIDATION`). When enabled, the provider skips credential validation and API client initialization so that configurations where every `zpa_*` resource and data source is conditionally disabled (e.g., `count = 0`) can plan and apply without credentials — e.g., multi-environment deployments where Zscaler is not present in every environment. A warning is emitted at configure time, and any resource or data source that does attempt an API call fails with an explanatory error instead of a panic.

### Deprecations

- [PR #679](https://github.com/zscaler/terraform-provider-zpa/pull/679) - Deprecated the `parallelism` provider attribute. The attribute has no effect and will be removed in a future major release; remove it from the provider block. Rate limiting requires no configuration: when a limit is exceeded, the API returns the interval to wait and the provider retries the request automatically.

### Documentation

- [PR #679](https://github.com/zscaler/terraform-provider-zpa/pull/679) - Removed the `parallelism` attribute from the provider argument reference.
- [PR #679](https://github.com/zscaler/terraform-provider-zpa/pull/679) - Removed the legacy guidance recommending that the number of concurrent API calls be limited to one when provisioning the resources `zpa_policy_access_rule`, `zpa_policy_inspection_rule`, `zpa_policy_timeout_rule`, `zpa_policy_forwarding_rule`, and `zpa_policy_isolation_rule`. Lowering Terraform's `-parallelism` flag applies to an entire run, cannot be scoped to individual resource types, and significantly slows large deployments.

## v4.4.10 — July 27, 2026

### Bug Fixes

- [PR #678](https://github.com/zscaler/terraform-provider-zpa/pull/678) - Fixed ([Issue #677](https://github.com/zscaler/terraform-provider-zpa/issues/677)) where the `enrollment_cert_id` auto-resolution only ran on create. The resolution now also runs on update for the resources `zpa_app_connector_group`, `zpa_service_edge_group`, and `zpa_private_cloud_group`, preventing a `missing.mandatory.params` API error when the attribute is empty in the state.

## v4.4.9 — July 24, 2026

### Enhancements

- [PR #675](https://github.com/zscaler/terraform-provider-zpa/pull/675) Removed `omitempty` tag from attribute boolean value `bypass_on_reauth` on ZPA `applicationsegment` and `applicationsegmentbrowseraccess`
- [PR #675](https://github.com/zscaler/terraform-provider-zpa/pull/675) Added support to attribute `devicePosture_failure_notification_enabled` on resources `zpa_policy_access_rule_v2` and `zpa_policy_access_rule`.

## v4.4.8 — July 20, 2026

### Enhancements

- [PR #673](https://github.com/zscaler/terraform-provider-zpa/pull/673) Added new `privileged_portal_capabilities` options `JOIN_SESSION`, and `CONTROL_SESSION` to resource `zpa_policy_capabilities_rule`

## v4.4.7 — July 15, 2026

### Enhancements

- [PR #671](https://github.com/zscaler/terraform-provider-zpa/pull/671) Added new `privileged_portal_capabilities` options `UPLOAD_INSPECTED_SANDBOX`, and `UPLOAD_INSPECTED_SCAN` to resource `zpa_policy_portal_access_rule`

### Bug Fixes

- [PR #671](https://github.com/zscaler/terraform-provider-zpa/pull/671) - Fixed a provider panic ([Issue #670](https://github.com/zscaler/terraform-provider-zpa/issues/670)) caused by an unguarded error type assertion in the read functions of `zpa_application_segment`, `zpa_server_group`, `zpa_service_edge_group`, and `zpa_lss_config_controller`. Transient API errors (e.g. cancelled/timed-out requests) are now surfaced as recoverable Terraform errors instead of crashing the provider.

## v4.4.6 — June 30, 2026

### Enhancements

- [PR #663](https://github.com/zscaler/terraform-provider-zpa/pull/663) Remove `forceNew` from attribute `select_connector_close_to_app` in resource `zpa_application_segment`

## v4.4.5 — June 23, 2026

### Enhancements

- [PR #663](https://github.com/zscaler/terraform-provider-zpa/pull/663) - Added OAuth2 user code enrollment support to the `zpa_private_cloud_group` resource via the new `user_codes` attribute, and made `enrollment_cert_id` optional with auto-resolution of the `Connector` enrollment certificate by name when omitted.
- [PR #663](https://github.com/zscaler/terraform-provider-zpa/pull/663) - Fixed the `zpa_private_cloud_group` resource to verify `user_codes` on initial create (previously they were only processed on update).
- [PR #663](https://github.com/zscaler/terraform-provider-zpa/pull/663) - Added the `version_profile_name` attribute to the `zpa_private_cloud_group` resource. When `override_version_profile` is enabled, the provider now auto-resolves `version_profile_id` from `version_profile_name`, consistent with `zpa_app_connector_group` and `zpa_service_edge_group`.
- [PR #663](https://github.com/zscaler/terraform-provider-zpa/pull/663) - Added `zpa_private_cloud` resource and data source to Private Cloud resources in the Business Continuity feature.

### Bug Fixes

- [PR #663](https://github.com/zscaler/terraform-provider-zpa/pull/663) - Fixed `zpa_server_group` deletion so that only application segments that actually reference the server group are updated during the detach. Previously, deleting a server group issued an update (PUT) to every application segment in the tenant, causing unnecessary configuration changes and noisy audit history on unrelated segments. ([#658](https://github.com/zscaler/terraform-provider-zpa/issues/658))

## v4.4.4 — May 21, 2026

### Enhancements

- [PR #659](https://github.com/zscaler/terraform-provider-zpa/pull/659) - Added support for OAuth2 user code enrollment to `zpa_app_connector_group` and `zpa_service_edge_group` resources via the new `user_codes` attribute. The `enrollment_cert_id` attribute is now optional and auto-resolved by name (`Connector` / `Service Edge`) when omitted, while remaining backwards compatible when set explicitly.

### Bug Fixes

- [PR #659](https://github.com/zscaler/terraform-provider-zpa/pull/659) - Added attribute `application_id` to resource `zpa_user_portal_link` to make reference to application segment resources.

## v4.4.2 — April 2 2026

### Documentation

- [PR #647](https://github.com/zscaler/terraform-provider-zpa/pull/647) - Updated `zpa_provisioning_key` documentation with newly supported `association_type` attribute values: `SITE_CONTROLLER_GRP`, `EXPORTER_GRP`, `NP_ASSISTANT_GRP`

## v4.4.1 — March, 12 2026

### Bug Fixes

- [PR #640](https://github.com/zscaler/terraform-provider-zpa/pull/640) - Fixed SCIM operand RHS validation in v1 access policy rules to use case-insensitive comparison (`strings.EqualFold`) so that values like email addresses are matched regardless of casing, consistent with RFC 7643 SCIM attribute semantics.
