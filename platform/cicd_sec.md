# CI/CD & Kubernetes Security Pipeline Reference

A concise operational guide covering **Trivy**, **Cosign (Sigstore)**, **Kyverno**, and **Falco**—how they secure workloads from build time to runtime, where each runs, how they are installed/configured, and minimal configuration hints.

---

## 1. End-to-End Lifecycle Overview

```text
[Code Push / CI Build]
   ├── 1. Trivy   ──► Scans image & IaC for CVEs/secrets (Pre-deploy)
   └── 2. Cosign  ──► Signs image digest via OIDC/keys + logs receipt in Rekor
         │
         ▼
[Kubernetes API Server / Admission Control]
   └── 3. Kyverno ──► Verifies Cosign signature & enforces Pod hardening YAML rules
         │
         ▼
[Running Cluster / Linux Kernel]
   ├── Trivy Operator ──► Continuously re-scans running Pods for newly disclosed CVEs
   └── 4. Falco       ──► Watches live syscalls via eBPF & alerts on suspicious behavior
```

| Tool | Stage | Primary Mechanism | Analogy |
| :--- | :--- | :--- | :--- |
| **Trivy** | CI/CD + In-Cluster | Static CVE, secret, SBOM & IaC scanner | Airport X-ray scanner |
| **Cosign** | CI/CD + Registry | Cryptographic OCI image signing & attestations | Tamper-evident wax seal |
| **Kyverno** | K8s Admission Webhook | Mutating & Validating Admission Controller (YAML) | Bouncer checking IDs & seals at the door |
| **Falco** | Runtime (Linux Kernel) | eBPF syscall monitoring + rule engine | 24/7 security camera inside the building |

---

## 2. Trivy (Vulnerability, Secret & Misconfiguration Scanner)

* **What it is:** An open-source scanner by Aqua Security that detects OS/language CVEs, hardcoded secrets, IaC misconfigurations (Terraform, Kubernetes YAMLs, Dockerfiles), and generates SBOMs.
* **Where it is used:**
  1. **CI/CD Pipelines (GitHub Actions / GitLab CI):** Blocks builds before images reach your registry.
  2. **Inside Kubernetes (`trivy-operator`):** Continuously scans already-running workloads when new CVEs are published after deployment.
* **How it is installed & configured:**
  * **CI:** Installed as a single CLI binary or GitHub Action step (`aquasecurity/trivy-action`).
  * **Kubernetes:** Installed via Helm (`aqua/trivy-operator`) into `trivy-system`. It runs as a Kubernetes Operator that automatically watches Pods/ReplicaSets and outputs native `VulnerabilityReport` and `ConfigAuditReport` CRDs.
* **Config Hint:**
  ```bash
  # CI check: fail build on fixable CRITICAL/HIGH CVEs or leaked secrets
  trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed --scanners vuln,secret myorg/app@sha256:...

  # K8s Operator inspection
  kubectl get vulnerabilityreports -A
  ```

---

## 3. Cosign & Sigstore (Cryptographic Image Signing)

* **What it is:** The "Let's Encrypt of code signing." **Cosign** signs container image `sha256` digests and attaches SBOM attestations stored directly alongside the image in your OCI registry (GHCR, ECR, Docker Hub).
  * **Fulcio:** Sigstore's CA that issues ~10-minute ephemeral signing certificates tied to your CI OIDC identity (GitHub/GitLab).
  * **Rekor:** An immutable, append-only transparency log (REST API backed by a Merkle tree) that records a timestamped receipt of the signing event so signatures remain verifiable after the 10-minute cert expires.
* **Where it is used:** At the end of CI/CD right after pushing an image to the registry (and optionally inside air-gapped environments using KMS/local keys with `--tlog-upload=false`).
* **How it is installed & configured:**
  * Installed as a single CLI binary in CI runners (`sigstore/cosign-installer`).
  * **Keyless mode:** Requires `id-token: write` permission in CI—generates a private key in RAM, signs, logs to Rekor, and discards the key immediately.
  * **Key-based / Air-gapped mode:** Uses a generated keypair (`cosign.key` / `cosign.pub`) or cloud KMS (`awskms://...`, `hashivault://...`).
