# ZCC — Recent Provider Changes

*Auto-generated from `terraform-provider-zcc/CHANGELOG.md` — last updated 2026-08-31.*

Curated subset of recent provider releases that affect HCL users. Internal SDK bumps, library upgrades, and pure refactors are filtered out. Always cross-reference the full upstream changelog at <https://github.com/zscaler/terraform-provider-zcc/blob/master/CHANGELOG.md>.

## v0.1.2 — August 13, 2026

### Bug Fixes

- [PR #28](https://github.com/zscaler/terraform-provider-zcc/pull/28) - `zcc_trusted_network`: fixed the reversed `condition_type` mapping on tenants served by the v1 API (`0` = `ALL`, `1` = `ANY`) and stopped `hostname`/`ssid` from showing `(known after apply)` on update plans when not set in the configuration.

## v0.1.1 — August 12, 2026

### Deprecations

- [PR #26](https://github.com/zscaler/terraform-provider-zcc/pull/26) - Deprecated the `parallelism` provider attribute. The attribute has no effect and will be removed in a future major release; remove it from the provider block. Rate limiting requires no configuration: when a limit is exceeded, the API returns the interval to wait and the provider retries the request automatically.

### Bug Fixes

- [PR #26](https://github.com/zscaler/terraform-provider-zcc/pull/26) - `zcc_trusted_network`: added support for tenants where the v2 `/trusted-networks` API is not yet available. The provider now detects the API generation automatically — no configuration needed — and transparently falls back to the legacy v1 `/webTrustedNetwork` endpoints using the same HCL. Import and data-source lookups by name now also resolve an unambiguous partial name on both API versions.

### Documentation

- [PR #9](https://github.com/zscaler/terraform-provider-zcc/pull/9) - Removed the `parallelism` attribute from the provider argument reference.
