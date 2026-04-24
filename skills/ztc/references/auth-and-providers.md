# ZTC — Auth & Providers

How to configure the `zscaler/ztc` provider correctly across auth modes, clouds, and multi-tenant layouts.

## Decision Table — Pick the Auth Mode

| Goal                                                | Use                              | Tradeoff                                                                     |
| --------------------------------------------------- | -------------------------------- | ---------------------------------------------------------------------------- |
| Tenant migrated to Zidentity (most modern tenants)  | OneAPI client credentials        | Requires Zidentity onboarding. Not available on `zscalergov` / `zscalerten`. |
| OneAPI tenant + JWT-style cert auth                 | OneAPI private key (PEM)         | More setup; supports key rotation without distributing a shared secret.      |
| Tenant **not** migrated to Zidentity                | Legacy v3 (username + API key)   | Will need to migrate when tenant moves to Zidentity.                         |
| `zscalergov` / `zscalerten` cloud                   | Legacy v3                        | OneAPI is not supported on these clouds.                                     |

If the user does not say which they have, **ask**. Do not silently default to OneAPI — many production tenants are still on legacy.

## Cloud Selector — Two Different Attributes

`zscaler_cloud` (OneAPI) and `ztc_cloud` (legacy) are **not** the same and accept different values. Mixing them is the most common source of "auth works but nothing returns" bugs.

### OneAPI: `zscaler_cloud` — OPTIONAL, Zidentity environment selector only

| Value     | When                                                                                            |
| --------- | ----------------------------------------------------------------------------------------------- |
| *(unset)* | **Default — production Zidentity.** Use this for all production tenants.                        |
| `beta`    | Zidentity beta environment, for pre-release validation. Never set for production state.          |

❌ Do not pass legacy cloud names to `zscaler_cloud`. ✅ Omit `zscaler_cloud` entirely for production OneAPI.

### Legacy: `ztc_cloud` — REQUIRED on legacy auth, names the actual cloud

| Value           | When                                                                  |
| --------------- | --------------------------------------------------------------------- |
| `zscaler`       | Default for commercial tenants.                                       |
| `zscloud`       | Commercial cloud — set if your tenant is provisioned on it.           |
| `zscalerbeta`   | Pre-release features; for testing only.                               |
| `zscalerone`    | Commercial cloud.                                                     |
| `zscalertwo`    | Commercial cloud.                                                     |
| `zscalerthree`  | Commercial cloud.                                                     |
| `zscalergov`    | US Federal cloud (legacy-only).                                       |
| `zscalerten`    | US Federal high-security cloud (legacy-only).                         |
| `zspreview`     | Internal preview environment (legacy only).                           |

## Provider Block — OneAPI Client Credentials

```hcl
terraform {
  required_version = "~> 1.9"
  required_providers {
    ztc = {
      source  = "zscaler/ztc"
      version = "~> 0.1.8"   # pin tight: pre-1.0
    }
  }
}

provider "ztc" {
  # Prefer env vars in CI; this block is for explicit local overrides.
  client_id     = var.ztc_client_id
  client_secret = var.ztc_client_secret
  vanity_domain = var.ztc_vanity_domain
  # zscaler_cloud = "beta"   # OPTIONAL — only set for non-prod Zidentity environments.
}
```

Equivalent env vars:

| Env var                  | Maps to            | Required?                  |
| ------------------------ | ------------------ | -------------------------- |
| `ZSCALER_CLIENT_ID`      | `client_id`        | Yes                        |
| `ZSCALER_CLIENT_SECRET`  | `client_secret`    | Yes (or `ZSCALER_PRIVATE_KEY`) |
| `ZSCALER_VANITY_DOMAIN`  | `vanity_domain`    | Yes                        |
| `ZSCALER_CLOUD`          | `zscaler_cloud`    | **No** — only for non-prod (e.g. `beta`) |

ZTC does **not** require a `customer_id` (unlike ZPA).

## Provider Block — OneAPI Private Key

```hcl
provider "ztc" {
  client_id     = var.ztc_client_id
  private_key   = file("${path.module}/ztc_private.pem")
  vanity_domain = var.ztc_vanity_domain
  # zscaler_cloud = "beta"   # OPTIONAL — only set for non-prod
}
```

PEM format must be PKCS#1 unencrypted (`-----BEGIN RSA PRIVATE KEY-----`) or PKCS#8 unencrypted (`-----BEGIN PRIVATE KEY-----`).

## Provider Block — Legacy v3 (Pre-Zidentity Tenants, GOV, ZSCALERTEN)

