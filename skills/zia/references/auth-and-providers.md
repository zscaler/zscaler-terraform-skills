# ZIA — Auth & Providers

How to configure the `zscaler/zia` provider correctly across auth modes, clouds, and multi-tenant layouts.

## Decision Table — Pick the Auth Mode

| Goal                                                | Use                              | Tradeoff                                                                       |
| --------------------------------------------------- | -------------------------------- | ------------------------------------------------------------------------------ |
| Tenant migrated to Zidentity (most modern tenants)  | OneAPI client credentials        | Requires Zidentity onboarding. Not available on `zscalergov` / `zscalerten`.   |
| OneAPI tenant + JWT-style cert auth                 | OneAPI private key (JWK)         | More setup; supports key rotation without distributing a shared secret.        |
| Tenant **not** migrated to Zidentity                | Legacy v3 (username + API key)   | Will need to migrate when tenant moves to Zidentity.                           |
| `zscalergov` / `zscalerten` cloud                   | Legacy v3                        | OneAPI is not supported on these clouds (as of provider v4.x).                 |

If the user does not say which they have, **ask**. Do not silently default to OneAPI — many production tenants are still on legacy.

## Cloud Selector — Two Different Attributes

`zscaler_cloud` (OneAPI) and `zia_cloud` (legacy) are **not** the same and accept different values. Mixing them is the most common source of "auth works but nothing returns" bugs.

### OneAPI: `zscaler_cloud` — OPTIONAL, Zidentity environment selector only

| Value     | When                                                                                            |
| --------- | ----------------------------------------------------------------------------------------------- |
| *(unset)* | **Default — production Zidentity.** Use this for all production tenants.                        |
| `beta`    | Zidentity beta environment, for pre-release validation. Never set for production state.          |

❌ Do not pass legacy cloud names (`zscaler`, `zscloud`, `zscalerthree`, …) to `zscaler_cloud`. They are not Zidentity environments. ✅ Omit `zscaler_cloud` entirely for production OneAPI.

### Legacy: `zia_cloud` — REQUIRED on legacy auth, names the actual cloud

| Value           | When                                                                                            |
| --------------- | ----------------------------------------------------------------------------------------------- |
| `zscaler`       | Default commercial cloud.                                                                       |
| `zscloud`       | Commercial cloud — set if your tenant is provisioned on it.                                     |
| `zscalerbeta`   | Pre-release features; for testing only — never for production state.                            |
| `zscalerone`    | Commercial cloud.                                                                                |
| `zscalertwo`    | Commercial cloud.                                                                                |
| `zscalerthree`  | Commercial cloud.                                                                                |
| `zscalergov`    | US Federal cloud (legacy-only).                                                                  |
| `zscalerten`    | US Federal high-security cloud (legacy-only).                                                    |
| `zspreview`     | Preview cloud.                                                                                   |

If you are not sure which cloud the tenant is on, log into the ZIA console and check the URL — the subdomain (e.g. `admin.zscalerthree.net`) names the cloud.

## Provider Block — OneAPI Client Credentials

```hcl
terraform {
  required_version = "~> 1.9"
  required_providers {
    zia = {
      source  = "zscaler/zia"
      version = "~> 4.0"
    }
  }
}

provider "zia" {
  # Prefer env vars in CI; this block is for local dev / explicit overrides.
  client_id     = var.zia_client_id
  client_secret = var.zia_client_secret
  vanity_domain = var.zia_vanity_domain
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

Unlike ZPA, ZIA does **not** require a `customer_id`.

## Provider Block — OneAPI Private Key (JWK)

```hcl
provider "zia" {
  client_id     = var.zia_client_id
  private_key   = file("${path.module}/zia_private.pem")
  vanity_domain = var.zia_vanity_domain
  # zscaler_cloud = "beta"   # OPTIONAL — only set for non-prod
}
```

❌ Do not commit the `.pem` to git. ✅ Mount it from your secret store onto the runner at job start, reference by `path.module` or an absolute env var path.

## Provider Block — Legacy v3 (Pre-Zidentity Tenants, GOV, ZSCALERTEN)

```hcl
provider "zia" {
  use_legacy_client = true                # gates legacy auth path

  zia_username = var.zia_username
  zia_password = var.zia_password
  zia_api_key  = var.zia_api_key
  zia_cloud    = var.zia_cloud            # zscaler | zscloud | … | zscalergov | zscalerten
}
```

Equivalent env vars: `ZIA_USERNAME`, `ZIA_PASSWORD`, `ZIA_API_KEY`, `ZIA_CLOUD`. The `ZIA_*` env vars are the legacy-namespaced equivalents.

❌ Legacy uses three secrets per tenant (username, password, API key) — protect all three. ✅ Rotate the password and API key separately on a defined cadence.

## Multi-Tenant Layouts

### Single-tenant, single-cloud (typical)

One `provider "zia"` block. Use environment-scoped state (`prod/zia/`, `staging/zia/`).

### Multiple tenants in the same configuration

Use provider aliases.

```hcl
provider "zia" {
  alias         = "tenant_a"
  client_id     = var.tenant_a_client_id
  client_secret = var.tenant_a_client_secret
  vanity_domain = "acme"
}

