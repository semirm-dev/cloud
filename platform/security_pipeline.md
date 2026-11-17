# Security Pipeline Reference (Trivy / Cosign / Kyverno / Falco)

A production-oriented guide to securing workloads from **build → admit → run**: what each tool does, where it runs, how to install and configure it, and how the pieces fit with the platform bootstrap.

Cross-links: [`platform_overview.md`](platform_overview.md) (install order) · [`iam.md`](iam.md) (OIDC / CI identity) · [`cni.md`](cni.md) (NetworkPolicy)

---

## 1. End-to-End Lifecycle

```text
[Code Push / CI Build]
   ├── Trivy (+ Gitleaks / Semgrep) ──► CVEs, secrets, IaC, optional SAST
   └── Cosign ──► Signs image digest (OIDC/keyless or KMS) + Rekor receipt
         │
         ▼
[Kubernetes API Server / Admission]
   └── Kyverno ──► Verify Cosign + enforce Pod hardening / generate defaults
         │
         ▼
[Running Cluster]
   ├── Trivy Operator ──► Re-scan running Pods for newly disclosed CVEs
   └── Falco (+ Falcosidekick) ──► eBPF syscall detection → alerts / response
```

| Tool | Stage | Primary mechanism | Analogy |
| :--- | :--- | :--- | :--- |
| **Trivy** | CI + in-cluster | CVE, secret, SBOM & IaC scanner | Airport X-ray |
| **Gitleaks / Semgrep** | CI (optional) | Secret scanning / SAST on source | Baggage swab / code review bot |
| **Cosign** | CI + registry | OCI image signing & attestations | Tamper-evident seal |
| **Kyverno** | Admission webhook | Mutating & validating policies (YAML) | Bouncer at the door |
| **Falco** | Runtime (kernel) | eBPF syscalls + rule engine | 24/7 security camera |

**vs [`platform_overview.md`](platform_overview.md):** Overview steps 10–12 install Kyverno → trivy-operator → Falco late (after networking/TLS). This doc’s rollout (§8) still says **turn Falco on in alert-only early** if you want signal sooner—then keep **Kyverno `Enforce` last**. Both are compatible.

---

## 2. Trivy (CVE, Secret & Misconfiguration Scanner)

* **What it is:** Aqua’s scanner for OS/language CVEs, hardcoded secrets, IaC misconfigs (Terraform, K8s YAML, Dockerfiles), and SBOMs (CycloneDX/SPDX).
* **Where it is used:**
  1. **CI** — fail the build before the image is trusted for deploy.
  2. **`trivy-operator`** — continuous in-cluster re-scan when new CVEs appear after deploy.
* **How it is installed & configured:**
  * **CI:** CLI or `aquasecurity/trivy-action`.
  * **Cluster:** Helm chart `aqua/trivy-operator` into `trivy-system` (ArgoCD Wave 1).

**CI config hint**

```bash
trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed \
  --scanners vuln,secret myorg/app@sha256:...

trivy config --exit-code 1 --severity CRITICAL,HIGH ./deploy/
```

**Helm install + values hint**

```bash
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm upgrade --install trivy-operator aqua/trivy-operator \
  --namespace trivy-system --create-namespace \
  --values trivy-operator-values.yaml
```

```yaml
# trivy-operator-values.yaml
trivy:
  ignoreUnfixed: true
  severity: CRITICAL,HIGH
operator:
  scanJobTimeout: 5m
```

**Optional CI companions (overview step 13)**

* **Gitleaks** — git history / diff secret scan before build.
* **Semgrep** — SAST rules on source (language-specific); keep configs in-repo, fail on `ERROR`.

---

## 3. Cosign & Sigstore (Image Signing)

* **What it is:** Signs container image digests and attaches attestations (e.g. SBOM) next to the image in the OCI registry.
  * **Fulcio** — short-lived (~10 min) certs bound to CI OIDC identity (GitHub/GitLab). See [`iam.md`](iam.md).
  * **Rekor** — append-only transparency log so signatures stay verifiable after the cert expires.
* **Where it is used:** Immediately after `docker push` / `cosign` on `@sha256:...` (never on a moving tag alone).
* **How it is installed:** CI binary via `sigstore/cosign-installer`.
  * **Keyless:** CI needs `id-token: write`; private key lives only in RAM for the sign.
  * **Air-gapped / regulated:** KMS (`awskms://...`, `hashivault://...`) or file keypair; optional `--tlog-upload=false` if Rekor is unreachable (document the trust tradeoff).

