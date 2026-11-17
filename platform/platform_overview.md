# Platform Engineering & DevSecOps Bootstrap Guide

An end-to-end execution order for standing up a production-grade Kubernetes platform—connecting your detailed references: networking ([`cni.md`](cni.md), [`ingress.md`](ingress.md)), TLS ([`cert_manager.md`](cert_manager.md)), DNS ([`external_dns.md`](external_dns.md)), security ([`security_pipeline.md`](security_pipeline.md)), and identity ([`iam.md`](iam.md)) into a single repeatable workflow.

This file is the **orchestration index** (order, waves, verify). Tool-specific install/config lives in the linked refs where they exist; Terraform, ArgoCD, OpenBao/ESO, and Prometheus/Loki are summarized only here until dedicated refs are added.

---

## 1. Master Installation & Configuration Order

In practice, **Steps 1–4** are bootstrapped via Terraform/CLI, **Steps 5–12** are deployed and reconciled from Git by **ArgoCD** (Sync Waves), and **Step 13** runs in CI (not in-cluster).

| Order | Tool | Where & How Installed | How Configured | What It Is Used For |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Terraform / OpenTofu** | Local CLI / CI Runner (Binary) | `.tf` HCL modules + remote state backend (S3/GCS); OIDC/IAM roles — see [`iam.md`](iam.md) | Provisions underlying cloud VPCs, subnets, IAM roles (OIDC), and managed K8s clusters (or VMs on bare metal). |
| **2** | **Kubernetes (`RKE2` / `EKS` / `kind`)** | Cluster Nodes (Systemd service or Cloud managed) | Cluster config YAML (`config.yaml` with `cni: none` or `cilium`) | Core container orchestration control plane and worker nodes. |
| **3** | **Cilium** *(or Calico)* — [`cni.md`](cni.md) | In-Cluster (`DaemonSet` + Operator via Helm/CLI) | Helm values (`kubeProxyReplacement=true`) + **`CiliumLoadBalancerIPPool` / `CiliumL2AnnouncementPolicy` applied with Cilium bootstrap** (before Traefik) | eBPF pod networking (CNI), `NetworkPolicy` enforcement, optional L7 Gateway/Ingress, and floating LoadBalancer IPs. |
| **4** | **ArgoCD** | In-Cluster (`argocd` namespace via Helm) | Root `Application` / `ApplicationSet` in a dedicated `bootstrap` AppProject; `default` project locked down (empty `sourceRepos` / `destinations`). SSO via Dex/OIDC, local `admin` disabled, RBAC `policy.default: role:readonly`. Each environment follows its own branch/tag: prod is promoted by PR once staging is green, not every cluster on `main` | Continuous GitOps delivery; once bootstrapped, it installs and syncs all remaining **in-cluster** tools (steps 5–12) from Git. |
| **5** | **OpenBao / Vault + External Secrets Operator (ESO)** | In-Cluster (`openbao` & `external-secrets` namespaces via ArgoCD) | HA with integrated Raft (3 replicas), auto-unseal via cloud KMS (GCP/AWS/Azure KMS) so a reschedule does not leave it sealed, TLS from a cert-manager internal CA. Init once with recovery shares (e.g. 5/3) into a password manager, then revoke the root token. Enable KV v2 & K8s Auth; `ClusterSecretStore` (`https://` server + `caProvider`) + `ExternalSecret` CRDs | Stores sensitive credentials securely and syncs them into native K8s `Secret`s without putting secrets in Git. |
| **6** | **`cert-manager`** — [`cert_manager.md`](cert_manager.md) | In-Cluster (`cert-manager` namespace via ArgoCD) | `ClusterIssuer` (ACME HTTP-01/DNS-01 or internal CA) + `Certificate` CRDs | Automatically issues and renews TLS/HTTPS certificates before expiration. |
| **7** | **Traefik** *(if not using Cilium Gateway)* — [`ingress.md`](ingress.md) | In-Cluster (`traefik` namespace via ArgoCD) | `Ingress` or Gateway API `HTTPRoute` manifests + `Middleware` CRDs; Service `type: LoadBalancer` uses the VIP from step 3 | Layer 7 HTTP/HTTPS reverse proxy routing external domains to internal cluster `Service`s. |
| **8** | **`external-dns`** — [`external_dns.md`](external_dns.md) | In-Cluster (`external-dns` namespace via ArgoCD) | Helm values (`provider`, `domainFilters`, `policy: upsert-only` → `sync`, unique `txtOwnerId`) + DNS API token/IAM role | Watches `Ingress`/`HTTPRoute`/`Service` hostnames and automatically creates `A`/`CNAME`/`TXT` records in Cloudflare/Route53. |
| **9** | **`kube-prometheus-stack` + Loki** | In-Cluster (`monitoring` namespace via ArgoCD) | `ServiceMonitor` / `PodMonitor` CRDs + Grafana dashboards & Alertmanager rules. Persistent volumes for Prometheus & Alertmanager; Alertmanager receivers configured (a page that routes nowhere is no alert); Grafana admin password from the secret store via ESO, not the chart default | Scrapes cluster/app metrics (Prometheus), aggregates pod logs (Loki), and visualizes health/alerts (Grafana). |
| **10** | **Kyverno** — [`security_pipeline.md`](security_pipeline.md) | In-Cluster (`kyverno` namespace via ArgoCD) | `ClusterPolicy` YAML files (`Audit` mode first, then `Enforce`) | Admission control bouncer: verifies Cosign image signatures and blocks `root`, `:latest`, or unhardened pods. |
| **11** | **`trivy-operator`** — [`security_pipeline.md`](security_pipeline.md) | In-Cluster (`trivy-system` namespace via ArgoCD) | Helm values (`severity=CRITICAL,HIGH`, `ignoreUnfixed=true`) | Continuously re-scans running pods for newly discovered CVEs and exposes `VulnerabilityReport` CRDs. |
| **12** | **Falco (+ Falcosidekick)** — [`security_pipeline.md`](security_pipeline.md) | In-Cluster (`DaemonSet` on every node via ArgoCD) | `modern_ebpf` driver + custom YAML syscall rules + Slack/Prometheus webhook | Monitors live Linux kernel syscalls via eBPF to detect shells, token reads, or malware at runtime. |
| **13** | **Trivy CLI + Cosign (+ Gitleaks/Semgrep)** — [`security_pipeline.md`](security_pipeline.md) | **CI/CD Pipeline** (GitHub Actions / GitLab CI runners) — not ArgoCD | `.github/workflows/*.yaml` pipeline steps (keyless OIDC via Fulcio/Rekor) | Scans code/images for CVEs & secrets on every `git push` and cryptographically signs the image digest before ArgoCD deploys it. |

