# ZPA — Recent Provider Changes

*Auto-generated from `terraform-provider-zpa/CHANGELOG.md` — last updated 2026-04-24.*

Curated subset of recent provider releases that affect HCL users. Internal SDK bumps, library upgrades, and pure refactors are filtered out. Always cross-reference the full upstream changelog at <https://github.com/zscaler/terraform-provider-zpa/blob/master/CHANGELOG.md>.

## v4.4.2 — April 2 2026

### Documentation

- [PR #647](https://github.com/zscaler/terraform-provider-zpa/pull/647) - Updated `zpa_provisioning_key` documentation with newly supported `association_type` attribute values: `SITE_CONTROLLER_GRP`, `EXPORTER_GRP`, `NP_ASSISTANT_GRP`

## v4.4.1 — March, 12 2026

### Bug Fixes

- [PR #640](https://github.com/zscaler/terraform-provider-zpa/pull/640) - Fixed SCIM operand RHS validation in v1 access policy rules to use case-insensitive comparison (`strings.EqualFold`) so that values like email addresses are matched regardless of casing, consistent with RFC 7643 SCIM attribute semantics.

## v4.4.0 — March, 11 2026

### Enhancements

- [PR #639](https://github.com/zscaler/terraform-provider-zpa/pull/639) - Added new `zpa_tag_namespace`, `zpa_tag_key`, and `zpa_tag_group` resources and data sources for managing tag controller objects.
