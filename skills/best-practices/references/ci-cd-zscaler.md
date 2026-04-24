# CI/CD for Zscaler Terraform

Pipeline shape, secret handling, and the **Zscaler-specific activation step** that doesn't exist in generic Terraform CI guidance.

## Decision Table — Pipeline Topology

| Repo shape                                                | Pipeline                                                                                            | Notes                                                                                              |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Single state, single provider                             | One pipeline: validate → plan-on-PR → apply-on-merge → activate                                     | Activation as a final step in the same job (ZIA / ZTC).                                            |
| Per-product states (ZPA, ZIA, ZTC, ZCC)                   | One pipeline per product, triggered by path filter                                                  | Independent cadences. Each product's apply runs the activation for its own state (ZIA/ZTC).        |
| Per-microtenant states                                    | One matrix job per microtenant in the product pipeline                                              | Lock-safe (separate states). Use `concurrency:` per microtenant key.                               |
| Atlantis / Spacelift                                       | Stack per state                                                                                     | Activation is a `terragrunt`/stack-level run after apply, not a separate workflow.                 |
| Terraform Cloud / Enterprise                              | Workspace per state, run-trigger to chain activate workspace                                         | Use a separate workspace for activation and a run-trigger from the policy workspace.               |

## Pipeline Stages — The Required Five

1. **Validate** — `fmt -check`, `validate`, `tflint`. Free, fast, runs on every push.
2. **Scan** — `trivy config`, `checkov`. Runs on every PR.
3. **Plan** — `terraform plan -out=tfplan`, save artifact. Posted as PR comment for review.
4. **Apply** — `terraform apply tfplan` against the **reviewed plan artifact**. Never re-runs `plan` inside the apply job.
5. **Activate (ZIA / ZTC only)** — verify the `zia_activation_status` / `ztc_activation_status` resource was applied and is in `ACTIVE` state. ZPA and ZCC have no activation step.

## Activation as a Pipeline Stage

This is what makes Zscaler CI non-generic. After `apply` succeeds for `zia_*` or `ztc_*` resources, the changes are **draft** in the Zscaler tenant until activation. There are three patterns; pick one.

### Pattern A — Activation in the same state (default; recommended for most teams)

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

CI: a single `terraform apply tfplan` activates everything atomically. Simple, auditable, no extra wiring.

❌ Don't list `depends_on` selectively to "stage" activation — partial activation isn't a thing in ZIA. Either everything in the state activates or you're in an inconsistent state.

### Pattern B — Two-stage pipeline (apply first, activate as a separate stage)

When the activation needs a manual approval gate between resource changes and console push, split the activation into a follow-on workflow that an approver triggers explicitly. Same state, two CI jobs:

```yaml
jobs:
  apply:
    # … terraform apply tfplan (without zia_activation_status)
  activate:
    needs: apply
    environment: prod-activation  # GitHub environment with required reviewers
    steps:
      - run: terraform apply -target=zia_activation_status.this
```

Tradeoff: the audit log shows two events per change, and the window between apply-and-activate is observable in the Zscaler tenant as "draft" state.

### Pattern C — Manual console activation (sandbox / break-glass only)

Acceptable for sandbox tenants or genuine emergencies. Document the manual step in the PR description. **Never** do this in production CI without an explicit incident exception — there's no audit trail.

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