---

## 2. Why This Exact Sequence Matters

1. **Cilium (#3) before everything else:** No pods (including CoreDNS or ArgoCD) can receive Pod IPs or communicate across nodes until a CNI is active. Apply the **LoadBalancer IP pool + L2/BGP policy with Cilium** so Traefik (#7) gets a real `EXTERNAL-IP` on first sync.
2. **ArgoCD (#4) immediately after networking:** Eliminates manual `helm install` for steps 5–12. Step 13 stays in CI.
3. **OpenBao + ESO (#5) before `cert-manager` & `external-dns` (#6–8):** DNS/API tokens (e.g. Cloudflare) are synced from the secret store rather than created by hand or committed to Git. The exception is cert-manager's controller and its internal CA issuer, which need no secret and come first because they issue OpenBao's own TLS cert.
4. **Kyverno (#10) after core controllers:** Rolling out late—and starting in `Audit`—avoids admission webhooks blocking system pods during bring-up.
5. **`external-dns` policy:** Start with `upsert-only` so existing records cannot be deleted; switch to `sync` only after hostnames and `txtOwnerId` look correct ([`external_dns.md`](external_dns.md)).

---

## 3. GitOps Directory Structure & ArgoCD Sync Waves

Organize the platform Git repo so ArgoCD installs operators/CRDs first and custom resources second using `argocd.argoproj.io/sync-wave` annotations:

```text
platform-gitops/
├── bootstrap/
│   └── root-app.yaml                 # App-of-Apps pointing to ./apps (AppProject: bootstrap)
├── projects/                         # AppProjects (Wave -1): bootstrap, platform, apps; `default` locked down
├── apps/                             # ArgoCD Application manifests with sync-waves
│   ├── wave-0-operators.yaml         # Wave 0: ESO, cert-manager, Traefik, external-dns, Kyverno
│   ├── wave-1-configs.yaml           # Wave 1: internal CA ClusterIssuer, OpenBao, ClusterSecretStore, ExternalSecrets, ACME ClusterIssuer, monitoring, Trivy, Falco
│   └── wave-2-policies-workloads.yaml# Wave 2: Kyverno ClusterPolicies (Audit → Enforce) + app workloads
└── charts-and-manifests/
    ├── security/
    ├── networking/
    └── observability/
```

### Sync Wave Breakdown

* **Bootstrap (pre-ArgoCD / with Cilium):** Cilium Helm install + `CiliumLoadBalancerIPPool` + `CiliumL2AnnouncementPolicy` (or cloud LB). Do **not** defer the IP pool to Wave 1 if Traefik needs a VIP on first apply.
* **Wave `-1` (Projects):** AppProjects, so every later Application has its project; the root app itself lives in `bootstrap`, never `default`.
* **Wave `0` (Controllers & CRDs):** Helm charts for `external-secrets`, `cert-manager`, `traefik` *(or rely on Cilium Gateway)*, `external-dns`, and `kyverno` so CRDs exist in the API server.
* **Wave `1` (Platform config & telemetry):** internal CA `ClusterIssuer`, OpenBao (or Vault), `ClusterSecretStore`, `ExternalSecret`s, ACME `ClusterIssuer`, `kube-prometheus-stack`, Loki, `trivy-operator`, Falco.
  * OpenBao's TLS cert comes from the internal CA issuer, so OpenBao syncs with/after that issuer, not in Wave 0 (its pod cannot start without the TLS Secret).
  * The first sync waits on a **manual step**: `bao operator init` (recovery shares → password manager), seed the secrets ESO reads, revoke the root token. Until then OpenBao is not Ready and the ExternalSecrets retry.
* **Wave `2` (Guardrails & workloads):** Kyverno `ClusterPolicy` (per-rule `failureAction: Audit` first) and application manifests.

**Bring layers up one at a time.** Waves order a single sync, but a first sync of everything stalls on the slowest manual step (OpenBao init) and leaves later layers half-applied. Gate each layer's `Application` behind a switch in the app-of-apps values and turn them on in order, one commit each:

```yaml
# apps/values.yaml — each template wraps itself in {{- if .Values.tracks.<name> }}
tracks:
  gateway: true         # networking + the app's route
  secrets: false        # cert-manager, ESO, OpenBao (needs the manual init)
  guardrails: false     # Kyverno + policies
  observability: false  # kube-prometheus-stack, Loki
```

A resource a layer needs from a later one (e.g. the app's `ServiceMonitor` before monitoring exists) needs its CRD applied up front, or the app sync fails.

---

## 4. Verification Checkpoints

Run these checks at each milestone before moving on:

1. **Networking & cluster ready (after step 3):**
   ```bash
   kubectl get nodes -o wide
   cilium status --wait
   kubectl get ciliumloadbalancerippool,ciliuml2announcementpolicy -A
   kubectl get pods -n kube-system   # CoreDNS Running
   ```
2. **GitOps sync healthy (after step 4):**
   ```bash
   kubectl get applications -n argocd
   ```
3. **Secrets, TLS & DNS end-to-end (after steps 5–8):**
   ```bash
   kubectl get externalsecret,clusterissuer,certificate -A   # READY=True
   kubectl -n traefik get svc                                # EXTERNAL-IP from Cilium pool / cloud LB
   dig +short app.example.com @1.1.1.1                       # Matches VIP or WAN target
   curl -I https://app.example.com                           # Valid TLS & expected status
   ```
4. **Security & runtime observability (after steps 9–13):**
   ```bash
   kubectl get policyreport,vulnerabilityreports -A
   kubectl get pods -n falco                                 # One Falco pod per node
   ```
5. **Teardown (managed clusters):** the cloud load balancer behind a `Gateway`/`LoadBalancer` Service and the disks behind PVCs are created by the cluster, not Terraform. Delete the root `Application` (so nothing is recreated), the child Applications, Gateways and PVCs *before* destroying the cluster, or they outlive it and keep billing.
