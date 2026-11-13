# Local GCP & Kubernetes (GKE) Lab with `floci-gcp` and Terraform

Complete end-to-end guide for running a local, zero-cost GCP environment using **`floci-gcp`**, **`floci-ui`**, and **Terraform** in WSL 2, following real GCP production best practices.

---

## 1. Prerequisites & WSL 2 Docker Setup

### Docker Desktop WSL 2 Integration (Windows)
1. Open **Docker Desktop** $\rightarrow$ **Settings** (gear icon) $\rightarrow$ **WSL integration** (under **Resources** or the right-hand settings sidebar).
2. Enable **Enable integration with my default WSL distro** and toggle **ON** your Linux distro (e.g., `Ubuntu`).
3. Ensure **Use Enhanced Container Isolation** is **OFF** so `floci-gcp` can mount `/var/run/docker.sock` to spawn real `k3s` Kubernetes containers.
4. Click **Apply** and restart your WSL terminal.

### Fix Docker Socket Permissions in WSL 2 (If Needed)
If `docker ps` or `docker compose` returns `permission denied` on `/var/run/docker.sock`:
```bash
sudo usermod -aG docker $USER
sudo chown root:docker /var/run/docker.sock
sudo chmod 660 /var/run/docker.sock
su - $USER
```
a
---

## 2. Install Local CLI Tools (`gcloud`, `kubectl`, `terraform`)

Run the following in your WSL 2 terminal (`Ubuntu` / `Debian`) to install the Google Cloud CLI, the GKE authentication plugin, and `kubectl`:

```bash
# 1. Install prerequisites
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates gnupg curl

# 2. Add Google Cloud apt repository
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list

# 3. Add HashiCorp apt repository (Terraform)
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# 4. Install gcloud CLI, GKE auth plugin, kubectl, and Terraform
sudo apt-get update
sudo apt-get install -y google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin kubectl terraform
```

Verify installations:
```bash
gcloud --version
kubectl version --client
terraform -version
```

---

## 3. Start `floci-gcp`, `floci-ui`, and Local Docker Registry

Create a clean working directory (e.g., `~/workspace/cloud/gcp-k8s`):
```bash
mkdir -p ~/workspace/cloud/gcp-k8s
cd ~/workspace/cloud/gcp-k8s
```

