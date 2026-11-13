# Long-lived layer: KMS key rings and keys can never be deleted in GCP,
# so they live apart from the cluster and are never destroyed.

resource "google_project_service" "apis" {
  for_each = toset([
    "cloudkms.googleapis.com",
    "container.googleapis.com", # Creates the GKE service agent granted below
  ])

  service            = each.key
  disable_on_destroy = false
}

resource "google_kms_key_ring" "gke_keyring" {
  name       = "${var.cluster_name}-keyring"
  location   = var.region
  depends_on = [google_project_service.apis]
}

resource "google_kms_crypto_key" "gke_secrets_key" {
  name            = "${var.cluster_name}-secrets-key"
  key_ring        = google_kms_key_ring.gke_keyring.id
  rotation_period = "7776000s" # 90 days automatic rotation

  lifecycle {
    prevent_destroy = true
  }
}

data "google_project" "current" {}

resource "google_kms_crypto_key_iam_member" "gke_kms_encrypter" {
  count = var.emulator ? 0 : 1 # Not implemented by floci-gcp

  crypto_key_id = google_kms_crypto_key.gke_secrets_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@container-engine-robot.iam.gserviceaccount.com"
}
