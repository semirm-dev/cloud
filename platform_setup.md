# Platform Engineering & DevSecOps Bootstrap Guide

An end-to-end execution order for standing up a production-grade Kubernetes platform—connecting your networking (`cni.md`, `ingress-tls-cni.md`), DNS (`external-dns.md`), and security (`cicd_scan.md`) references into a single repeatable workflow.

---

## 1. Master Installation & Configuration Order

In practice, **Steps 1–4** are bootstrapped via Terraform/CLI, and **Steps 5–12** are deployed and reconciled declaratively from Git by **ArgoCD** using Sync Waves.

| Order | Tool | Where & How Installed | How Configured | What It Is Used For |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Terraform / OpenTofu** | Local CLI / CI Runner (Binary) | `.tf` HCL modules + remote state backend (S3/GCS) | Provisions underlying cloud VPCs, subnets, IAM roles (OIDC), and managed K8s clusters (or VMs on bare metal). |
| **2** | **Kubernetes (`RKE2` / `EKS` / `kind`)** | Cluster Nodes (Systemd service or Cloud managed) | Cluster config YAML (`config.yaml` with `cni: none` or `cilium`) | Core container orchestration control plane and worker nodes. |
| **3** | **Cilium** *(or Calico)* | In-Cluster (`DaemonSet` + Operator via Helm/CLI) | Helm values (`kubeProxyReplacement=true`, `CiliumL2AnnouncementPolicy`, `CiliumLoadBalancerIPPool`) | eBPF pod networking (CNI), `NetworkPolicy` enforcement, L7 Gateway/Ingress, and floating LoadBalancer IPs. |
| **4** | **ArgoCD** | In-Cluster (`argocd` namespace via Helm) | Root `Application` / `ApplicationSet` YAML manifests pointing to your Git repo | Continuous GitOps delivery; once bootstrapped, it installs and syncs all remaining tools below from Git. |
| **5** | **OpenBao / Vault + External Secrets Operator (ESO)** | In-Cluster (`openbao` & `external-secrets` namespaces via ArgoCD) | Enable KV v2 & K8s Auth in OpenBao; `ClusterSecretStore` + `ExternalSecret` CRDs | Stores sensitive credentials securely and syncs them into native K8s `Secret`s without putting secrets in Git. |
| **6** | **`cert-manager`** | In-Cluster (`cert-manager` namespace via ArgoCD) | `ClusterIssuer` (ACME HTTP-01/DNS-01 or internal CA) + `Certificate` CRDs | Automatically issues and renews TLS/HTTPS certificates before expiration. |
| **7** | **Traefik** *(if not using Cilium Gateway)* | In-Cluster (`traefik` namespace via ArgoCD) | `Ingress` or Gateway API `HTTPRoute` manifests + `Middleware` CRDs | Layer 7 HTTP/HTTPS reverse proxy routing external domains to internal cluster `Service`s. |
| **8** | **`external-dns`** | In-Cluster (`external-dns` namespace via ArgoCD) | Helm values (`provider`, `domainFilters`, `policy: sync`, `txtOwnerId`) + DNS API token/IAM role | Watches `Ingress`/`HTTPRoute`/`Service` hostnames and automatically creates `A`/`CNAME`/`TXT` records in Cloudflare/Route53. |
| **9** | **`kube-prometheus-stack` + Loki** | In-Cluster (`monitoring` namespace via ArgoCD) | `ServiceMonitor` / `PodMonitor` CRDs + Grafana dashboards & Alertmanager rules | Scrapes cluster/app metrics (Prometheus), aggregates pod logs (Loki), and visualizes health/alerts (Grafana). |
| **10** | **Kyverno** | In-Cluster (`kyverno` namespace via ArgoCD) | `ClusterPolicy` YAML files (`Audit` mode first, then `Enforce`) | Admission control bouncer: verifies Cosign image signatures and blocks `root`, `:latest`, or unhardened pods. |
| **11** | **`trivy-operator`** | In-Cluster (`trivy-system` namespace via ArgoCD) | Helm values (`severity=CRITICAL,HIGH`, `ignoreUnfixed=true`) | Continuously re-scans running pods for newly discovered CVEs and exposes `VulnerabilityReport` CRDs. |
| **12** | **Falco (+ Falcosidekick)** | In-Cluster (`DaemonSet` on every node via ArgoCD) | `modern_ebpf` driver + custom YAML syscall rules + Slack/Prometheus webhook | Monitors live Linux kernel syscalls via eBPF to detect shells, token reads, or malware at runtime. |
| **13** | **Trivy CLI + Cosign (+ Gitleaks/Semgrep)** | CI/CD Pipeline (GitHub Actions / GitLab CI runners) | `.github/workflows/*.yaml` pipeline steps (keyless OIDC via Fulcio/Rekor) | Scans code/images for CVEs & secrets on every `git push` and cryptographically signs the image digest before ArgoCD deploys it. |

