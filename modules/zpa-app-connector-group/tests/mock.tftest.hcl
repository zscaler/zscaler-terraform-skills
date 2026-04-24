# mock.tftest.hcl — module wiring tests using a mock provider (terraform ~> 1.7)
# Validates output wiring and resource attribute propagation without real API calls.
# Limitation: mock cannot validate Zscaler API acceptance — pair with integration tests.

mock_provider "zpa" {
  mock_resource "zpa_app_connector_group" {
    defaults = {
      id   = "mock-acg-00000000"
      name = "mock-name"
    }
  }
}

variables {
  name         = "us-east-1-mock"
  country_code = "US"
  latitude     = "39.0438"
  longitude    = "-77.4874"
  location     = "Ashburn, VA, US"
}

run "output_id_is_non_empty" {
  command = apply

  assert {
    condition     = output.id != ""
    error_message = "id output must be non-empty after apply."
  }
}

run "output_name_matches_input" {
  command = apply

  assert {
    condition     = output.name == var.name
    error_message = "name output must equal the input variable."
  }
}

run "override_version_profile_propagates" {
  command = apply

  variables {
    override_version_profile = true
    version_profile_id       = "2"
  }

  assert {
    condition     = zpa_app_connector_group.this.override_version_profile == true
    error_message = "override_version_profile must be true when set."
  }

  assert {
    condition     = zpa_app_connector_group.this.version_profile_id == "2"
    error_message = "version_profile_id must be \"2\" (New Release)."
  }
}

run "microtenant_id_propagates_when_set" {
  command = apply

  variables {
    microtenant_id = "mt-00000000-0000-0000-0000-000000000001"
  }

  assert {
    condition     = zpa_app_connector_group.this.microtenant_id == "mt-00000000-0000-0000-0000-000000000001"
    error_message = "microtenant_id must be forwarded to the resource."
  }
}

run "microtenant_id_is_null_by_default" {
  command = apply

  assert {
    condition     = zpa_app_connector_group.this.microtenant_id == null
    error_message = "microtenant_id should be null when not supplied."
  }
}

run "dns_query_type_defaults_to_ipv4_ipv6" {
  command = apply

  assert {
    condition     = zpa_app_connector_group.this.dns_query_type == "IPV4_IPV6"
    error_message = "dns_query_type default must be IPV4_IPV6."
  }
}
