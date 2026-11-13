variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "floci-local"
}

variable "region" {
  description = "GCP Region (must match the cluster region)"
  type        = string
  default     = "europe-west1"
}

variable "cluster_name" {
  description = "Name of the GKE cluster the key is for"
  type        = string
  default     = "practice-gke-cluster"
}

variable "emulator" {
  description = "Skip resources floci-gcp does not implement (KMS key IAM). Set false for real GCP."
  type        = bool
  default     = true
}
