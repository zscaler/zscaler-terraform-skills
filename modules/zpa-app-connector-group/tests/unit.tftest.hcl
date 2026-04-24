# unit.tftest.hcl — input-validation tests (terraform ~> 1.6)
# command = plan only: zero API calls, no credentials required.

variables {
  name         = "us-east-1-unit"
  country_code = "US"
  latitude     = "39.0438"
  longitude    = "-77.4874"
  location     = "Ashburn, VA, US"
}

# ── name ───────────────────────────────────────────────────────────────────────

run "rejects_blank_name" {
  command = plan
  variables { name = "   " }
  expect_failures = [var.name]
}

# ── country_code ───────────────────────────────────────────────────────────────

run "rejects_three_letter_country_code" {
  command = plan
  variables { country_code = "USA" }
  expect_failures = [var.country_code]
}

run "rejects_empty_country_code" {
  command = plan
  variables { country_code = "" }
  expect_failures = [var.country_code]
}

# ── latitude / longitude ───────────────────────────────────────────────────────

run "rejects_non_numeric_latitude" {
  command = plan
  variables { latitude = "not-a-number" }
  expect_failures = [var.latitude]
}

run "rejects_non_numeric_longitude" {
  command = plan
  variables { longitude = "west" }
  expect_failures = [var.longitude]
}

# ── location ───────────────────────────────────────────────────────────────────

run "rejects_blank_location" {
  command = plan
  variables { location = "" }
  expect_failures = [var.location]
}

# ── upgrade_day ────────────────────────────────────────────────────────────────

run "rejects_abbreviated_upgrade_day" {
  command = plan
  variables { upgrade_day = "Sun" }
  expect_failures = [var.upgrade_day]
}

run "rejects_lowercase_upgrade_day" {
  command = plan
  variables { upgrade_day = "sunday" }
  expect_failures = [var.upgrade_day]
}

# ── version_profile_id ─────────────────────────────────────────────────────────

run "rejects_out_of_range_version_profile" {
  command = plan
  variables { version_profile_id = "99" }
  expect_failures = [var.version_profile_id]
}

# ── dns_query_type ─────────────────────────────────────────────────────────────

run "rejects_unknown_dns_query_type" {
  command = plan
  variables { dns_query_type = "BOTH" }
  expect_failures = [var.dns_query_type]
}

# ── happy-path ─────────────────────────────────────────────────────────────────

run "accepts_minimum_valid_inputs" {
  command = plan
  # uses the top-level variables block
}

run "accepts_explicit_ipv4_only" {
  command = plan
  variables { dns_query_type = "IPV4" }
}

run "accepts_version_profile_new_release" {
  command = plan
  variables {
    override_version_profile = true
    version_profile_id       = "2"
  }
}