### `docker-compose.yml`
This starts:
* **`floci-gcp`** on port **`4588`** (handles all GCP REST/gRPC APIs and spawns real `k3s` containers for GKE).
* **`floci-ui`** on port **`4500`** (multi-cloud browser console to inspect your GCP VPCs, GKE clusters, and IAM accounts).
* **`ingress-proxy`** on ports **`80`/`443`** (forwards to the GKE node's Traefik LoadBalancer; stands in for the Google Cloud load balancer, see section 7).
* **`registry`** on port **`5000`** (local OCI container registry for `docker push` / `kubectl` image pulls).

```yaml
services:
  floci-gcp:
    image: floci/floci-gcp:latest
    container_name: floci-gcp
    ports:
      - "4588:4588"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - floci-gcp-data:/app/data
    environment:
      - FLOCI_GCP_STORAGE_MODE=hybrid
      - FLOCI_GCP_DEFAULT_PROJECT_ID=floci-local
      - FLOCI_GCP_HOSTNAME=floci-gcp
      - FLOCI_GCP_BASE_URL=http://floci-gcp:4588
    restart: unless-stopped

  floci-ui:
    image: floci/floci-ui:latest
    container_name: floci-ui
    ports:
      - "4500:4500"
    environment:
      - FLOCI_GCP_ENDPOINT=http://floci-gcp:4588
      - FLOCI_GCP_PROJECT=floci-local
    depends_on:
      - floci-gcp
    restart: unless-stopped

  registry:
    image: registry:2
    container_name: local-registry
    ports:
      - "5000:5000"
    restart: unless-stopped

  # Forwards host 80/443 to the GKE (k3s) node, standing in for a cloud load balancer
  ingress-proxy:
    image: alpine/socat:1.8.0.3
    container_name: ingress-proxy
    entrypoint: ["sh", "-c"]
    command:
      - |
        socat TCP-LISTEN:80,fork,reuseaddr TCP:floci-gcp-gke-floci-local-practice-gke-cluster:80 &
        exec socat TCP-LISTEN:443,fork,reuseaddr TCP:floci-gcp-gke-floci-local-practice-gke-cluster:443
    ports:
      - "80:80"
      - "443:443"
    restart: unless-stopped

volumes:
  floci-gcp-data:
```

Start the stack and verify health:
```bash
docker compose up -d
curl -s http://localhost:4588/health
curl -s http://localhost:4588/_floci-gcp/info
```

* **Web Dashboard:** Open `http://localhost:4500` in your browser and select **GCP**.

---

## 4. Configure `gcloud` CLI for Local Emulation

Create a `.env` file in your working directory (and source it with `source .env` in each terminal session):

```bash
export CLOUDSDK_CORE_PROJECT=floci-local
export CLOUDSDK_AUTH_ACCESS_TOKEN=floci-local-dummy-token
export CLOUDSDK_API_ENDPOINT_OVERRIDES_CONTAINER=http://container.localhost:4588/
export CLOUDSDK_API_ENDPOINT_OVERRIDES_COMPUTE=http://localhost:4588/compute/v1/
export CLOUDSDK_API_ENDPOINT_OVERRIDES_IAM=http://localhost:4588/
export CLOUDSDK_API_ENDPOINT_OVERRIDES_CLOUDKMS=http://localhost:4588/v1/
```

Create an isolated `floci-local` profile so you never mix local tests with real Google Cloud credentials. Source `.env` first: `gcloud` validates region/zone against the compute API, which fails with "no active account" unless the emulator token and endpoint are set.

```bash
source .env
gcloud config configurations create floci-local --activate
gcloud config set project floci-local
gcloud config set compute/region europe-west1
gcloud config set compute/zone europe-west1-b
```

---

## 5. Production-Ready Terraform Configuration

Make sure no leftover AWS `.tf` or `terraform.tfvars` files exist in `~/workspace/cloud/gcp-k8s`.

### `providers.tf`
*(To deploy to real GCP later, remove `access_token` and all `*_custom_endpoint` attributes, set `emulator = false`, and run `gcloud auth application-default login`.)*

```hcl
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
```

### `variables.tf`

```hcl
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
```

### `main.tf`

```hcl
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
```

### `outputs.tf`

```hcl
output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.primary.endpoint
  sensitive = true
}

output "kubeconfig_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${var.zone} --project ${var.project_id}"
}
```

### `kms/` — Long-Lived KMS Layer

KMS key rings and keys can **never be deleted** in GCP (or in `floci-gcp`), and their names stay reserved forever. Recreating them on every cluster rebuild fails with `409 KeyRing already exists`, so they live in a separate Terraform root that is applied once and never destroyed. The cluster root above only looks the key up with a `data` source.

`kms/providers.tf` is an exact copy of `providers.tf`.

#### `kms/variables.tf`

```hcl
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
```

#### `kms/main.tf`

```hcl
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
```

#### `kms/outputs.tf`

```hcl
output "gke_secrets_key_id" {
  value = google_kms_crypto_key.gke_secrets_key.id
}
```

---

## 6. Provision & Connect Workflow

```bash
# 1. Load local emulator environment variables
source .env

# 2. Create the long-lived KMS layer (once)
terraform -chdir=kms init
terraform -chdir=kms apply

# 3. Initialize, validate, and apply the cluster
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan

# 4. Fetch kubeconfig and inspect your cluster
gcloud container clusters get-credentials practice-gke-cluster --zone europe-west1-b
kubectl get nodes -o wide
kubectl get pods -A
```

---

## 7. Ingress & TLS (Traefik + cert-manager)

Production GKE puts a Google Cloud load balancer in front of an ingress controller (or the GKE Gateway API) and gets certificates from Let's Encrypt or Google-managed certs. Locally, `floci-gcp` has no cloud load balancer or Cloud DNS, so the same layers are built from in-cluster pieces:

| Layer | Production GKE | This lab |
| :--- | :--- | :--- |
| External load balancer | Google Cloud LB (from `Service type: LoadBalancer` or Gateway) | k3s ServiceLB + `ingress-proxy` container on host `80`/`443` |
| Ingress controller | Traefik / Envoy Gateway / GKE Gateway | Traefik (Helm) |
| Certificates | cert-manager + Let's Encrypt DNS-01 (Cloud DNS via Workload Identity) | cert-manager + local root CA |
| DNS | external-dns → Cloud DNS | `*.localtest.me` (public DNS that always resolves to `127.0.0.1`) |

`floci-gcp` starts k3s with its built-in Traefik disabled, so you install and own the ingress controller yourself, as in production.

### 7.1 Install Traefik and cert-manager

`traefik-values.yaml` (redirect all HTTP to HTTPS):
```yaml
ports:
  web:
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
```

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install traefik traefik/traefik --version 42.4.0 \
  -n traefik --create-namespace -f traefik-values.yaml --wait

helm install cert-manager jetstack/cert-manager --version v1.21.3 \
  -n cert-manager --create-namespace --set crds.enabled=true --wait

kubectl get svc -n traefik   # EXTERNAL-IP is the k3s node IP (ServiceLB)
```

### 7.2 Local Certificate Authority

`tls-issuers.yaml`:
```yaml
# 1. Bootstrap issuer that only signs the root CA
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
---
# 2. Local root CA (stored as Secret local-root-ca in cert-manager namespace)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: local-root-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: local-root-ca
  secretName: local-root-ca
  duration: 87600h # 10 years
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: selfsigned
    kind: ClusterIssuer
---
# 3. The issuer apps use (swap for a Let's Encrypt DNS-01 issuer in production)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: local-ca
spec:
  ca:
    secretName: local-root-ca
```

```bash
kubectl apply -f tls-issuers.yaml
kubectl wait --for=condition=Ready certificate/local-root-ca -n cert-manager --timeout=60s
```

### 7.3 Demo App with TLS Ingress

`whoami.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
spec:
  replicas: 2
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
        - name: whoami
          image: traefik/whoami:v1.11.0
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              memory: 32Mi
---
apiVersion: v1
kind: Service
metadata:
  name: whoami
spec:
  selector:
    app: whoami
  ports:
    - port: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  annotations:
    cert-manager.io/cluster-issuer: local-ca
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - whoami.localtest.me
      secretName: whoami-tls
  rules:
    - host: whoami.localtest.me
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: whoami
                port:
                  number: 80
```

```bash
kubectl apply -f whoami.yaml
kubectl wait --for=condition=Ready certificate/whoami-tls --timeout=90s
kubectl get ingress,certificate
```

### 7.4 Test

```bash
# Export the root CA so clients can verify certificates it signed
kubectl get secret local-root-ca -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d > local-root-ca.crt

curl -I http://whoami.localtest.me/                            # 301 -> https://
curl --cacert local-root-ca.crt https://whoami.localtest.me/   # 200, verified TLS
```

To trust it in a Windows browser, import `local-root-ca.crt` into **Trusted Root Certification Authorities** (`certmgr.msc`). Remove it when you're done with the lab.

**Going to production:** replace the `local-ca` issuer with a Let's Encrypt `ClusterIssuer` using a DNS-01 solver (Cloud DNS + Workload Identity), add external-dns, and drop `ingress-proxy` because the Traefik `LoadBalancer` Service gets a real Google Cloud LB IP.

---

## 8. Inspecting & Resetting Your Environment

* **Browser Console (`floci-ui`):** `http://localhost:4500`
* **`floci-gcp` API Endpoint:** `http://localhost:4588`
* **List GCP resources via CLI:**
  ```bash
  gcloud container clusters list
  gcloud compute networks list
  gcloud compute networks subnets list
  ```
* **Inspect Terraform state:**
  ```bash
  terraform state list
  terraform show
  ```
* **Tear down the cluster (KMS layer stays; re-apply reuses the key):**
  ```bash
  terraform destroy
  ```
* **Wipe all `floci-gcp` emulator state without restarting Docker:**
  ```bash
  curl -X POST http://localhost:4588/_floci-gcp/state/reset
  ```

---

## 9. Key Local Emulation Notes

* **Single `k3s` Container Behind GKE:** Even though `node_count = 2` is validated and stored in your GKE node pool API state, `floci-gcp` spawns a single `rancher/k3s` Docker container per cluster (`kubectl get nodes` will display 1 node).
* **VPC Routing:** VPCs, subnets, and secondary CIDR ranges are tracked at the API level only; actual container traffic uses the host Docker network.
* **Unimplemented APIs (`emulator = true`):** `floci-gcp` 0.12.0 returns `501` for Cloud Router/NAT and `404` for KMS key IAM policies, so those three resources are skipped locally via `count`. Set `emulator = false` for real GCP.
* **KMS Layer:** Never destroy `kms/` (`prevent_destroy = true` blocks it). After an emulator state reset, delete `kms/terraform.tfstate` and re-apply `kms/` before the cluster.
* **CNI:** Nothing to install. k3s ships with flannel; real GKE provides its own CNI (Dataplane V2 / Cilium via `datapath_provider`). You cannot swap the CNI on the `floci-gcp` cluster. For Cilium practice use `kind` or k3d.
* **`ingress-proxy`:** Targets the container name of the `practice-gke-cluster` k3s node. If you change `cluster_name`, update the two `socat` targets in `docker-compose.yaml`.
* **Runtime Fidelity:** Workload Identity, private nodes, Dataplane V2, KMS secrets encryption, Shielded VMs, autoscaling, and Managed Prometheus are stored by the API but not enforced by k3s.