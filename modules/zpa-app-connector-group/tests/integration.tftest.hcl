# integration.tftest.hcl — apply-mode tests against a SANDBOX tenant (terraform ~> 1.6)
#
# Prerequisites:
#   export ZSCALER_CLIENT_ID="<sandbox-client-id>"
#   export ZSCALER_CLIENT_SECRET="<sandbox-client-secret>"
#   export ZSCALER_VANITY_DOMAIN="<sandbox-vanity-domain>"
#   export ZPA_CUSTOMER_ID="<sandbox-customer-id>"
#
# NEVER run against production credentials.
# ZPA has no activation step — changes take effect on apply.
# Resources are destroyed automatically when terraform test completes.

variables {
  name         = "ci-test-acg"
  description  = "managed-by:ci ttl:24h"
  country_code = "US"
  city_country = "Ashburn, US"
  latitude     = "39.0438"
  longitude    = "-77.4874"
  location     = "Ashburn, VA, US"
  enabled      = true
}

run "creates_app_connector_group" {
  command = apply

  assert {
    condition     = zpa_app_connector_group.this.id != ""
    error_message = "App Connector Group was not created (id is empty)."
  }

  assert {
    condition     = zpa_app_connector_group.this.name == "ci-test-acg"
    error_message = "App Connector Group name does not match input."
  }

  assert {
    condition     = zpa_app_connector_group.this.enabled == true
    error_message = "App Connector Group must be enabled."
  }

  assert {
    condition     = zpa_app_connector_group.this.country_code == "US"
    error_message = "country_code must be US."
  }

  assert {
    condition     = zpa_app_connector_group.this.dns_query_type == "IPV4_IPV6"
    error_message = "dns_query_type default must be IPV4_IPV6."
  }
}

run "update_upgrade_day_to_saturday" {
  command = apply

  variables {
    upgrade_day = "SATURDAY"
  }

  assert {
    condition     = zpa_app_connector_group.this.upgrade_day == "SATURDAY"
    error_message = "upgrade_day update did not apply."
  }
}

run "enable_version_profile_override" {
  command = apply

  variables {
    upgrade_day              = "SATURDAY"
    override_version_profile = true
    version_profile_id       = "1"
  }

  assert {
    condition     = zpa_app_connector_group.this.override_version_profile == true
    error_message = "override_version_profile must be true."
  }

  assert {
    condition     = zpa_app_connector_group.this.version_profile_id == "1"
    error_message = "version_profile_id must be 1 (Previous)."
  }
}
