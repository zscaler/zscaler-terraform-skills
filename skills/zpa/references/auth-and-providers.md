# ZPA — Auth & Providers

How to configure the `zscaler/zpa` provider correctly across auth modes, clouds, and microtenant scopes.

## Decision Table — Pick the Auth Mode

| Goal                                                | Use                              | Tradeoff                                                                  |
| --------------------------------------------------- | -------------------------------- | ------------------------------------------------------------------------- |
| Tenant migrated to Zidentity (most modern tenants)  | OneAPI client credentials        | Requires Zidentity onboarding; not available on `GOV` / `GOVUS` clouds.   |
| OneAPI tenant + JWT-style cert auth                 | OneAPI private key (JWK)         | More setup; supports key rotation without distributing a shared secret.   |
| Tenant **not** migrated to Zidentity                | Legacy v3 client credentials     | Will need to migrate when tenant moves to Zidentity.                      |
| GOV / GOVUS cloud                                   | Legacy v3 client credentials     | OneAPI is not supported on these clouds (as of provider v4.x).            |

If the user does not say which they have, **ask**. Do not silently default to OneAPI — many production tenants are still on legacy.

## Cloud Selector — Two Different Attributes

`zscaler_cloud` (OneAPI) and `zpa_cloud` (legacy) are **not** the same and accept different values. Mixing them is the most common source of "auth works but nothing returns" bugs.

### OneAPI: `zscaler_cloud` — OPTIONAL, Zidentity environment selector only

| Value     | When                                                                                            |
| --------- | ----------------------------------------------------------------------------------------------- |
| *(unset)* | **Default — production Zidentity.** Use this for all production tenants.                        |
| `beta`    | Zidentity beta environment, for pre-release validation. Never set for production state.          |

❌ Do not pass legacy `zpa_cloud` values (`PRODUCTION`, `BETA`, `ZPATWO`, `GOV`, …) to `zscaler_cloud`. They are not valid Zidentity environments. ✅ Omit `zscaler_cloud` entirely for production OneAPI.

### Legacy: `zpa_cloud` — REQUIRED only when not `PRODUCTION`

| Value         | When                                                                          |
| ------------- | ----------------------------------------------------------------------------- |
| *(unset)*     | **Default — `PRODUCTION`.** Omit on production tenants.                       |
| `BETA`        | Pre-release features; for testing only — never for production state.          |
| `ZPATWO`      | Specific commercial cloud — set if your tenant is provisioned on it.          |
| `GOV`         | US Federal cloud (legacy-only).                                               |
| `GOVUS`       | US Federal high-security cloud (legacy-only).                                 |
| `PREVIEW`     | Internal preview cloud.                                                        |

## Provider Block — OneAPI Client Credentials

```hcl
terraform {
  required_version = "~> 1.9"
  required_providers {
    zpa = {
      source  = "zscaler/zpa"
      version = "~> 4.0"
    }
  }
}

provider "zpa" {
  # Prefer env vars in CI; this block is for local dev / explicit overrides.
  client_id     = var.zpa_client_id
  client_secret = var.zpa_client_secret
  vanity_domain = var.zpa_vanity_domain
  customer_id   = var.zpa_customer_id
  # zscaler_cloud = "beta"   # OPTIONAL — only set for non-prod Zidentity environments.
}
```

Equivalent env vars (preferred — no `provider` block needed):

| Env var                  | Maps to            | Required?                  |
| ------------------------ | ------------------ | -------------------------- |
| `ZSCALER_CLIENT_ID`      | `client_id`        | Yes                        |
| `ZSCALER_CLIENT_SECRET`  | `client_secret`    | Yes (or `ZSCALER_PRIVATE_KEY`) |
| `ZSCALER_VANITY_DOMAIN`  | `vanity_domain`    | Yes                        |
| `ZSCALER_CLOUD`          | `zscaler_cloud`    | **No** — only for non-prod (e.g. `beta`) |
| `ZPA_CUSTOMER_ID`        | `customer_id`      | Yes                        |

## Provider Block — OneAPI Private Key (JWK)

```hcl
provider "zpa" {
  client_id     = var.zpa_client_id
  private_key   = file("${path.module}/zpa_private.pem")
  vanity_domain = var.zpa_vanity_domain
  customer_id   = var.zpa_customer_id
  # zscaler_cloud = "beta"   # OPTIONAL
}
```

❌ Do not commit the `.pem` to git. ✅ Mount it from your secret store onto the runner at job start, and reference it via `path.module` or an absolute path env var.

## Provider Block — Legacy v3 (Pre-Zidentity Tenants, GOV, GOVUS)

```hcl
provider "zpa" {
  use_legacy_client = true                # gates legacy auth path

  zpa_client_id     = var.zpa_client_id
  zpa_client_secret = var.zpa_client_secret
  zpa_customer_id   = var.zpa_customer_id
  # zpa_cloud       = "BETA"  # REQUIRED only when non-PRODUCTION
}
```

Equivalent env vars: `ZPA_CLIENT_ID`, `ZPA_CLIENT_SECRET`, `ZPA_CUSTOMER_ID`, `ZPA_CLOUD`. The `ZPA_*` env vars are the legacy-namespaced equivalents of the `ZSCALER_*` OneAPI env vars. `ZPA_CLOUD` is the only one of these that can typically be omitted (production is the default).

