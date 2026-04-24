# Testing & Validation — Zscaler Terraform

How to test HCL that targets the Zscaler providers — what works, what doesn't, and what's specifically different from generic Terraform testing guidance.

## Decision Table — Which Approach for Which Goal?

| Situation                                                  | Approach                                                              | Tools                                          | Where to run                       |
| ---------------------------------------------------------- | --------------------------------------------------------------------- | ---------------------------------------------- | ---------------------------------- |
| Catch syntax / typo errors                                 | Static                                                                | `terraform fmt -check`, `terraform validate`   | Pre-commit + every PR              |
| Catch policy / shape violations (no wildcard segments etc) | Static + custom OPA / Conftest                                         | `conftest`, `checkov`, `tflint`                | Every PR                           |
| Validate input shape (variable validation)                 | `terraform test` (1.6+) with `command = plan`                          | Native test framework                          | Every PR (free, no API calls)      |
| Validate computed output shape (without API)               | `terraform test` (1.7+) with `mock_provider`                          | Native test framework + mocks                  | Every PR (free)                    |
| Validate against real Zscaler API behavior                 | `terraform test` with `command = apply` against a **sandbox tenant** | Native test framework + sandbox tenant         | Merge to main (real cost in time)  |
| Full integration with downstream apps                      | Terratest (or `terraform test` w/ `apply` + assertions)              | Go + sandbox tenant                            | Nightly / pre-release              |

## What Doesn't Work

- ❌ **`mock_provider` cannot validate Zscaler API behavior.** Mocks return whatever values you specify; they will happily accept invalid attribute combinations that the real API rejects. Mocks catch *input shape* bugs, not *API contract* bugs. Pair mocks with sandbox-tenant integration runs.
- ❌ **No "dry-run" mode for activation.** `zia_activation_status` either activates or doesn't. There is no way to test activation without actually pushing changes to a tenant.
- ❌ **`terraform plan` cannot detect rule-ordering conflicts** until apply — the order check is server-side. Test orderings against a sandbox tenant.

## Sandbox Tenant Strategy

You need a non-prod Zscaler tenant for integration testing. Three patterns:

| Pattern                            | When                                                   | Tradeoff                                                                       |
| ---------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------ |
| Dedicated sandbox tenant           | Most teams                                             | Real API behavior, no production blast radius. Cost: tenant license.            |
| Beta / preview cloud               | Early-access feature testing                           | OneAPI: set `ZSCALER_CLOUD = "beta"`. Get newest features but less stable.      |
| Microtenant in production tenant   | When sandbox tenant isn't an option                    | Cheaper. Risk: misconfiguration leaks across microtenant boundaries.            |

Tag every test resource with a unique CI-run identifier so a sweeper job can clean orphans:

```hcl
resource "zpa_application_segment" "test" {
  name        = "ci-test-${var.test_run_id}-app"
  description = "managed-by:ci ci-run:${var.test_run_id}"
  # …
}
```

## Native Test Framework — What Works

### Input shape validation (Terraform 1.6+)

```hcl
# tests/inputs.tftest.hcl

variables {
  app_name      = "ci-test-app"
  domain_names  = ["test.example.com"]
  tcp_ports     = ["443", "443"]
}

run "rejects_empty_domain_list" {
  command = plan

  variables {
    domain_names = []
  }

  expect_failures = [var.domain_names]
}

run "accepts_minimum_inputs" {
  command = plan
  # uses defaults from the variables {} block above
}
```

Runs `terraform plan` only — no API calls, no cost. Catches:

- Variable validation block failures.
- Missing required variables.
- Type mismatches.
- Conditional resource counts (`count = condition ? 1 : 0`) producing 0 or 1 as expected.

### Mock provider tests (Terraform 1.7+)

```hcl
# tests/mock.tftest.hcl

mock_provider "zia" {
  mock_resource "zia_url_filtering_rules" {
    defaults = {
      id    = "12345"
      order = 1
    }
  }
}

run "url_filtering_rule_has_expected_categories" {
  command = plan

  assert {
    condition     = length(zia_url_filtering_rules.this.url_categories) > 0
    error_message = "URL categories must be non-empty."
  }
}
```

