# ZPA — Policy Rules

Policy rules are the highest hallucination surface for LLMs writing ZPA HCL. The schema accepts almost any shape; the API rejects anything not on the right operand matrix. This page is the source of truth.

## Policy Type Map

Each policy rule resource binds to **one** policy set. Always look up `policy_set_id` via the `zpa_policy_type` data source — never hardcode.

| Resource                                | `policy_type` for `data.zpa_policy_type` | Common `action` values                                 |
| --------------------------------------- | ---------------------------------------- | ------------------------------------------------------ |
| `zpa_policy_access_rule`                | `ACCESS_POLICY`                          | `ALLOW`, `DENY`                                        |
| `zpa_policy_access_forwarding_rule`     | `BYPASS_POLICY` (forwarding)             | `BYPASS`, `INTERCEPT`, `INTERCEPT_ACCESSIBLE`          |
| `zpa_policy_access_isolation_rule`      | `ISOLATION_POLICY`                       | `ISOLATE`, `BYPASS_ISOLATE`                            |
| `zpa_policy_access_inspection_rule`     | `INSPECTION_POLICY`                      | `INSPECT`, `BYPASS_INSPECT`                            |

```hcl
data "zpa_policy_type" "access" {
  policy_type = "ACCESS_POLICY"
}
```

❌ Do not pass a literal `policy_set_id` from the console — it varies by tenant and by microtenant.

## Rule Skeleton

```hcl
resource "zpa_policy_access_rule" "<descriptive_name>" {
  name          = "..."          # required
  description   = "..."
  action        = "ALLOW"        # see policy type map
  operator      = "AND"          # AND across condition blocks (typical)
  policy_set_id = data.zpa_policy_type.access.id

  conditions {                   # one or more — each block is its own group
    operator = "OR"              # operator across operands inside this block
    operands {
      object_type = "APP"
      lhs         = "id"
      rhs         = zpa_application_segment.crm.id
    }
    # more operands inside this conditions block ...
  }

  # Add more conditions blocks for additional groups (combined by rule-level operator)
}
```

Composition rules:

- The rule-level `operator` (`AND` / `OR`) joins the **conditions blocks** to each other.
- Each `conditions` block has its own `operator` joining its **operands** to each other.
- Typical pattern: rule-level `AND`, conditions-level `OR`. Read it as: *"all of these condition groups must match, and within each group any operand can match."*

## Operand Reference

The single most error-prone area. `lhs` and `rhs` semantics depend entirely on `object_type`. Get one wrong → API returns `400 INVALID_INPUT` with `Invalid operand type for the given condition` or `LHS value is required for the given operand`.

| `object_type`        | `lhs`                                          | `rhs`                                              | Extra fields                | Notes                                                                                  |
| -------------------- | ---------------------------------------------- | -------------------------------------------------- | --------------------------- | -------------------------------------------------------------------------------------- |
| `APP`                | `"id"`                                         | `zpa_application_segment.<x>.id`                   | —                           | Reference one application segment.                                                     |
| `APP_GROUP`          | `"id"`                                         | `zpa_segment_group.<x>.id`                         | —                           | Reference a segment group (matches all segments in it).                                |
| `SCIM`               | SCIM attribute ID (`data.zpa_scim_attribute_header.<x>.id`) | The attribute value (string)            | `idp_id`                    | Match a SCIM user attribute equal to a value.                                          |
| `SCIM_GROUP`         | `data.zpa_idp_controller.<x>.id` (the IdP ID)  | `data.zpa_scim_groups.<x>.id`                      | `idp_id` (= same IdP ID)    | Match a SCIM group. **`lhs` is the IdP ID, not `"id"`.**                               |
| `SAML`               | `data.zpa_saml_attribute.<x>.id`               | The attribute value, *or* `rhs_list = ["...","..."]` | `idp_id`                  | `rhs_list` allows multi-value match in a single operand.                               |
| `IDP`                | `"id"`                                         | `data.zpa_idp_controller.<x>.id`                   | —                           | Match users from a specific IdP.                                                       |
| `POSTURE`            | `data.zpa_posture_profile.<x>.posture_udid`    | `"true"` or `"false"` (string)                     | —                           | Posture compliant (`"true"`) / non-compliant (`"false"`). **`rhs` is a string.**       |
| `TRUSTED_NETWORK`    | `data.zpa_trusted_network.<x>.network_id`      | `"true"` or `"false"` (string)                     | —                           | On (`"true"`) / off (`"false"`) trusted network.                                       |
| `CLIENT_TYPE`        | `"id"`                                         | One of `zpn_client_type_zapp`, `zpn_client_type_exporter`, `zpn_client_type_browser_isolation`, `zpn_client_type_machine_tunnel`, `zpn_client_type_ip_anchoring`, … | — | Source client type.                                                                    |
| `PLATFORM`           | One of `linux`, `mac`, `windows`, `android`, `ios` | `"true"` (string)                              | —                           | Match the device platform.                                                             |
| `COUNTRY_CODE`       | ISO-3166 two-letter country (`"US"`, `"BR"`)   | `"true"` (string)                                  | —                           | Geographic match on source.                                                            |
| `MACHINE_GRP`        | `"id"`                                         | `zpa_machine_group.<x>.id`                         | —                           | Posture-derived machine group.                                                         |