## Multi-Tenant / Multi-Region Layouts

### Single-tenant, single-cloud (typical)

One `provider "zpa"` block. Use environment-scoped state (`prod/zpa/`, `staging/zpa/`).

### Multiple tenants in the same configuration

Use provider aliases. Each alias is its own `provider` block.

```hcl
provider "zpa" {
  alias         = "tenant_a"
  client_id     = var.tenant_a_client_id
  client_secret = var.tenant_a_client_secret
  vanity_domain = "acme"
  customer_id   = var.tenant_a_customer_id
}

provider "zpa" {
  alias         = "tenant_b"
  client_id     = var.tenant_b_client_id
  client_secret = var.tenant_b_client_secret
  vanity_domain = "globex"
  customer_id   = var.tenant_b_customer_id
}

resource "zpa_segment_group" "acme_finance" {
  provider = zpa.tenant_a
  name     = "Finance"
  enabled  = true
}
```

❌ Do not put two tenants' resources in the same state file unless you genuinely manage them as one fate. ✅ Prefer one workspace per tenant.

## Microtenant Configuration

Microtenant scope is set **per resource**, not on the provider.

```hcl
resource "zpa_segment_group" "tenant_x_finance" {
  name           = "Finance"
  enabled        = true
  microtenant_id = var.zpa_microtenant_id
}
```

Rules:

- ❌ Do not omit `microtenant_id` on a resource that lives in a microtenant — Read will return 404 → Terraform recreates.
- ❌ Do not mix microtenant-scoped and parent-tenant resources without clearly separating them.
- ✅ Plumb `microtenant_id` through every resource and every data source via a single `var.zpa_microtenant_id` (use `null` for parent tenant).
- ✅ Pass `microtenant_id` to data sources too:

    ```hcl
    data "zpa_segment_group" "finance" {
      name           = "Finance"
      microtenant_id = var.zpa_microtenant_id
    }
    ```

## Credential Hygiene

| ❌ Don't                                                                                | ✅ Do                                                                                                |
| -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Put `client_secret`, `private_key`, or `customer_id` in a checked-in `.tfvars`.        | Source from Vault / AWS Secrets Manager / GH Actions secrets, inject as env vars at job start.       |
| Echo credentials in CI logs (`echo "secret=$ZSCALER_CLIENT_SECRET"`).                  | Use `::add-mask::` (GitHub Actions) on every secret your job touches.                                |
| Store `private_key` PEM in the repo.                                                   | Mount it onto the runner from a secret store; reference by path.                                     |
| Use a single OneAPI client for all environments.                                       | Issue one OneAPI client per environment (prod / staging / dev). Rotate on cadence.                   |
| Mark sensitive variables as `sensitive = false` (or omit the flag).                    | `sensitive = true` on every variable carrying a credential, even if only display-masked.             |

State considerations:

- The OneAPI client secret is **not** persisted to state — it's read from provider config at apply time only.
- IDs (segment IDs, server IDs, microtenant IDs) **are** in state. Keep state in an encrypted backend with strict access (S3 + KMS + bucket policy, or Terraform Cloud / Enterprise).

## CI/CD Wiring (GitHub Actions sketch)

```yaml
jobs:
  plan:
    runs-on: ubuntu-latest
    env:
      ZSCALER_CLIENT_ID:     ${{ secrets.ZPA_PROD_CLIENT_ID }}
      ZSCALER_CLIENT_SECRET: ${{ secrets.ZPA_PROD_CLIENT_SECRET }}
      ZSCALER_VANITY_DOMAIN: acme
      ZPA_CUSTOMER_ID:       ${{ secrets.ZPA_PROD_CUSTOMER_ID }}
      # ZSCALER_CLOUD intentionally unset — production Zidentity is the default.
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with: { terraform_version: 1.9.0 }
      - run: terraform init
      - run: terraform fmt -check
      - run: terraform validate
      - run: terraform plan -out=tfplan
      - uses: actions/upload-artifact@v4
        with: { name: tfplan, path: tfplan }
```

The apply job pulls the plan artifact and runs `terraform apply tfplan` — **never** re-plans inside apply.

## Common Auth Errors

| Error message                                       | Cause                                                                                  | Fix                                                                            |
| --------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `401 unauthorized` immediately on init/plan         | Wrong `client_id` / `client_secret`, or wrong `vanity_domain` for the tenant.          | Verify in Zidentity console; confirm `vanity_domain` is the prefix (no `.zscalerportal.net`). |
| `vanity_domain not found`                           | Typo in `vanity_domain`, or tenant not migrated to Zidentity.                          | Confirm in Zidentity; if not migrated, switch to legacy auth.                  |
| `Cloud GOV not supported for OneAPI`                | Tenant is on GOV/GOVUS but provider is configured for OneAPI.                          | Switch to legacy auth (`use_legacy_client = true`).                            |
| `customer_id required`                              | Forgot `ZPA_CUSTOMER_ID` env or `customer_id` in provider block.                       | Set it.                                                                        |
| `403 access denied` on a specific resource only      | Microtenant scope mismatch — credential lacks access to the requested microtenant.     | Use a credential bound to that microtenant, or remove `microtenant_id`.        |
