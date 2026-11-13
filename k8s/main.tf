# ==============================================================================
# 1. Enable Mandatory GCP APIs
# ==============================================================================
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "artifactregistry.googleapis.com",
  ])

  service            = each.key
  disable_on_destroy = false
}

# ==============================================================================
# 2. Custom VPC, Subnets with Secondary Ranges (Pods/Services) & Cloud NAT
# ==============================================================================
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  routing_mode            = "REGIONAL"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

resource "google_compute_subnetwork" "gke_subnet" {
  name                     = "${var.cluster_name}-private-subnet"
  ip_cidr_range            = "10.0.0.0/20"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true

  # Mandatory for VPC-native (Alias IP) GKE clusters
  secondary_ip_range {
    range_name    = "k8s-pods"
    ip_cidr_range = "10.16.0.0/14"
  }

  secondary_ip_range {
    range_name    = "k8s-services"
    ip_cidr_range = "10.20.0.0/20"
  }
}

# Cloud Router + Cloud NAT (Outbound Internet for Private Worker Nodes)
resource "google_compute_router" "router" {
  count = var.emulator ? 0 : 1 # Not implemented by floci-gcp

  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  count = var.emulator ? 0 : 1 # Not implemented by floci-gcp

  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# ==============================================================================
# 3. Dedicated Least-Privilege IAM Service Account for Worker Nodes
# ==============================================================================
resource "google_service_account" "gke_nodes" {
  account_id   = "gke-worker-nodes-sa"
  display_name = "GKE Worker Node Service Account"
  depends_on   = [google_project_service.apis]
}

resource "google_project_iam_member" "node_default_role" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "node_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# ==============================================================================
# 4. Cloud KMS Envelope Encryption for Kubernetes Secrets
# ==============================================================================
# Key ring and key are managed in ./kms (never destroyed); look the key up here.
data "google_kms_crypto_key" "gke_secrets_key" {
  name     = "${var.cluster_name}-secrets-key"
  key_ring = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.cluster_name}-keyring"
}

# ==============================================================================
# 5. GKE Control Plane (Private Nodes, VPC-Native, Workload Identity, Dataplane V2)
# ==============================================================================
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone # Use var.region in production for regional HA control plane

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.gke_subnet.id

  # Best Practice: Remove default node pool and manage node pools separately
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false # Set to true in live production

  # Modern Cilium-based eBPF networking & network policy enforcement
  datapath_provider = "ADVANCED_DATAPATH"

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "k8s-pods"
    services_secondary_range_name = "k8s-services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0" # Restrict to office/VPN CIDR in live production
      display_name = "Admin Access"
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  database_encryption {
    state    = "ENCRYPTED"
    key_name = data.google_kms_crypto_key.gke_secrets_key.id
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.node_default_role,
  ]
}

# ==============================================================================
# 6. Separately Managed 2-Node Pool (Shielded VMs, Auto-Upgrade/Repair, Autoscaling)
# ==============================================================================
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-workers"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  node_count = 2

  autoscaling {
    min_node_count = 1
    max_node_count = 4
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = "e2-medium"
    disk_size_gb    = 50
    disk_type       = "pd-balanced"
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      environment = "practice"
      managed-by  = "terraform"
    }
  }
}
