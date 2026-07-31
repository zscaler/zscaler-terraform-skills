# CI/CD for Zscaler Terraform

Pipeline shape, secret handling, and the **Zscaler-specific activation step** that doesn't exist in generic Terraform CI guidance.

## Decision Table — Pipeline Topology

| Repo shape                                                | Pipeline                                                                                            | Notes                                                                                              |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Single state, single provider                             | One pipeline: validate → plan-on-PR → apply-on-merge → activate                                     | Activation as a final step in the same job (ZIA / ZTC).                                            |
| Per-product states (ZPA, ZIA, ZTC, ZCC)                   | One pipeline per product, triggered by path filter                                                  | Independent cadences. Each product's apply runs the activation for its own state (ZIA/ZTC).        |
| Per-microtenant states                                    | One matrix job per microtenant in the product pipeline                                              | ZPA only. Lock-safe (separate states). Use `concurrency:` per microtenant key.                      |
| **Several ZIA / ZTC states, one tenant**                  | Parallel `plan`; `apply` serialised with `max-parallel: 1`; **one** activate job gated on all applies | Tenant has one write lock and one activation queue. Key `concurrency` on the tenant. [Details](#zia--ztc--serialise-on-the-tenant) |
| Atlantis / Spacelift                                       | Stack per state                                                                                     | Activation is a `terragrunt`/stack-level run after apply, not a separate workflow.                 |
| Terraform Cloud / Enterprise                              | Workspace per state, run-trigger to chain activate workspace                                         | Use a separate workspace for activation and a run-trigger from the policy workspace.               |

## Pipeline Stages — The Required Five

1. **Validate** — `fmt -check`, `validate`, `tflint`. Free, fast, runs on every push.
2. **Scan** — `trivy config`, `checkov`. Runs on every PR.
3. **Plan** — `terraform plan -out=tfplan`, save artifact. Posted as PR comment for review.
4. **Apply** — `terraform apply tfplan` against the **reviewed plan artifact**. Never re-runs `plan` inside the apply job.
5. **Activate (ZIA / ZTC only)** — run the `ziaActivator` / `ztcActivator` binary once, as its own stage. If the configuration manages activation in HCL instead, verify the `zia_activation_status` / `ztc_activation_status` resource was applied and is in `ACTIVE` state. ZPA and ZCC have no activation step.

## Activation as a Pipeline Stage

This is what makes Zscaler CI non-generic. After `apply` succeeds for `zia_*` or `ztc_*` resources, the changes are **draft** in the Zscaler tenant until activation.

Three facts drive the choice of pattern:

- **Activation is tenant-wide.** One call publishes every pending change in the tenant. No pipeline ever needs more than one activation call per run — including a pipeline that applies several states.
- **Activation queues behind other editors.** While any other administrator or API session holds unactivated changes, an activation call is queued rather than published, and a queued activation cannot be cancelled. So a per-state activation does not publish that state's changes independently; it waits for every other session, and then publishes their pending work too — including from a run that is still in flight or that failed halfway.
- **The activation endpoint is tightly rate limited** — 10 POST requests per minute and 40 per hour on ZIA. Any design that activates per-resource will hit this.

### Pattern A — Out-of-band activator as a dedicated stage (recommended)

Build the product's activator binary (`ziaActivator` / `ztcActivator`) and run it once after apply:

```yaml
- run: terraform apply -auto-approve tfplan
- name: Activate configuration
  run: ziaActivator      # ztcActivator for ZTC
```

Exactly one activation call per run, timing under explicit control, and — critically — the activation step cannot fall out of step with the resource graph as the configuration grows. This is the right default for any pipeline and the only sane option once the configuration is built from modules. The activator reads the same credentials as the provider, so it needs no separate secret wiring.

Adding an approval gate is natural in this shape, because activation is already its own job:

```yaml
jobs:
  apply:
    # … terraform apply tfplan
  activate:
    needs: apply
    environment: prod-activation  # GitHub environment with required reviewers
    steps:
      - run: ziaActivator
```

### Pattern B — Activation in the same state

```hcl
# main.tf — alongside your zia_* resources
resource "zia_activation_status" "this" {
  status = "ACTIVE"

  depends_on = [
    zia_url_filtering_rules.block_gambling,
    zia_firewall_filtering_rule.allow_finance_egress,
    # … list every resource whose changes must activate together
  ]
}
```

CI: a single `terraform apply tfplan` activates everything atomically, and the activation is visible in `terraform plan`. Reasonable for a single flat state that owns all its resources.

The limitation is `depends_on`, which cannot be inferred: every resource must be listed, and one you forget may be applied *after* activation and silently left draft. In module-based configurations you end up depending on whole modules and maintaining that list forever — prefer Pattern A there.

❌ Don't list `depends_on` selectively to "stage" activation — partial activation isn't a thing in ZIA. Either everything in the state activates or you're in an inconsistent state.

### Pattern C — Manual console activation (sandbox / break-glass only)

Acceptable for sandbox tenants or genuine emergencies. Document the manual step in the PR description. **Never** do this in production CI without an explicit incident exception — there's no audit trail.

### ❌ Anti-pattern — `ZIA_ACTIVATION=true` in a pipeline

Activates in-flight after every create, update, and delete. Because activation is tenant-wide, every call but the last is redundant, and a few dozen resources will exhaust the 40/hour budget inside one apply. The run doesn't fail — rate-limited requests are retried automatically — it just decelerates to the pace of the activation limit. Treat the variable as legacy and leave it unset.

### Session timeout affects long pipelines

ZIA activates pending changes **when a session ends**, including when it ends by hitting the API session timeout (5–20 minutes, default 5). A pipeline whose apply runs longer than the timeout will have changes activated part-way through, before the rest of the configuration is written. The provider re-authenticates and the run continues, so nothing errors — but activation happened at a moment nobody chose.

Raise it to 20 — either in the ZIA Admin Portal under **Administration > Advanced Settings** → **API Session Timeout Duration (In Minutes)** ([docs](https://help.zscaler.com/zia/configuring-advanced-settings#session-timeout)), or via the `api_session_timeout` attribute on `zia_advanced_settings` — and keep individual runs short by splitting large configurations across smaller states. The behaviour is native to the platform and cannot be overridden by the provider, so run duration is the real lever.

**ZTC is stricter: there is no adjustable session timeout.** ZTC exposes no equivalent setting in the provider or the tenant, so for ZTC pipelines short runs are the only mitigation and splitting large configurations across smaller states is mandatory rather than advisory.

## Secret Handling

### OIDC against Zidentity (preferred when supported)

GitHub Actions with OIDC eliminates long-lived static credentials. Once your org has a Zidentity client configured for federated identity:

```yaml
permissions:
  id-token: write   # required for OIDC
  contents: read

jobs:
  apply:
    steps:
      - uses: zscaler/zidentity-oidc-action@v1   # hypothetical / illustrative
        with:
          vanity-domain: ${{ vars.ZSCALER_VANITY_DOMAIN }}
          client-id: ${{ vars.ZSCALER_CLIENT_ID }}
        # exports ZSCALER_OIDC_TOKEN; provider consumes it
      - run: terraform apply tfplan
```

If your tenant doesn't yet support OIDC federation, fall back to static client credentials in encrypted secrets — but **plan to migrate**.

### Static credentials (current default)

```yaml
env:
  TF_VAR_environment: prod

jobs:
  apply:
    steps:
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
      - name: Apply
        env:
          ZSCALER_CLIENT_ID:     ${{ secrets.ZSCALER_CLIENT_ID }}
          ZSCALER_CLIENT_SECRET: ${{ secrets.ZSCALER_CLIENT_SECRET }}
          ZSCALER_VANITY_DOMAIN: ${{ vars.ZSCALER_VANITY_DOMAIN }}
          # ZSCALER_CLOUD only set for non-prod Zidentity environments (e.g. "beta")
          ZPA_CUSTOMER_ID:       ${{ vars.ZPA_CUSTOMER_ID }}
        run: terraform apply tfplan
```

Rules:

- ❌ Never `echo` a secret in a CI step.
- ❌ Never log full provider HTTP request bodies (use `TF_LOG=INFO` not `DEBUG` in CI; the provider redacts secrets in `INFO` and below).
- ❌ Never mix `ZSCALER_*` and `<product>_*` env vars in the same job — the provider picks one auth path based on `use_legacy_client` and silently ignores the other namespace.
- ✅ Rotate static client credentials on a schedule (90 days max) and revoke immediately on team-member departure.

### Per-auth-path env-var matrix

| Auth path           | Required                                                                              | Optional                                       |
| ------------------- | ------------------------------------------------------------------------------------- | ---------------------------------------------- |
| OneAPI (Zidentity)  | `ZSCALER_CLIENT_ID`, `ZSCALER_CLIENT_SECRET` (or `ZSCALER_PRIVATE_KEY`), `ZSCALER_VANITY_DOMAIN` | `ZSCALER_CLOUD` (only for non-prod, e.g. `beta`) |
| ZPA OneAPI          | …above + `ZPA_CUSTOMER_ID`                                                            | `ZPA_MICROTENANT_ID`                           |
| ZPA legacy          | `ZPA_CLIENT_ID`, `ZPA_CLIENT_SECRET`, `ZPA_CUSTOMER_ID`                               | `ZPA_CLOUD` (only when not `PRODUCTION`)        |
| ZIA legacy          | `ZIA_USERNAME`, `ZIA_PASSWORD`, `ZIA_API_KEY`, `ZIA_CLOUD`, `ZSCALER_USE_LEGACY_CLIENT=true` | —                                              |
| ZTC legacy          | `ZTC_USERNAME`, `ZTC_PASSWORD`, `ZTC_API_KEY`, `ZTC_CLOUD`, `ZSCALER_USE_LEGACY_CLIENT=true` | —                                              |
| ZCC legacy          | `ZCC_CLIENT_ID`, `ZCC_CLIENT_SECRET`, `ZCC_CLOUD`, `ZSCALER_USE_LEGACY_CLIENT=true`   | —                                              |

Cross-product equivalence for the env-var matrix lives in [Cross-Product Equivalents: Auth Env-Var Matrix](cross-product-equivalents.md#auth-env-var-matrix).

## State-Backend Auth from CI (Cross-Cloud)

A Zscaler-Terraform job typically needs **two distinct auth paths**: one to talk to the Zscaler API (Zidentity OneAPI or legacy v3 — see above), and one to read/write Terraform state on the host cloud's backend (AWS S3 / Azure Storage / GCS / Terraform Cloud).

Use keyless federation for the host-cloud path whenever possible; long-lived static cloud credentials in CI are a separate compliance liability from the Zscaler credentials.

### OIDC Trust Policy Correctness — Per CI Host × Host Cloud

| CI host          | Host cloud         | Expected `aud`                                | Where to pin `sub`                                        |
| ---------------- | ------------------ | --------------------------------------------- | --------------------------------------------------------- |
| GitHub Actions   | AWS                | `sts.amazonaws.com`                           | `repo:<org>/<repo>:ref:refs/heads/<branch>`                |
| GitHub Actions   | Azure              | `api://AzureADTokenExchange`                  | `repo:<org>/<repo>:environment:<env>`                      |
| GitHub Actions   | GCP                | value passed via `audience` parameter         | repo + ref or environment                                  |
| GitHub Actions   | Terraform Cloud    | `terraform.io` (configured per workspace)     | `organization:<org>:project:<proj>:workspace:<ws>:run_phase:<plan\|apply>` |
| GitLab CI        | AWS                | matches `$CI_SERVER_URL`                      | project path + ref                                         |
| GitLab CI        | Azure              | `api://AzureADTokenExchange`                  | project path + ref                                         |
| GitLab CI        | GCP                | value passed via `audience` parameter         | project path + ref                                         |

Rules:

- ✅ Pin `aud` to the exact value from the table.
- ✅ Pin `sub` to a specific repo + branch or environment — never wildcards across an org.
- ❌ `sub` wildcards like `repo:*:*` or `repo:<org>/*:ref:*` let any repo assume the role.
- ❌ Mismatched `aud` → token rejected with an opaque error; fix `aud` per the table, do not relax `sub`.

### Example — GitHub Actions → AWS S3 backend + Zidentity OneAPI

Two distinct credential paths in one job. Keep them as separate steps; do not mix env-var namespaces.

```yaml
permissions:
  id-token: write   # required for OIDC to AWS AND to Zidentity (if your tenant supports it)
  contents: read

jobs:
  apply:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Step 1: federate to AWS for S3 backend access
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/zscaler-tf-prod
          aws-region: us-east-1
          # No static AWS keys — token exchange only.

      # Step 2: provide Zidentity OneAPI credentials to the Zscaler provider
      - uses: hashicorp/setup-terraform@v3
      - name: Apply
        env:
          ZSCALER_CLIENT_ID:     ${{ secrets.ZSCALER_CLIENT_ID }}
          ZSCALER_CLIENT_SECRET: ${{ secrets.ZSCALER_CLIENT_SECRET }}
          ZSCALER_VANITY_DOMAIN: ${{ vars.ZSCALER_VANITY_DOMAIN }}
          ZPA_CUSTOMER_ID:       ${{ vars.ZPA_CUSTOMER_ID }}
        run: terraform apply tfplan
```

### Example — GitHub Actions → GCS backend + Zidentity OneAPI

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  apply:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Step 1: federate to GCP for GCS backend access
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: projects/123/locations/global/workloadIdentityPools/github/providers/github
          service_account: zscaler-tf-prod@acme-prod.iam.gserviceaccount.com

      # Step 2: Zidentity OneAPI credentials (same as above)
      - uses: hashicorp/setup-terraform@v3
      - name: Apply
        env:
          ZSCALER_CLIENT_ID:     ${{ secrets.ZSCALER_CLIENT_ID }}
          ZSCALER_CLIENT_SECRET: ${{ secrets.ZSCALER_CLIENT_SECRET }}
          ZSCALER_VANITY_DOMAIN: ${{ vars.ZSCALER_VANITY_DOMAIN }}
        run: terraform apply tfplan
```

### Example — GitHub Actions → Azure Storage backend + Zidentity OneAPI

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  apply:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Step 1: federate to Azure for storage-account access
      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
          # federated credential pinned to repo + environment

      # Step 2: Zidentity OneAPI credentials
      - uses: hashicorp/setup-terraform@v3
      - name: Apply
        env:
          ARM_USE_OIDC:          true   # Azure backend consumes the federated token
          ZSCALER_CLIENT_ID:     ${{ secrets.ZSCALER_CLIENT_ID }}
          ZSCALER_CLIENT_SECRET: ${{ secrets.ZSCALER_CLIENT_SECRET }}
          ZSCALER_VANITY_DOMAIN: ${{ vars.ZSCALER_VANITY_DOMAIN }}
        run: terraform apply tfplan
```

❌ Putting AWS / Azure / GCP static keys in `secrets.*` when OIDC federation is available on your CI host.
❌ Reusing the same trust policy for plan and apply jobs — pin `sub` separately so the apply role cannot be assumed from a plan-only context.
❌ Mixing the Zscaler env-var namespace with the cloud-provider env-var namespace in shell `export`s — keep each in its own step.
✅ Two separate credential steps per job. State-backend auth ≠ Zscaler API auth.
✅ Drift-detection jobs that only need plan-time read access can use a separate, less-privileged trust policy and a read-only AWS / Azure / GCP role.

## Plan-Artifact Discipline

The plan you apply must be the plan that was reviewed. Do not re-run `plan` inside the apply job.

```yaml
jobs:
  plan:
    outputs:
      plan-id: ${{ steps.upload.outputs.artifact-id }}
    steps:
      - run: terraform plan -out=tfplan
      - id: upload
        uses: actions/upload-artifact@v4
        with: { name: tfplan, path: tfplan }
  apply:
    needs: plan
    steps:
      - uses: actions/download-artifact@v4
        with: { name: tfplan }
      - run: terraform apply tfplan
```

❌ `terraform apply` without the saved plan = re-planning at apply-time = the apply may diverge from what was reviewed.

## Concurrency & Microtenants

Per-microtenant state files allow per-microtenant CI parallelism. Use GitHub Actions matrix:

```yaml
jobs:
  apply:
    strategy:
      matrix:
        microtenant: [finance, sales, support]
    concurrency:
      group: zpa-${{ matrix.microtenant }}
      cancel-in-progress: false
    steps:
      - run: terraform apply tfplan
        working-directory: infrastructure/zpa/prod/microtenant-${{ matrix.microtenant }}
```

`concurrency.group` per-microtenant prevents two apply jobs against the same microtenant state from racing; `cancel-in-progress: false` keeps the in-flight apply from being aborted by a newer push.

### ZIA / ZTC — Serialise on the Tenant

**Do not copy the ZPA matrix above for ZIA or ZTC.** It is safe on ZPA because ZPA has no tenant-wide write lock and no activation step. ZIA and ZTC have both, so multiple states against one tenant must apply **one at a time**:

```yaml
jobs:
  apply:
    strategy:
      matrix:
        state: [firewall-rules, url-filtering, dlp, locations]
      max-parallel: 1                      # applies run one at a time
    concurrency:
      group: zia-apply-${{ inputs.tenant }}  # key on the TENANT, not the state
      cancel-in-progress: false
    steps:
      - run: terraform apply tfplan
        working-directory: infrastructure/zia/prod/${{ matrix.state }}

  activate:
    needs: apply                            # once, after every state is applied
    steps:
      - run: ziaActivator
```

Two details matter. The concurrency key must be the tenant, because two different repos or pipelines pointing at the same tenant still collide. And activation is a single job gated on `needs: apply`, not a step inside each matrix leg.

`plan` jobs can still run fully parallel — reads do not take the write lock, so PR feedback is unaffected. Only `apply` needs the mutex.

Concurrent ZIA applies produce `EDIT_LOCK_NOT_AVAILABLE` / `Failed during enter Org barrier`, which the provider retries — so the failure looks like a slow pipeline rather than a conflict. See [State Management: Concurrency Is a Tenant Property](state-management.md#concurrency-is-a-tenant-property-not-a-state-property).

## GitLab CI Sketch

```yaml
stages: [validate, scan, plan, apply, activate]

validate:
  stage: validate
  script:
    - terraform fmt -check -recursive
    - terraform init -backend=false
    - terraform validate

scan:
  stage: scan
  script:
    - trivy config .
    - checkov -d .

plan:
  stage: plan
  script:
    - terraform init
    - terraform plan -out=tfplan
  artifacts:
    paths: [tfplan]

apply:
  stage: apply
  script:
    - terraform init
    - terraform apply tfplan
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
  needs: [plan]

activate-verify:
  stage: activate
  script:
    - |
      # Optional: query the ZIA API to verify the activation took effect
      # (the apply step already activated via zia_activation_status)
      echo "Activation verified by zia_activation_status resource"
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
  needs: [apply]
```

## Atlantis / Spacelift

- Atlantis: each state path is a separate Atlantis workspace with `apply_requirements: [approved]`. Activation is part of the `terraform apply` step (Pattern A above).
- Spacelift: stack per state. Use stack dependencies to chain activation if you want Pattern B.

## Cost Control

Zscaler API calls are not metered like cloud-provider calls, but unbounded plan/apply churn against a production tenant is still rude:

- ✅ Schedule full-tenant drift detection (`terraform plan` against every state) at low frequency (daily, not per-commit).
- ✅ Skip the "scan" stage on doc-only PRs (`paths-ignore` for `*.md`).
- ❌ Don't run integration tests against the production tenant in PR CI. Use a sandbox tenant.
