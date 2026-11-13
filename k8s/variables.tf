variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "floci-local"
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP Zone for zonal cluster (use var.region in prod for multi-zone HA)"
  type        = string
  default     = "europe-west1-b"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "practice-gke-cluster"
}

variable "emulator" {
  description = "Skip resources floci-gcp does not implement (Cloud Router/NAT, KMS key IAM). Set false for real GCP."
  type        = bool
  default     = true
}
