# ZCC — Auth & Providers

How to configure the `zscaler/zcc` provider correctly. ZCC has a key trap: **OneAPI and legacy ZCC v2 use different env-var namespaces**, and the provider will silently pick one based on `use_legacy_client`.

## Decision Table — Pick the Auth Mode

| Goal                                                | Use                              | Tradeoff                                                                     |
| --------------------------------------------------- | -------------------------------- | ---------------------------------------------------------------------------- |
| Tenant migrated to Zidentity (most modern tenants)  | OneAPI client credentials        | Requires Zidentity onboarding.                                               |
| OneAPI tenant + JWT-style cert auth                 | OneAPI private key (PEM)         | More setup; supports key rotation without distributing a shared secret.      |
| Tenant **not** migrated to Zidentity                | Legacy ZCC v2 client credentials | Will need to migrate when tenant moves to Zidentity.                         |

If the user does not say which they have, **ask**. Do not silently default to OneAPI — many production tenants are still on legacy.

## Cloud Selector — Two Different Attributes

`zscaler_cloud` (OneAPI) and `zcc_cloud` (legacy) are **not** the same and accept different values.

### OneAPI: `zscaler_cloud` — OPTIONAL, Zidentity environment selector only

| Value     | When                                                                                            |
| --------- | ----------------------------------------------------------------------------------------------- |
| *(unset)* | **Default — production Zidentity.** Use this for all production tenants.                        |
| `beta`    | Zidentity beta environment, for pre-release validation. Never set for production state.          |

❌ Do not pass legacy cloud names to `zscaler_cloud`. ✅ Omit `zscaler_cloud` entirely for production OneAPI.

### Legacy: `zcc_cloud` — names the actual cloud

| Value           | When                                                                  |
| --------------- | --------------------------------------------------------------------- |
| `zscaler`       | Default for commercial tenants.                                       |
| `zscloud`       | Commercial cloud — set if your tenant is provisioned on it.           |
| `zscalerbeta`   | Pre-release features; for testing only.                               |
| `zscalerone`    | Commercial cloud.                                                     |
| `zscalertwo`    | Commercial cloud.                                                     |
| `zscalerthree`  | Commercial cloud.                                                     |

## Provider Block — OneAPI Client Credentials

```hcl
terraform {
  required_version = "~> 1.9"
  required_providers {
    zcc = {
      source  = "zscaler/zcc"
      version = "~> 0.1.0"
    }
  }
}

provider "zcc" {
  # Prefer env vars in CI; this block is for explicit local overrides.
  client_id     = var.zcc_client_id
  client_secret = var.zcc_client_secret
  vanity_domain = var.zcc_vanity_domain
  # zscaler_cloud = "beta"   # OPTIONAL — only set for non-prod Zidentity environments.
}
```

Equivalent OneAPI env vars:

| Env var                  | Maps to            | Required?                  |
| ------------------------ | ------------------ | -------------------------- |
| `ZSCALER_CLIENT_ID`      | `client_id`        | Yes                        |
| `ZSCALER_CLIENT_SECRET`  | `client_secret`    | Yes (or `ZSCALER_PRIVATE_KEY`) |
| `ZSCALER_PRIVATE_KEY`    | `private_key`      | Alternative to `client_secret` |
| `ZSCALER_VANITY_DOMAIN`  | `vanity_domain`    | Yes                        |
| `ZSCALER_CLOUD`          | `zscaler_cloud`    | **No** — only for non-prod (e.g. `beta`) |

## Provider Block — OneAPI Private Key

```hcl
provider "zcc" {
  client_id     = var.zcc_client_id
  private_key   = file("${path.module}/zcc_private.pem")
  vanity_domain = var.zcc_vanity_domain
  # zscaler_cloud = "beta"   # OPTIONAL
}
```

❌ Do not commit the `.pem` to git. ✅ Mount it from your secret store onto the runner at job start, reference by `path.module` or an absolute env var path.

## Provider Block — Legacy ZCC v2 Client

```hcl
provider "zcc" {
  use_legacy_client = true

  zcc_client_id     = var.zcc_legacy_client_id
  zcc_client_secret = var.zcc_legacy_client_secret
  zcc_cloud         = var.zcc_legacy_cloud      # zscaler | zscloud | …
}
```

Equivalent legacy env vars:

| Env var                       | Maps to              |
| ----------------------------- | -------------------- |
| `ZCC_CLIENT_ID`               | `zcc_client_id`      |
| `ZCC_CLIENT_SECRET`           | `zcc_client_secret`  |
| `ZCC_CLOUD`                   | `zcc_cloud`          |
| `ZSCALER_USE_LEGACY_CLIENT`   | `use_legacy_client`  |

## The Env Var Trap