**Config hint**

```bash
cosign sign --yes ghcr.io/myorg/app@sha256:...
cosign attest --yes --predicate sbom.cdx.json --type cyclonedx \
  ghcr.io/myorg/app@sha256:...
cosign verify \
  --certificate-identity 'https://github.com/myorg/app/.github/workflows/release.yaml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/myorg/app@sha256:...
```

Pin the identity to the signing workflow file **and** ref: a regexp like `https://github.com/myorg/.*` trusts any workflow on any branch in the org.

---

## 4. Minimal CI Sketch (Trivy → Cosign)

Illustrative GitHub Actions fragment—build once, scan the local image, push **that same image** only if it is clean, then sign its digest:

```yaml
permissions:
  contents: read          # Default for every job; each job widens only what it needs

concurrency:              # One run per ref; a newer push cancels the older run
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

env:
  IMAGE: ghcr.io/myorg/app

jobs:
  build-scan-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    outputs:
      digest: ${{ steps.push.outputs.digest }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - run: docker build -t "$IMAGE:$GITHUB_SHA" .
      - uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
        with:
          image-ref: ${{ env.IMAGE }}:${{ github.sha }}   # Local image, not yet pushed
          severity: CRITICAL,HIGH
          exit-code: "1"
          ignore-unfixed: true
      - uses: docker/login-action@8aa5831fb8d48d8f76594c7ddde61ae58019f550 # v4.8.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - id: push                                          # The scanned bytes; nothing is rebuilt
        run: |
          docker push "$IMAGE:$GITHUB_SHA"
          ref=$(docker inspect --format '{{index .RepoDigests 0}}' "$IMAGE:$GITHUB_SHA")
          echo "digest=${ref#*@}" >> "$GITHUB_OUTPUT"

  sign:
    needs: build-scan-push
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write     # Signature is stored next to the image
      id-token: write     # Cosign keyless; only this job can mint an OIDC token
    env:
      DIGEST: ${{ needs.build-scan-push.outputs.digest }}
    steps:
      - uses: docker/login-action@8aa5831fb8d48d8f76594c7ddde61ae58019f550 # v4.8.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: sigstore/cosign-installer@756fe2d284c7292c4e9b62c8a28f1e5629c59532 # v4.1.3
      - run: cosign sign --yes "$IMAGE@$DIGEST"
```

Actions are pinned by full commit SHA (version in the comment): a tag is mutable, so whoever controls the action's repo can repoint `@v4` at new code that runs with your token. Resolve with `git ls-remote https://github.com/<owner>/<repo> 'refs/tags/<tag>*'` (use the peeled `^{}` commit for annotated tags).

ArgoCD (or Flux) should deploy by **digest** (or a tag that Kyverno rewrites to digest via `mutateDigest`).

---

## 5. Kyverno (Admission Policy)

* **What it is:** Kubernetes-native policy engine as **mutating + validating** admission webhooks—runs before objects hit `etcd` (including ArgoCD syncs).
* **Where it is used:** Signature verification, Pod hardening, default mutation, generate baseline `NetworkPolicy` ([`cni.md`](cni.md)).
* **How it is installed:** Helm `kyverno/kyverno` into `kyverno`; **3 replicas** of `admissionController` in production. Policies as `ClusterPolicy` / `Policy`. Roll out per-rule `failureAction: Audit` → `Enforce` (the policy-level `validationFailureAction` is deprecated since Kyverno 1.13).

```bash
helm repo add kyverno https://kyverno.github.io/helm-charts
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace \
  --values kyverno-values.yaml
```

```yaml
# kyverno-values.yaml
# Webhooks fail closed: once a rule is on Enforce, no admission pod means no pod creates.
# The PDB stops a node drain taking all three at once.
admissionController:
  replicas: 3
  podDisruptionBudget:
    enabled: true
  container:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
```