* **Config Hint:**
  ```bash
  # Keyless OIDC signing (CI)
  cosign sign --yes ghcr.io/myorg/app@sha256:...

  # Attach a signed CycloneDX SBOM attestation
  cosign attest --yes --predicate sbom.cdx.json --type cyclonedx ghcr.io/myorg/app@sha256:...
  ```

---

## 4. Kyverno (Kubernetes Policy Engine & Admission Controller)

* **What it is:** A Kubernetes-native policy engine that plugs into `kube-apiserver` as a **Mutating and Validating Admission Webhook**. It intercepts every `kubectl apply` or ArgoCD sync *before* the resource is saved to `etcd`.
* **Where it is used:** Inside the Kubernetes control plane to enforce security guardrails, verify Cosign image signatures, mutate defaults, and generate baseline resources (like default-deny `NetworkPolicy` objects for new namespaces).
* **How it is installed & configured:**
  * Installed via Helm (`kyverno/kyverno`) into the `kyverno` namespace (run 3 replicas of `admissionController` in production).
  * Configured purely with Kubernetes YAML CRDs: **`ClusterPolicy`** (cluster-wide) or **`Policy`** (namespace-scoped).
  * Roll out safely with `validationFailureAction: Audit` first, then switch to `Enforce`.
* **Config Hint:**
  ```yaml
  apiVersion: kyverno.io/v1
  kind: ClusterPolicy
  metadata:
    name: verify-images-and-hardening
  spec:
    validationFailureAction: Enforce   # Use "Audit" first when testing
    rules:
      - name: check-cosign-signature
        verifyImages:
          - imageReferences: ["ghcr.io/myorg/*"]
            mutateDigest: true          # Rewrites :tag to @sha256:...
            attestors:
              - entries:
                  - keyless:
                      issuer: "https://token.actions.githubusercontent.com"
                      subject: "https://github.com/myorg/*"
  ```

---

## 5. Falco (eBPF Runtime Threat Detection)

* **What it is:** A CNCF runtime security engine that monitors live Linux kernel system calls (`execve`, `openat`, `connect`) using **eBPF** to detect anomalous behavior inside running containers—catching zero-day exploits or post-compromise actions that passed build and admission checks.
* **Where it is used:** Running continuously on every Kubernetes worker and control-plane node in production.
* **How it is installed & configured:**
  * Installed via Helm (`falcosecurity/falco`) as a **DaemonSet** across all nodes using the `modern_ebpf` driver (no kernel module compilation needed on kernels $\ge 5.8$).
  * Paired with **Falcosidekick** to route alerts to Slack, PagerDuty, Prometheus, or a SIEM (and optionally **Falco Talon** for automated pod quarantine/kill responses).
  * Configured via YAML rule files (`falco_rules.yaml` + custom overrides) matching syscall conditions and container/K8s metadata (`k8s.ns.name`, `k8s.pod.name`, `proc.name`).
* **Config Hint:**
  ```yaml
  # Custom Falco rule snippet (passed via Helm customRules)
  - rule: Production Shell Spawned
    desc: Alert when an interactive shell starts inside a production pod
    condition: spawned_process and container and k8s.ns.name = "production" and proc.name in (sh, bash, zsh)
    output: "Shell opened in prod (pod=%k8s.pod.name image=%container.image.repository cmd=%proc.cmdline)"
    priority: CRITICAL
  ```

---

## 6. Recommended Production Rollout Order

1. **Falco (Alert-Only):** Deploy first to gain runtime visibility and tune out noisy legitimate processes before wiring up PagerDuty.
2. **Trivy + Cosign (CI/CD):** Add scanning and signing to build pipelines so new artifacts have CVE reports, SBOMs, and signatures.
3. **Kyverno (`Audit` → `Enforce`):** Deploy policies in `Audit` mode, inspect `kubectl get policyreport -A` to verify existing apps pass, then flip to `Enforce`.