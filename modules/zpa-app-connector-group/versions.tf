terraform {
  required_version = "~> 1.9"
  required_providers {
    zpa = {
      source  = "zscaler/zpa"
      version = "~> 4.0"
    }
  }
}