**Config hint — verify images + basic hardening**

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-images-and-hardening
spec:
  background: true
  rules:
    # verifyImages skips any image it does not match, so pin where images may come from
    - name: allowed-registries
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        failureAction: Audit           # Flip to Enforce after PolicyReports look clean
        message: "Images must come from ghcr.io/myorg/."
        pattern:
          spec:
            =(initContainers):
              - image: "ghcr.io/myorg/*"
            =(ephemeralContainers):
              - image: "ghcr.io/myorg/*"
            containers:
              - image: "ghcr.io/myorg/*"
    - name: check-cosign-signature
      match:
        any:
          - resources:
              kinds: ["Pod"]
      verifyImages:
        - imageReferences: ["ghcr.io/myorg/*"]
          failureAction: Audit
          mutateDigest: true
          attestors:
            - entries:
                - keyless:
                    issuer: "https://token.actions.githubusercontent.com"
                    subject: "https://github.com/myorg/app/.github/workflows/release.yaml@refs/heads/main"
    - name: deny-latest-tag
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        failureAction: Audit
        message: "Image tag :latest is forbidden; use a digest or immutable tag. No tag means :latest."
        pattern:
          spec:
            =(initContainers):
              - image: "*:* & !*:latest"
            containers:
              - image: "*:* & !*:latest"
    - name: require-non-root
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        failureAction: Audit
        message: "Containers must run as non-root."
        pattern:
          spec:
            securityContext:
              runAsNonRoot: true
            containers:
              - securityContext:
                  allowPrivilegeEscalation: false
                  capabilities:
                    drop: ["ALL"]
```

Exclude system namespaces (`kube-system`, `kyverno`, …) via `exclude` / Namespace selectors so bootstrap controllers are not blocked.

The keyless `subject` pins one workflow file **and** ref (use `subjectRegExp` for several); `https://github.com/myorg/*` would accept a signature from any workflow on any branch in the org.

For a private registry, Kyverno's admission ServiceAccount needs registry read (Workload Identity / IRSA, or `imageRegistryCredentials`), or every pod fails verification once the rule is on `Enforce`.

---

## 6. Falco (eBPF Runtime Detection)

* **What it is:** CNCF runtime engine watching syscalls (`execve`, `openat`, `connect`, …) via **eBPF** for post-compromise / zero-day behavior that passed CI and admission.
* **Where it is used:** DaemonSet on every node; alerts only until tuned, then page / auto-respond.
* **How it is installed:** Helm `falcosecurity/falco` with `modern_ebpf` (kernels **>= 5.8**, no kernel module). Pair **Falcosidekick** (Slack, PagerDuty, Prometheus, SIEM) and optionally **Falco Talon** (quarantine/kill).

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm upgrade --install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --values falco-values.yaml
```

```yaml
# falco-values.yaml
driver:
  kind: modern_ebpf
falco:
  grpc:
    enabled: true
  grpcOutput:
    enabled: true
customRules:
  rules-production.yaml: |-
    - rule: Production Shell Spawned
      desc: Interactive shell in a production pod
      condition: >
        spawned_process and container and
        k8s.ns.name = "production" and
        proc.name in (sh, bash, zsh)
      output: >
        Shell in prod (pod=%k8s.pod.name image=%container.image.repository
        cmd=%proc.cmdline)
      priority: CRITICAL
      tags: [mitre_execution, shell]
```

Start **alert-only** (no PagerDuty / Talon) until false positives are tuned.

---

## 7. Verification

```bash
# CI artifacts
cosign verify \
  --certificate-identity 'https://github.com/myorg/app/.github/workflows/release.yaml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/myorg/app@sha256:...

# Kyverno
kubectl -n kyverno get pods
kubectl get clusterpolicy
kubectl get policyreport -A

# Trivy Operator
kubectl -n trivy-system get pods
kubectl get vulnerabilityreports -A

# Falco
kubectl -n falco get pods    # One Falco pod per node
kubectl -n falco logs -l app.kubernetes.io/name=falco --tail=50
```

---

## 8. Recommended Production Rollout

Aligned with [`platform_overview.md`](platform_overview.md) steps 10–13, with an optional early Falco soak:

1. **Falco (alert-only)** — optional early or with step 12; tune noise before paging.
2. **Trivy + Cosign (+ Gitleaks/Semgrep) in CI** — step 13; every new image scanned and signed.
3. **trivy-operator** — step 11; catch CVEs published after deploy.
4. **Kyverno `Audit` → `Enforce`** — step 10 policies in Wave 2; read `policyreport` before Enforce.

Never enable signature/`Enforce` policies until CI has been signing for long enough that existing deployable images verify cleanly.
