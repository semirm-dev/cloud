terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project      = var.project_id
  region       = var.region
  access_token = "floci-local-dummy-token"

  container_custom_endpoint              = "http://container.localhost:4588/"
  compute_custom_endpoint                = "http://localhost:4588/compute/v1/"
  iam_custom_endpoint                    = "http://localhost:4588/"
  cloud_resource_manager_custom_endpoint = "http://localhost:4588/"
  service_usage_custom_endpoint          = "http://localhost:4588/"
  resource_manager_custom_endpoint       = "http://localhost:4588/"
  cloud_billing_custom_endpoint          = "http://localhost:4588/"
  kms_custom_endpoint                    = "http://localhost:4588/v1/"
}