Useful for validating module-level wiring without API calls. Limitations:

- ❌ Cannot validate that the API would accept the request.
- ❌ Cannot detect rule-ordering conflicts.
- ❌ Cannot detect DUPLICATE_ITEM-style errors (duplicate rule names within a tenant).

### Apply-mode tests against a sandbox tenant

```hcl
# tests/integration.tftest.hcl

variables {
  test_run_id = "ci-run-${formatdate("YYYYMMDDhhmmss", timestamp())}"
}

run "creates_url_filtering_rule" {
  command = apply

  variables {
    rule_name      = "ci-test-${var.test_run_id}-block-gambling"
    url_categories = ["GAMBLING"]
    order          = 1000   # high order to avoid collision with existing rules
  }

  assert {
    condition     = zia_url_filtering_rules.this.id != ""
    error_message = "Rule was not created."
  }
}
```

CI must run with the sandbox-tenant credentials (separate from production CI secrets). After the test, clean up:

```bash
terraform destroy -auto-approve
```

For ZIA / ZTC, the destroy must include re-activating to push the deletion live:

```hcl
# tests/integration.tftest.hcl
run "cleanup_activation" {
  command = apply

  module {
    source = "./tests/modules/activate"  # tiny module that just declares zia_activation_status
  }
}
```

## Static Analysis Pipeline (free, runs on every PR)

```bash
#!/usr/bin/env bash
set -euo pipefail

terraform fmt -check -recursive
terraform init -backend=false
terraform validate

tflint --recursive

trivy config --severity HIGH,CRITICAL --exit-code 1 .
checkov -d . --framework terraform --soft-fail-on CKV_TF_1
```

Run as a GitHub Actions matrix job per Terraform module path:

```yaml
strategy:
  matrix:
    path: [infrastructure/zpa/prod, infrastructure/zia/prod, infrastructure/ztc/prod]
steps:
  - uses: hashicorp/setup-terraform@v3
  - run: ./.ci/static-checks.sh
    working-directory: ${{ matrix.path }}
```

## Common LLM / Author Mistakes (Native Tests)

- ❌ Using `command = plan` to assert on a computed attribute (e.g. `id` of a not-yet-created resource). Computed attributes are unknown at plan time. Use `command = apply`.
- ❌ Indexing into a set-type nested block with `[0]` (sets aren't ordered). Materialize via apply or use `for` expressions.
- ❌ Asserting on an attribute that isn't in the published schema. Cross-check against the Registry page.
- ❌ Forgetting `expect_failures` when testing a variable-validation block — without it, the test fails because the validation triggers.

## Sweeper Job — Don't Leak Test Resources

```yaml
# .github/workflows/sweep-sandbox.yml
on:
  schedule:
    - cron: '0 6 * * *'   # daily at 06:00 UTC

jobs:
  sweep:
    steps:
      - name: List candidate test resources older than 24h
        run: |
          # Use the Zscaler API or terraform_remote_state on a "scoreboard"
          # state file that records test_run_ids and their TTLs.
          ./scripts/sweep-stale-test-resources.sh
```

Conventions:

- Every test resource carries `name = "ci-test-${run-id}-..."` and `description = "managed-by:ci ttl:24h"`.
- Sweeper queries by name prefix and deletes older than TTL.
- For ZIA / ZTC, the sweeper apply must include `zia_activation_status` to push the deletes live.

## Pre-Commit (Local Loop)

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.96.1
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tflint
      - id: terraform_trivy
```

Catches issues before push; same checks rerun in CI as the source of truth.

## Acceptance Criteria — When Is a PR "Tested"?

| Risk tier         | Required tests                                                                                               |
| ----------------- | ------------------------------------------------------------------------------------------------------------ |
| Doc-only          | `terraform fmt -check`                                                                                        |
| Module change     | All static checks + `terraform test` (plan + mock).                                                          |
| New resource type | All static checks + `terraform test` (plan + mock + apply against sandbox tenant) + manual sandbox verification.|
| Production change | All of the above + reviewed plan artifact + named approver + post-deploy verification step.                  |