```hcl
provider "ztc" {
  use_legacy_client = true

  username  = var.ztc_username
  password  = var.ztc_password
  api_key   = var.ztc_api_key
  ztc_cloud = var.ztc_cloud   # zscaler | zscloud | … | zscalergov | zscalerten | zspreview
}
```

Equivalent env vars:

| Env var                       | Maps to              |
| ----------------------------- | -------------------- |
| `ZTC_USERNAME`                | `username`           |
| `ZTC_PASSWORD`                | `password`           |
| `ZTC_API_KEY`                 | `api_key`            |
| `ZTC_CLOUD`                   | `ztc_cloud`          |
| `ZSCALER_USE_LEGACY_CLIENT`   | `use_legacy_client`  |

❌ Legacy uses three secrets per tenant — protect all three. ✅ Rotate the password and API key separately on a defined cadence.

## Optional Provider Tuning

| Argument           | Default | When to set                                                                                          |
| ------------------ | ------- | ---------------------------------------------------------------------------------------------------- |
| `http_proxy`       | unset   | Local caching proxy / corporate egress (`ZSCALER_HTTP_PROXY` env).                                   |
| `parallelism`      | `1`     | Increase carefully — ZTC is rate-limited; the default is intentional. Most users should leave at 1.  |
| `max_retries`      | `5`     | Lower for fast-fail environments; raise for flaky network paths.                                     |
| `request_timeout`  | `0` (no limit) | Set in seconds (max 300) when running behind aggressive idle-timeout middleware.                |

## Multi-Tenant Layouts

ZTC tenants are typically aligned with cloud accounts (one tenant per AWS account / Azure subscription / GCP project, or one per region). Use **provider aliases**:

```hcl
provider "ztc" {
  alias         = "us_east"
  client_id     = var.ztc_us_east_client_id
  client_secret = var.ztc_us_east_client_secret
  vanity_domain = "acme"
}

provider "ztc" {
  alias         = "eu_west"
  client_id     = var.ztc_eu_west_client_id
  client_secret = var.ztc_eu_west_client_secret
  vanity_domain = "acme"
}

resource "ztc_traffic_forwarding_rule" "us_east_direct" {
  provider = ztc.us_east
  # ...
}
```

❌ Do not put two tenants' resources in the same state file unless you genuinely manage them as one fate. Each tenant has its own activation lifecycle.

## Credential Hygiene

| ❌ Don't                                                                      | ✅ Do                                                                                  |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Put `client_secret`, `private_key`, or legacy `password` / `api_key` in checked-in `.tfvars`. | Source from Vault / Secrets Manager / GH Actions secrets, inject as env vars.        |
| Echo credentials in CI logs.                                                | Use `::add-mask::` (GitHub Actions) on every secret your job touches.                 |
| Store `private_key` PEM in the repo.                                        | Mount it onto the runner from a secret store; reference by path.                      |
| Use a single OneAPI client across environments.                             | Issue one OneAPI client per environment. Rotate on cadence.                           |
| Leave sensitive variables unmarked.                                         | `sensitive = true` on every variable carrying a credential.                           |

State considerations:

- The OneAPI client secret is **not** persisted to state.
- Configuration data (rule definitions, IDs) **is** in state. Encrypt at rest, restrict access.
- ZTC resources include cloud-orchestrated objects (location IDs, edge connector group IDs) — losing state means losing the link, not the objects (which still exist in cloud orchestration).

## CI/CD Wiring (GitHub Actions sketch)

```yaml
jobs:
  plan:
    runs-on: ubuntu-latest
    env:
      ZSCALER_CLIENT_ID:     ${{ secrets.ZTC_PROD_CLIENT_ID }}
      ZSCALER_CLIENT_SECRET: ${{ secrets.ZTC_PROD_CLIENT_SECRET }}
      ZSCALER_VANITY_DOMAIN: acme
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

## Common Auth Errors

| Error message                                       | Cause                                                                                  | Fix                                                                          |
| --------------------------------------------------- | -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `401 unauthorized` immediately on init/plan         | Wrong credentials, or wrong `vanity_domain` for the tenant.                            | Verify in Zidentity console.                                                 |
| `vanity_domain not found`                           | Typo, or tenant not migrated to Zidentity.                                              | Confirm in Zidentity; if not migrated, switch to legacy auth.                |
| `Cloud zscalergov not supported for OneAPI`         | Tenant on GOV / `zscalerten` but provider configured for OneAPI.                       | Switch to legacy auth (`use_legacy_client = true`).                          |
| `403 access denied` on a specific resource          | The OneAPI client lacks the role/scope needed for that resource.                       | Re-issue the OneAPI client with the right role; check Zidentity role mapping.|
| `429 too many requests`                             | `parallelism` too high.                                                                 | Reduce `parallelism` back to `1`.                                            |