OneAPI and legacy ZCC v2 use **different** env-var prefixes (`ZSCALER_*` vs `ZCC_*`). The provider picks which path to use based on `use_legacy_client` (or `ZSCALER_USE_LEGACY_CLIENT`). The unused namespace is silently ignored.

❌ **Wrong** — mixing namespaces:

```bash
# Looks fine, but provider will use OneAPI (because use_legacy_client is false by default)
# and silently ignore ZCC_* vars
export ZSCALER_CLIENT_ID=…
export ZCC_CLIENT_SECRET=…    # ignored!
terraform plan   # 401: client_secret is empty
```

✅ **Right** — pick one namespace and stick with it:

```bash
# OneAPI:
export ZSCALER_CLIENT_ID=…
export ZSCALER_CLIENT_SECRET=…
export ZSCALER_VANITY_DOMAIN=acme

# OR legacy:
export ZSCALER_USE_LEGACY_CLIENT=true
export ZCC_CLIENT_ID=…
export ZCC_CLIENT_SECRET=…
export ZCC_CLOUD=zscaler
```

In CI, gate the env vars by which auth mode the workspace uses — never set both.

## Optional Provider Tuning

| Argument            | Default | When to set                                                                                        |
| ------------------- | ------- | -------------------------------------------------------------------------------------------------- |
| `http_proxy`        | unset   | Local caching proxy / corporate egress (`ZSCALER_HTTP_PROXY` env).                                 |
| `parallelism`       | reserved| Reserved for bulk operations; leave at default.                                                    |
| `max_retries`       | SDK default | Lower for fast-fail environments; raise for flaky network paths.                              |
| `request_timeout`   | per-request | Set in seconds when running behind aggressive idle-timeout middleware.                         |
| `min_wait_seconds`  | SDK default | Lower bound for retry backoff.                                                                |
| `max_wait_seconds`  | SDK default | Upper bound for retry backoff.                                                                |

## Multi-Tenant Layouts

ZCC tenants follow the same pattern as ZIA — typically one tenant per company. Use **provider aliases** if you genuinely manage multiple tenants from one configuration:

```hcl
provider "zcc" {
  alias         = "tenant_a"
  client_id     = var.tenant_a_client_id
  client_secret = var.tenant_a_client_secret
  vanity_domain = "acme"
}

provider "zcc" {
  alias         = "tenant_b"
  client_id     = var.tenant_b_client_id
  client_secret = var.tenant_b_client_secret
  vanity_domain = "globex"
}

resource "zcc_trusted_network" "acme_corp_office" {
  provider     = zcc.tenant_a
  network_name = "Corp Office"
  active       = true
}
```

❌ Do not put two tenants' resources in the same state file unless you genuinely manage them as one fate.

## Credential Hygiene

| ❌ Don't                                                                          | ✅ Do                                                                                    |
| -------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Put `client_secret` / `private_key` / `zcc_client_secret` in checked-in `.tfvars`. | Source from Vault / Secrets Manager / GH Actions secrets, inject as env vars at job start. |
| Echo credentials in CI logs.                                                     | Use `::add-mask::` (GitHub Actions) on every secret.                                    |
| Store `private_key` PEM in the repo.                                             | Mount it onto the runner from a secret store; reference by path.                        |
| Mix OneAPI and legacy env vars in the same job.                                  | Gate by `use_legacy_client`; only set the matching namespace.                           |
| Use a single OneAPI client across environments.                                  | Issue one OneAPI client per environment. Rotate on cadence.                             |
| Leave sensitive variables unmarked.                                              | `sensitive = true` on every variable carrying a credential.                             |

## CI/CD Wiring (GitHub Actions sketch — OneAPI)

```yaml
jobs:
  plan:
    runs-on: ubuntu-latest
    env:
      ZSCALER_CLIENT_ID:     ${{ secrets.ZCC_PROD_CLIENT_ID }}
      ZSCALER_CLIENT_SECRET: ${{ secrets.ZCC_PROD_CLIENT_SECRET }}
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

| Error message                                       | Cause                                                                                  | Fix                                                                            |
| --------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `401 unauthorized` immediately on init/plan         | Wrong credentials; mixed env-var namespaces (see [The Env Var Trap](#the-env-var-trap)). | Verify in Zidentity console; use only one namespace.                          |
| `vanity_domain not found`                           | Typo, or tenant not migrated to Zidentity.                                              | Confirm in Zidentity; if not migrated, switch to legacy auth.                  |
| `403 access denied` on a specific resource          | The OneAPI client lacks the role/scope needed for ZCC.                                 | Re-issue the OneAPI client with the right role; verify in Zidentity.           |
| `client_secret is required`                         | Set `ZCC_CLIENT_SECRET` but provider is in OneAPI mode (default).                       | Either set `ZSCALER_CLIENT_SECRET` (OneAPI) or `use_legacy_client = true`.     |
