# ZTC — Recent Provider Changes

*Auto-generated from `terraform-provider-ztc/CHANGELOG.md` — last updated 2026-04-23.*

Curated subset of recent provider releases that affect HCL users. Internal SDK bumps,
library upgrades, and pure refactors are filtered out. Always cross-reference the full
upstream changelog at <https://github.com/zscaler/terraform-provider-ztc/blob/master/CHANGELOG.md>.

## v0.1.8 — February 27, 2026

### Enhancements

- [PR #27](https://github.com/zscaler/terraform-provider-ztc/pull/27) - Added new resource and data source `ztc_dns_gateway` for managing DNS Gateway configurations.

## v0.1.6 — February 9, 2026

### Bug Fixes

- [PR #23](https://github.com/zscaler/terraform-provider-ztc/pull/23) - Fixed `ztc_traffic_forwarding_rule` READ function to accomodate OneAPI vs Legacy API availability.

## v0.1.5 — February 5, 2026

### Bug Fixes

- [PR #22](https://github.com/zscaler/terraform-provider-ztc/pull/22) - Fixed `ztc_traffic_forwarding_rule` READ function to accomodate OneAPI vs Legacy API availability.

## v0.1.4 — February 3, 2026

### Bug Fixes

- [PR #21](https://github.com/zscaler/terraform-provider-ztc/pull/21) - Fixed `ztc_traffic_forwarding_dns_rule`,  `ztc_traffic_forwarding_rule` and `ztc_traffic_log_forwarding_rule` resource reorder logic due to recent API enforcement changes. Included safeguard to prevent unnecessary reordering when the order is already correct.

## v0.1.3 — January 19, 2026

### Bug Fixes

- [PR #18](https://github.com/zscaler/terraform-provider-ztc/pull/18) - Fixed resource and datasource `ztc_traffic_forwarding_rule` issue to retrieve by ID.

## v0.1.1 — December 1, 2025

### Bug Fixes

- [PR #12](https://github.com/zscaler/terraform-provider-ztc/pull/12) - Fixed resources and data sources `ztc_provisioning_url`, `ztc_location_template`.
