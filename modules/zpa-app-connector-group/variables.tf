variable "name" {
  description = "Name of the App Connector Group."
  type        = string
  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name must not be blank."
  }
}

variable "description" {
  description = "Human-readable description."
  type        = string
  default     = ""
}

variable "enabled" {
  description = "Whether the group is enabled."
  type        = bool
  default     = true
}

variable "city_country" {
  description = "City and country label (e.g. \"Ashburn, US\")."
  type        = string
  default     = ""
}

variable "country_code" {
  description = "ISO-3166-1 alpha-2 country code (e.g. \"US\", \"DE\")."
  type        = string
  validation {
    condition     = length(var.country_code) == 2
    error_message = "country_code must be a two-letter ISO-3166-1 alpha-2 code."
  }
}

variable "latitude" {
  description = "Decimal latitude of the connector location (as string, e.g. \"39.0438\")."
  type        = string
  validation {
    condition     = can(tonumber(var.latitude))
    error_message = "latitude must be a numeric string."
  }
}

variable "longitude" {
  description = "Decimal longitude of the connector location (as string, e.g. \"-77.4874\")."
  type        = string
  validation {
    condition     = can(tonumber(var.longitude))
    error_message = "longitude must be a numeric string."
  }
}

variable "location" {
  description = "Human-readable location description (e.g. \"Ashburn, VA, US\")."
  type        = string
  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be blank."
  }
}

variable "upgrade_day" {
  description = "Day of the week for scheduled connector upgrades."
  type        = string
  default     = "SUNDAY"
  validation {
    condition = contains(
      ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"],
      var.upgrade_day
    )
    error_message = "upgrade_day must be an uppercase day name (SUNDAY … SATURDAY)."
  }
}

variable "upgrade_time_in_secs" {
  description = "Seconds from midnight UTC at which upgrades start (e.g. \"66600\" = 18:30 UTC)."
  type        = string
  default     = "66600"
}

variable "override_version_profile" {
  description = "Set to true to pin version_profile_id rather than use the tenant default."
  type        = bool
  default     = false
}

variable "version_profile_id" {
  description = "Connector version profile. 0 = Default, 1 = Previous, 2 = New Release."
  type        = string
  default     = "0"
  validation {
    condition     = contains(["0", "1", "2"], var.version_profile_id)
    error_message = "version_profile_id must be \"0\" (Default), \"1\" (Previous), or \"2\" (New Release)."
  }
}

variable "dns_query_type" {
  description = "DNS query type for connector host resolution."
  type        = string
  default     = "IPV4_IPV6"
  validation {
    condition     = contains(["IPV4", "IPV6", "IPV4_IPV6"], var.dns_query_type)
    error_message = "dns_query_type must be IPV4, IPV6, or IPV4_IPV6."
  }
}

variable "microtenant_id" {
  description = "Microtenant ID to scope this group. Set null for the parent tenant (default)."
  type        = string
  default     = null
}
