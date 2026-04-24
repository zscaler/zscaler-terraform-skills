# Security & Compliance — Zscaler Terraform

Secrets, scanning, audit, and policy-as-code for Terraform repos that consume the Zscaler providers.

## Decision Table — Where Do Secrets Belong?

| Secret type                                               | Anti-pattern                                          | Recommended                                                                                  |
| --------------------------------------------------------- | ----------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| OneAPI `client_secret` / `private_key`                    | `.tfvars` in git, `var.client_secret`                 | CI secret (`ZSCALER_CLIENT_SECRET`, `ZSCALER_PRIVATE_KEY`). On Terraform 1.11+ use `write_only`. |
| Legacy `password`, `api_key`                              | `.tfvars`, hardcoded                                  | CI secret env vars (`ZIA_PASSWORD`, `ZIA_API_KEY`, etc.).                                    |
| ZPA `customer_id`                                         | Hardcoded — usually not actually a secret             | Set via `ZPA_CUSTOMER_ID` env var; treat as configuration, not credential.                   |
| Federated identity                                        | Long-lived static client credentials                  | OIDC against Zidentity from CI (when supported by your tenant).                              |
| Local development                                         | Real prod credentials on a laptop                     | Dedicated developer client credentials scoped to a sandbox tenant; revoke on offboarding.    |

## Rules — Secrets

- ❌ Never `terraform apply -var "client_secret=..."` from CLI history (logs the secret).
- ❌ Never store credentials in `terraform.tfvars` or `*.auto.tfvars` checked into git.
- ❌ Never put a credential into a `variable` block on Terraform `< 1.11` — it lands in state, even with `sensitive = true`.
- ❌ Never log the provider request body in CI (`TF_LOG=DEBUG` exposes auth headers in some failure paths).
- ❌ Never share a single OneAPI client across multiple microtenants if they have different blast radii.
- ✅ Source credentials from CI secrets via env vars only.
- ✅ On Terraform 1.11+, use `write_only` arguments (e.g. `client_secret_wo`) when the provider supports them — keeps the secret out of state entirely.
- ✅ Rotate static client credentials at most every 90 days; rotate immediately on team change.
- ✅ Use the per-product `ZSCALER_USE_LEGACY_CLIENT=true` env var to make the auth path explicit; **never mix `ZSCALER_*` and `<product>_*` in the same job**.

## `write_only` Pattern (Terraform 1.11+)

When the provider exposes a write-only variant of a credential field, prefer it:

```hcl
provider "zia" {
  # If/when the provider exposes write-only credential attributes,
  # use them so the value is never persisted to state.
  api_key_wo = var.zia_api_key_wo   # write-only variable, also 1.11+
}

variable "zia_api_key_wo" {
  type      = string
  ephemeral = true   # 1.11+: marks the variable as ephemeral
}
```

Until the Zscaler providers expose `*_wo` attributes for every credential field, the env-var-only path remains the safer fallback (the provider reads the env var directly without the value passing through Terraform state).

## Static Analysis & Scanning

### Trivy (config scanning)

```bash
# Install
brew install trivy

# Scan a directory of HCL
trivy config .

# Fail CI on HIGH or CRITICAL findings
trivy config --severity HIGH,CRITICAL --exit-code 1 .
```

What Trivy catches in Zscaler HCL:

- ✅ Secrets accidentally committed (`*.tfvars` files containing `client_secret = "..."`).
- ✅ Insecure backend configuration (state without encryption).
- ⚠️ Generic Terraform misconfigs — the Zscaler-specific catalog is limited.

### Checkov (policy scanning)

```bash
pip install checkov
checkov -d . --framework terraform
```

Checkov has a generic Terraform policy library. To get Zscaler-specific value, write your own custom policies:

```yaml
# .checkov.yaml
external-modules-download-path: /tmp/checkov-modules
custom-policies-dir: ./.checkov/policies
soft-fail-on:
  - CKV_TF_1   # for example, allow non-pinned versions in examples
```

Custom policy examples worth writing:

- "Every `zia_*` resource state must include a `zia_activation_status` resource in the same module."
- "No `zpa_application_segment` may have `domain_names = ["*"]`."
- "Every `zia_url_filtering_rules` must specify an `order >= 1`."