Quick mental model: for "is this object the one I mean" matches, `lhs = "id"`, `rhs = <object_id>`. For "is this attribute equal to this value" matches (SCIM, SAML, POSTURE, TRUSTED_NETWORK, PLATFORM, COUNTRY_CODE), `lhs = <attribute_or_id>`, `rhs = <value>`.

## Worked Examples

### Allow Engineering SCIM group to CRM

```hcl
resource "zpa_policy_access_rule" "eng_to_crm" {
  name          = "Engineering -> CRM"
  action        = "ALLOW"
  operator      = "AND"
  policy_set_id = data.zpa_policy_type.access.id

  conditions {
    operator = "OR"
    operands {
      object_type = "APP"
      lhs         = "id"
      rhs         = zpa_application_segment.crm.id
    }
  }

  conditions {
    operator = "OR"
    operands {
      object_type = "SCIM_GROUP"
      lhs         = data.zpa_idp_controller.okta.id
      rhs         = data.zpa_scim_groups.engineering.id
      idp_id      = data.zpa_idp_controller.okta.id
    }
  }
}
```

### Deny non-compliant CrowdStrike posture

```hcl
data "zpa_posture_profile" "crwd_zta_40" {
  name = "CrowdStrike_ZPA_ZTA_40"
}

resource "zpa_policy_access_rule" "deny_low_posture" {
  name          = "Deny ZTA < 40"
  action        = "DENY"
  operator      = "AND"
  policy_set_id = data.zpa_policy_type.access.id

  conditions {
    operator = "OR"
    operands {
      object_type = "POSTURE"
      lhs         = data.zpa_posture_profile.crwd_zta_40.posture_udid
      rhs         = "false"           # non-compliant
    }
  }
}
```

### Allow only from US Windows clients

```hcl
resource "zpa_policy_access_rule" "us_windows_only" {
  name          = "US Windows only"
  action        = "ALLOW"
  operator      = "AND"
  policy_set_id = data.zpa_policy_type.access.id

  conditions {
    operator = "OR"
    operands {
      object_type = "APP"
      lhs         = "id"
      rhs         = zpa_application_segment.crm.id
    }
  }

  conditions {
    operator = "AND"
    operands {
      object_type = "PLATFORM"
      lhs         = "windows"
      rhs         = "true"
    }
    operands {
      object_type = "COUNTRY_CODE"
      lhs         = "US"
      rhs         = "true"
    }
  }
}
```

Note the `operator = "AND"` inside the second `conditions` — this requires *both* PLATFORM and COUNTRY_CODE to match, not either.

### SAML multi-value match (`rhs_list`)

```hcl
conditions {
  operator = "OR"
  operands {
    object_type = "SAML"
    lhs         = data.zpa_saml_attribute.email.id
    rhs_list    = ["alice@acme.com", "bob@acme.com"]
    idp_id      = data.zpa_idp_controller.okta.id
  }
}
```

`rhs_list` only works for `object_type = "SAML"` and `"SCIM"`. For others, use multiple `operands` blocks instead.

## Rule Ordering

`zpa_policy_access_rule` does **not** expose a Terraform-managed order field by default — the API auto-assigns ordering when rules are created, and rules created via Terraform run after any predefined / default rules.

If you need explicit ordering:

- ✅ Use `rule_order` attribute (provider 4.x+) and assign **contiguous** integers starting at 1.
- ❌ Do not assign `rule_order = 0` or negative — same footgun as ZIA rule resources.
- ❌ Do not leave gaps. The API may renumber and Terraform sees drift.
- ✅ Manage all rules of the same policy type in **one** Terraform configuration. Splitting them across configs makes ordering impossible to reason about.

```hcl
resource "zpa_policy_access_rule" "first" {
  name       = "First"
  rule_order = 1
  # ...
}

resource "zpa_policy_access_rule" "second" {
  name       = "Second"
  rule_order = 2
  depends_on = [zpa_policy_access_rule.first]
  # ...
}
```

`depends_on` makes the create order deterministic, which avoids transient `rule_order` collisions during initial apply.

## Common Errors

| Error                                                                       | Cause                                                                                       | Fix                                                                                              |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `400 INVALID_INPUT: Invalid operand type for the given condition`           | `object_type` is wrong, or `lhs`/`rhs` shape doesn't match the operand reference table.     | Cross-check against the operand table above.                                                     |
| `400 INVALID_INPUT: LHS value is required for the given operand`            | Forgot `lhs`, or used `lhs = "id"` for an operand that needs an attribute/IdP ID.           | For `SCIM_GROUP`, `lhs = idp_id`. For `POSTURE`, `lhs = posture_udid`.                            |
| `400 INVALID_INPUT: idp_id is required`                                     | Forgot `idp_id` field on a `SCIM` / `SCIM_GROUP` / `SAML` operand.                          | Add `idp_id = data.zpa_idp_controller.<x>.id`.                                                   |
| Rule applied but doesn't match expected users                               | Used `OR` between conditions blocks when you wanted `AND`, or vice versa.                   | Re-read the composition rules above. Rule-level operator joins blocks; block operator joins operands. |
| `terraform plan` shows churn on `conditions` order                          | The API may return conditions in a different order than HCL.                                | See [Troubleshooting: Drift Causes](troubleshooting.md#drift-causes).                            |
| Rule fires but action is wrong                                              | `action` enum mismatch with the policy type. E.g. `ISOLATE` on an access policy.            | Use the action value from the policy type map above.                                             |