---

## 2. Why This Exact Sequence Matters

1. **Cilium (#3) before everything else:** No pods (including CoreDNS or ArgoCD) can receive Pod IPs or communicate across nodes until a CNI is active.
2. **ArgoCD (#4) immediately after networking:** Eliminates manual `helm install` commands for Steps 5–12. Everything from this point onward is tracked in Git.
3. **OpenBao + ESO (#5) before `cert-manager` & `external-dns` (#6–8):** Ensures DNS API tokens (e.g., Cloudflare) are pulled dynamically from your secret store rather than created manually.
4. **Kyverno (#10) after core controllers:** Rolling out Kyverno late—and starting in `Audit` mode—prevents admission webhooks from accidentally blocking system pods during cluster bring-up.

---

## 3. GitOps Directory Structure & ArgoCD Sync Waves

Organize your platform Git repository so ArgoCD installs operators/CRDs first and custom resources second using `argocd.argoproj.io/sync-wave` annotations:

```text
platform-gitops/
├── bootstrap/
│   └── root-app.yaml                 # App-of-Apps pointing to ./apps
├── apps/                             # ArgoCD Application manifests with sync-waves
│   ├── wave-0-operators.yaml         # Wave 0: ESO, cert-manager, Traefik, external-dns, Kyverno
│   ├── wave-1-configs.yaml           # Wave 1: ClusterSecretStore, ClusterIssuer, Prometheus/Loki, Trivy, Falco
│   └── wave-2-policies-workloads.yaml# Wave 2: Kyverno ClusterPolicies (Audit -> Enforce) + App workloads
└── charts-and-manifests/
    ├── security/
    ├── networking/
    └── observability/
```

### Sync Wave Breakdown
* **Wave `0` (Controllers & CRDs):** Installs Helm charts for `external-secrets`, `cert-manager`, `traefik`, `external-dns`, and `kyverno` so all Custom Resource Definitions exist in the API server.
* **Wave `1` (Platform Configurations & Telemetry):** Applies `ClusterSecretStore`, `ExternalSecret`s, `ClusterIssuer`, `CiliumLoadBalancerIPPool`, `kube-prometheus-stack`, `Loki`, `trivy-operator`, and `Falco`.
* **Wave `2` (Guardrails & Workloads):** Applies Kyverno `ClusterPolicy` rules (`validationFailureAction: Audit` first) and deploys application manifests.

---

## 4. Verification Checkpoints

Run these checks at each milestone before moving to the next phase:

1. **Networking & Cluster Ready (After Step 3):**
   ```bash
   kubectl get nodes -o wide
   cilium status --wait
   kubectl get pods -n kube-system   # Confirm CoreDNS pods are Running
   ```
2. **GitOps Sync Healthy (After Step 4):**
   ```bash
   kubectl get applications -n argocd
   ```
3. **Secrets, TLS & DNS End-to-End (After Steps 5–8):**
   ```bash
   kubectl get externalsecret,clusterissuer,certificate -A   # All should show READY=True
   dig +short app.example.com @1.1.1.1                       # Resolves to LoadBalancer VIP
   curl -I https://app.example.com                           # Valid TLS cert & HTTP 200
   ```
4. **Security & Runtime Observability (After Steps 9–13):**
   ```bash
   kubectl get policyreport,vulnerabilityreports -A
   kubectl get pods -n falco                                 # 1 Falco pod Running per node
   ```