### tflint

```bash
brew install tflint

# Fail on any Terraform-syntax warning
tflint --recursive
```

## Policy-as-Code (OPA / Sentinel)

For organizations using Terraform Cloud / Enterprise or running Conftest in CI:

```rego
# .opa/policies/zscaler/no_wildcard_app_segment.rego
package zscaler.app_segment

deny[msg] {
  resource := input.resource.zpa_application_segment[name]
  resource.domain_names[_] == "*"
  msg := sprintf("zpa_application_segment.%s uses wildcard domain '*' (forbidden in production)", [name])
}
```

```rego
# .opa/policies/zscaler/zia_activation_required.rego
package zscaler.zia_activation

resources_in_state := {name | input.resource.zia_url_filtering_rules[name]}
resources_in_state := {name | input.resource.zia_firewall_filtering_rule[name]}
# … other zia_* resource types

has_activation := count(input.resource.zia_activation_status) > 0

deny[msg] {
  count(resources_in_state) > 0
  not has_activation
  msg := "Configuration creates zia_* resources but does not include a zia_activation_status resource — changes will not take effect."
}
```

Run with Conftest in CI:

```yaml
- name: Generate plan JSON
  run: terraform show -json tfplan > tfplan.json
- name: Conftest
  run: conftest test --policy .opa/policies tfplan.json
```

## Audit Trail for Activation

Every `zia_activation_status` / `ztc_activation_status` apply is a publishable event. CI should:

1. Capture the plan artifact pre-apply.
2. Capture the apply log post-apply.
3. Record the activation timestamp + the user / CI workflow that triggered it.
4. Retain both artifacts for the duration required by your compliance regime (typically 1–7 years).

GitHub Actions: use `actions/upload-artifact` with `retention-days` set to your max retention; mirror critical artifacts to S3 with versioning + Object Lock for tamper-proof retention.

## Compliance Mappings (Common Frameworks)

| Framework requirement                          | How a Zscaler-Terraform repo satisfies it                                                                                |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| SOC 2 CC8.1 (change management)                | PR-required for all Zscaler config changes; reviewer ≠ author; plan artifact retained.                                    |
| SOC 2 CC6.1 (access control)                   | OIDC federation against Zidentity; no static credentials in CI; per-team state isolation.                                 |
| ISO 27001 A.12.1.2 (change management)         | CHANGELOG, conventional commits, semver-tagged releases of any internal modules.                                          |
| PCI DSS 3.2.1 §10 (audit logging)              | CI logs + plan artifacts retained; activation events linked to PR + reviewer.                                             |
| HIPAA §164.312(b) (audit controls)             | Same as PCI §10; ensure tenant-level audit logs in Zscaler are also retained.                                             |
| FedRAMP / GovCloud                             | Use `zscalergov` legacy cloud (no OneAPI yet for GOV); state stored in FedRAMP-authorized backend (e.g. S3 GovCloud).      |

## Rules — Compliance

- ❌ No production change without an approved plan artifact and a named reviewer.
- ❌ No production activation triggered manually from the Zscaler console (no audit trail tying it to a code change).
- ✅ Every `zia_*` / `ztc_*` apply ends with `<product>_activation_status` so the apply log is the activation log.
- ✅ State backend versioning enabled; restore tested at least quarterly.
- ✅ Custom OPA / Conftest policies for the highest-risk patterns (wildcard segments, missing activation, oversized rule scope).

## State File Sensitivity Recap

State contains: resource IDs, configuration attributes (rule names, URL categories), computed attributes (gateway IPs).

State does **not** contain (for any of the four providers):

- OneAPI `client_secret` / `private_key`.
- Legacy `password` / `api_key`.

State **will** contain anything you accidentally put into a `variable` (without `write_only`). Audit your `variables.tf` for any field that takes a credential — it should be either a CI env var or a `*_wo` write-only variable.

Encrypt state at rest (S3 + KMS, GCS CMEK, Azure Storage SSE, Terraform Cloud built-in). Restrict bucket / workspace access to the state's owning team.