provider "zia" {
  alias         = "tenant_b"
  client_id     = var.tenant_b_client_id
  client_secret = var.tenant_b_client_secret
  vanity_domain = "globex"
}

resource "zia_url_filtering_rules" "acme_block_gambling" {
  provider = zia.tenant_a
  name     = "Block Gambling"
  state    = "ENABLED"
  action   = "BLOCK"
  order    = 1
  url_categories = ["GAMBLING"]
  protocols      = ["ANY_RULE"]
  request_methods = ["CONNECT", "GET", "POST"]
}
```

❌ Do not put two tenants' resources in the same state file unless you genuinely manage them as one fate. Each tenant has its own activation lifecycle — sharing state means a partial failure leaves one tenant's draft changes stuck.

✅ Prefer one workspace per tenant.

## Credential Hygiene

| ❌ Don't                                                                          | ✅ Do                                                                                    |
| -------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Put `client_secret`, `private_key`, or legacy `password` / `api_key` in checked-in `.tfvars`. | Source from Vault / AWS Secrets Manager / GH Actions secrets, inject as env vars at job start. |
| Echo credentials in CI logs.                                                     | Use `::add-mask::` (GitHub Actions) on every secret your job touches.                   |
| Store `private_key` PEM in the repo.                                             | Mount it onto the runner from a secret store; reference by path.                        |
| Use a single OneAPI client across environments.                                  | Issue one OneAPI client per environment (prod / staging / dev). Rotate on cadence.      |
| Leave sensitive variables unmarked.                                              | `sensitive = true` on every variable carrying a credential.                             |

State considerations:

- The OneAPI client secret is **not** persisted to state — read from provider config at apply time only.
- Configuration data (rule definitions, IDs) **is** in state. Encrypt at rest, restrict access.

## CI/CD Wiring (GitHub Actions sketch)

```yaml
jobs:
  plan:
    runs-on: ubuntu-latest
    env:
      ZSCALER_CLIENT_ID:     ${{ secrets.ZIA_PROD_CLIENT_ID }}
      ZSCALER_CLIENT_SECRET: ${{ secrets.ZIA_PROD_CLIENT_SECRET }}
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

The apply job pulls the plan artifact and runs `terraform apply tfplan` — **never** re-plans inside apply. If you manage `zia_activation_status` in HCL (recommended), activation happens as part of apply.

## Common Auth Errors

| Error message                                       | Cause                                                                                  | Fix                                                                            |
| --------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `401 unauthorized` immediately on init/plan         | Wrong `client_id` / `client_secret`, or wrong `vanity_domain` for the tenant.          | Verify in Zidentity console; confirm `vanity_domain` is the prefix, no FQDN.   |
| `vanity_domain not found`                           | Typo, or tenant not migrated to Zidentity.                                              | Confirm in Zidentity; if not migrated, switch to legacy auth.                  |
| `Cloud zscalergov not supported for OneAPI`         | Tenant on `zscalergov` / `zscalerten` but provider configured for OneAPI.              | Switch to legacy auth (`use_legacy_client = true`).                            |
| `403 access denied` on a specific resource          | The OneAPI client lacks the role/scope needed for that resource (DLP / sandbox / etc.). | Re-issue the OneAPI client with the right role; check Zidentity role mapping. |
