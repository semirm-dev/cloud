output "gke_secrets_key_id" {
  value = google_kms_crypto_key.gke_secrets_key.id
}
