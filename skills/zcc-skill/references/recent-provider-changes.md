# ZCC — Recent Provider Changes

*Auto-generated from `terraform-provider-zcc/CHANGELOG.md` — last updated 2026-04-23.*

Curated subset of recent provider releases that affect HCL users. Internal SDK bumps,
library upgrades, and pure refactors are filtered out. Always cross-reference the full
upstream changelog at <https://github.com/zscaler/terraform-provider-zcc/blob/master/CHANGELOG.md>.

## v0.1.0 — April, xx 2026

### Initial Release

- [PR #1](https://github.com/zscaler/terraform-provider-zcc/pull/1) - Initial Terraform Plugin Framework provider for Zscaler Client Connector (ZCC), built on `zscaler-sdk-go/v3` v3.8.30. Resources: `zcc_trusted_network`, `zcc_forwarding_profile`, `zcc_failopen_policy`, `zcc_web_app_service`. Data sources: `zcc_trusted_network`, `zcc_forwarding_profile`, `zcc_failopen_policy`, `zcc_web_app_service`, `zcc_admin_user`, `zcc_admin_roles`, `zcc_devices`, `zcc_custom_ip_apps`, `zcc_predefined_ip_apps`, `zcc_process_based_apps`, `zcc_application_profiles`.

### Build & tooling

- Aligned `terraform-plugin-framework` to `v1.19.0` and `terraform-plugin-testing` to `v1.15.0` so the provider builds cleanly against `terraform-plugin-go v0.31.0` (Terraform 1.14+ resource configuration generation).
