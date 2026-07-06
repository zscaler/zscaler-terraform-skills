# ZPA — Recent Provider Changes

*Auto-generated from `terraform-provider-zpa/CHANGELOG.md` — last updated 2026-07-06.*

Curated subset of recent provider releases that affect HCL users. Internal SDK bumps, library upgrades, and pure refactors are filtered out. Always cross-reference the full upstream changelog at <https://github.com/zscaler/terraform-provider-zpa/blob/master/CHANGELOG.md>.

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

## v4.4.0 — March, 11 2026

### Enhancements

- [PR #639](https://github.com/zscaler/terraform-provider-zpa/pull/639) - Added new `zpa_tag_namespace`, `zpa_tag_key`, and `zpa_tag_group` resources and data sources for managing tag controller objects.

## v4.3.81 — February, 5 2025

### Bug Fixes

- [PR #630](https://github.com/zscaler/terraform-provider-zpa/pull/630) - Fixed attribute `dc_hosting_info` in the resource `zpa_app_connector_group` by setting it to both `Optional` and `Computed`. Also removed enforced validation of supported values to allow custom user names.
- [PR #629](https://github.com/zscaler/terraform-provider-zpa/pull/629) - Fixed policy access rule SCIM condition validation: validation now uses `GetValues` (aligned with `zpa_scim_attribute_header` data source) so RHS values from the attribute's `values` list (e.g. display names) are accepted instead of incorrectly failing.

### Enhancements

- [PR #629](https://github.com/zscaler/terraform-provider-zpa/pull/629) - Added `enrollment_cert_id` and `user_codes` attributes to `zpa_app_connector_group` to support OAuth2 enrollment via user code verification API.
- [PR #629](https://github.com/zscaler/terraform-provider-zpa/pull/629) - Added `enrollment_cert_id` and `user_codes` attributes to `zpa_service_edge_group` to support OAuth2 enrollment via user code verification API.
- [PR #629](https://github.com/zscaler/terraform-provider-zpa/pull/629) - Marked `provisioning_key` attribute as sensitive in `zpa_provisioning_key` resource and data source to prevent exposure in logs and console output; value remains accessible via `terraform output` and resource references.
- [PR #629](https://github.com/zscaler/terraform-provider-zpa/pull/629) - Added boolean `policy_style` attribute to `zpa_application_segment` to enable `FQDN-to-IP Policy Evaluation`

## v4.3.8 — January, 23 2025

### Bug Fixes

- [PR #625](https://github.com/zscaler/terraform-provider-zpa/pull/625) - Fixed `zpa_segment_group` and `zpa_app_connector_group` detachment function to ensure it removes the resource correctly from all supported access policies during apply and destruction process.

## v4.3.7 — January, 21 2025

### Bug Fixes

- [PR #624](https://github.com/zscaler/terraform-provider-zpa/pull/624) - Fixed `zpa_segment_group` detachment function to ensure it removes the resource correctly from all supported access policies during destruction process.

## v4.3.6 — January, 19 2025

### Bug Fixes

- [PR #619](https://github.com/zscaler/terraform-provider-zpa/pull/619) - Fixed `zpa_policy_access_rule` and `zpa_policy_access_rule_v2` update function to reconstruct deleted resources
