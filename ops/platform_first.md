# Roadmap: Senior Platform Engineer, Security-Focused

This roadmap gets you the official title first, then turns it toward security. It's self-contained. The follow-on is `blue.md` (DevSecOps → detection engineering → blue team).

| Stage | What it is | Duration | Title at the end |
|---|---|---|---|
| 1 | Study alongside your current job (4 h/day, 6 days/week) | 12 weeks | **Senior Platform Engineer** |
| 2 | Full-time platform job, security as your chosen focus | 12–18 months | **Platform Security / DevSecOps Engineer** |
| 3 | Detection engineering (optional next step) | see `blue.md` Phase 2 | **Detection / Security Platform Engineer** |

---

**Candidate Profile (from CV):**
- **Platform experience you already have:** two roles already titled Platform Engineer (Cisco SFCN, MFC). Kubernetes Operators/CRDs, Helm, Argo CD app-of-apps, GCP/AWS, a full observability stack (Prometheus, Grafana, Loki, OTel Collector, Elasticsearch), Keycloak SSO, GitOps secrets with Sealed Secrets (MFC), Kubernetes RBAC and AWS IAM tightening, the AWS Shield protection Operator.
- **Real gaps for platform job ads:** **Terraform/IaC** and **CI pipeline ownership**. Crossplane, Backstage and vCluster are nice to have, not requirements.
- **Rule:** apply at about 70% coverage. The rest is learned faster on the job, while being paid.

## Daily Study Framework (Stage 1)
- **Hour 1: Concepts.** Docs, design trade-offs, and how the thing fails or gets abused.
- **Hours 2–3: Hands-on lab.** Terminal work only.
- **Hour 4: Break it.** Misconfigure on purpose, check that the scanner, policy or test catches it, then fix it.

Commit everything to one public repo (`platform-lab/`). It's your portfolio.

---

## Stage 1: Get Hired as a Senior Platform Engineer (Weeks 1 – 12)

### Weeks 1–2: Terraform & IaC Security
- **Objective:** maintainable, modular, multi-account infrastructure code, with misconfigurations caught before `apply`.
- **Topics:**
  - Reusable Terraform / OpenTofu module design: inputs/outputs, versioning, composition.
  - Remote state in S3 with **native lockfile locking** (`use_lockfile = true`, Terraform ≥ 1.11 / OpenTofu ≥ 1.10). DynamoDB locking is deprecated.
  - Encrypted state; state access treated as a privileged secret; drift detection with `terraform plan` in CI.
  - Static analysis: `tflint`, **`trivy config`** (tfsec has been folded into Trivy), Checkov.
  - Policy-as-code on plans: OPA/Conftest or Checkov custom policies against `terraform show -json`.
  - Module tests with **Terratest** (Go).
  - Terragrunt: learn it only if job ads in your market ask for it.
- **Milestone:** a multi-tier AWS VPC, EKS cluster and IAM role hierarchy from your own modules, tested with Terratest. Pull requests fail on HIGH findings, and a planted public S3 bucket and `*:*` IAM policy must be caught.

### Week 3: CI Pipeline Security
- **Objective:** the pipeline is part of the attack surface. Harden it.
- **Topics:**
  - GitHub Actions architecture: reusable workflows, caching, matrix builds, environments with protection rules.
  - Hardening: actions pinned by commit SHA; least-privilege `permissions:` per job; `pull_request_target` and script-injection risks; why self-hosted runners must be ephemeral.
  - Tooling: StepSecurity Harden-Runner (egress control), OpenSSF Scorecard, zizmor (Actions static analysis), Dependabot / Renovate.
- **Milestone:** the Weeks 1–2 repo gets a hardened plan/apply pipeline with Scorecard ≥ 7, and zizmor reports nothing.

### Week 4: OIDC, Vault & External Secrets
- **Objective:** no long-lived static credentials anywhere.
- **Topics:**
  - OIDC federation: GitHub Actions → AWS `AssumeRoleWithWebIdentity` / GCP Workload Identity Federation. Trust policies scoped to repo + branch + environment.
  - HashiCorp Vault: Kubernetes auth method, dynamic database credentials, leases and revocation, audit device.
  - **External Secrets Operator (ESO)** with Vault / AWS Secrets Manager / GCP Secret Manager, as the step up from the Sealed Secrets setup you ran at MFC: central audit, dynamic and rotating credentials, and no single controller key whose loss exposes every secret in Git.
  - Secret scanning: Gitleaks / TruffleHog in pre-commit and CI, plus history scanning.
- **Milestone:** CI provisions infrastructure with **no static secrets** in GitHub settings, and the trust policy rejects forks and other branches. The app's Postgres credentials are short-lived Vault leases delivered by ESO through Argo CD. Revoking a lease kills access within the TTL.

### Weeks 5–7: CKA
- Mostly exam practice for you: kubeadm cluster setup and upgrade, etcd backup/restore, scheduling, Services/Ingress/Gateway API, NetworkPolicies, storage, troubleshooting broken nodes and workloads.
- Practise under time pressure with the killer.sh simulator (two sessions come with the exam).
- **Milestone:** pass CKA by the end of Week 7.
- **Start applying from Week 6.**

### Weeks 8–10: Crossplane Portfolio Piece, Secured by Default
- **Objective:** show a Kubernetes-native self-service control plane. Developers ask for infrastructure through a short claim, and the platform enforces the rules.
- **Topics:**
  - Crossplane architecture: Providers, Managed Resources, Composite Resource Definitions (XRD), Compositions, claims.
  - **Composition Functions in Go** (`function-sdk-go`): transformation and validation logic in code instead of YAML patching.
  - Provider-AWS, ProviderConfig with IRSA / Pod Identity (no static keys).
  - Admission policy: **Kyverno** validate/mutate/generate vs OPA/Gatekeeper vs Kubernetes-native ValidatingAdmissionPolicy (CEL).
  - Argo CD hardening: AppProjects restricting source repos, destinations and cluster-scoped resources; RBAC via Keycloak SSO groups; local admin disabled.
- **Milestone:** a `PostgresDatabase` (or `TeamEnvironment`) XRD that provisions RDS, delivers credentials through Vault/ESO, and generates a NetworkPolicy and a least-privilege IAM role per claim. Kyverno rejects claims without an owner label, and Argo CD delivers everything through a per-team AppProject. A developer writes a 10-line claim and gets a working, secured database.

### Week 11: Write-Up & CV
- A README with an architecture diagram and 3–4 Architecture Decision Records: Crossplane vs Terraform modules for self-service, migrating from Sealed Secrets to ESO + Vault (your MFC experience is the "before"), Kyverno vs Gatekeeper, the tenancy model.
- Publish it as a post on `semirmahovkic.xyz/blog`.
- CV: suggested headline and bullet wording that puts the platform and security work first (Cisco Operators, AWS Shield Operator, RBAC/IAM, Keycloak SSO, Sealed Secrets, the new lab). The final wording is yours.

### Week 12: Buffer & Interview Prep
- Platform system design: multi-tenant clusters, a golden-path pipeline from commit to production, a secrets architecture, disaster recovery for Argo CD and the clusters.
- Live Kubernetes troubleshooting; Terraform state, module and drift questions.
- Your story: "11 years building what platforms run, and the platforms themselves at Cisco and MFC".

---

## Stage 2: Full-Time Platform Engineer, Security-Focused (Months 4 – 18)

### Pick the Employer With This in Mind
Places where security is part of the platform job by default:
- **Regulated companies** such as fintech, banking, trading and payments. Your Tradeview and NAGA background is an advantage. Compliance (DORA, PCI-DSS, SOC 2, NIS2) makes guardrails required work.
- **Job ads titled "Platform Engineer (Security)" / "Cloud Platform Security Engineer"**, which is the target role itself.
- **Security vendors**, where the platform is the product (like Cisco SFCN).

In interviews, ask who owns admission policies, image signing and secrets management. "Nobody yet" is a good answer for you.

### What to Expect
About 70–80% normal platform work at first, 20–30% security. Grow the security share by volunteering: guardrails are usually unowned work.

### Security Work to Own
Learn each item when you take it on at work. Each comes with what it covers and what "done" looks like.

- [ ] **Admission guardrails & cluster hardening**
  - Pod Security Standards per namespace. Kyverno policies blocking privileged pods, `hostPath`/`hostPID`, root users, `CAP_SYS_ADMIN`, and requiring read-only root filesystems and `drop: ["ALL"]` capabilities. Seccomp `RuntimeDefault`, AppArmor profiles. `kube-bench` and `kubescape` for CIS benchmarks.
  - *Done when:* policies run in enforce mode cluster-wide, with documented exceptions.
- [ ] **Software supply chain**
  - SBOMs with Syft, scanning with Grype/Trivy, **Cosign keyless signing**, SLSA provenance (`slsa-github-generator`), signature and attestation verification at admission (Kyverno `verifyImages` or Sigstore Policy Controller).
  - *Done when:* an unsigned image cannot start in production.
- [ ] **Secrets**
  - Vault/ESO rollout across teams, removal of static cloud keys from all pipelines, secret scanning on every repo.
  - *Done when:* the static-credential inventory is zero, or every remaining one has an owner and expiry.
- [ ] **Access**
  - Kubernetes RBAC and cloud IAM reviews (Cloudsplaining, IAM Access Analyzer), SSO for every platform tool, a break-glass process that is audited.
  - *Done when:* nobody has standing cluster-admin.
- [ ] **Runtime detection & audit**
  - Falco (`modern_ebpf` driver) with custom rules for shells in containers, reverse shells and `/etc` writes. A Kubernetes API audit policy logging `RequestResponse` on Secrets and RBAC and `Metadata` elsewhere, shipped to the security team's SIEM.
  - *Done when:* the security team receives and uses the alerts.
- [ ] **Org-wide CI hardening**
  - Rolling the Week 3 standards (pinned actions, least privilege, OIDC, Scorecard) out across every team's pipelines, through shared reusable workflows.

### Certification
- **CKS around month 9.** The checklist above covers most of its domains: cluster setup and hardening, system hardening, microservice security, supply chain, runtime security and audit. CKS requires an active CKA, which you'll have from Stage 1.

### When to Move to the Next Title
Once you've owned **3 or more checklist items in production**, either ask for the Platform Security / DevSecOps title internally or start applying for it. Platform Security Engineer is a strong destination in its own right. Stage 3 is optional.

---

## Stage 3: Detection Engineering (optional)

Continue with **`blue.md` from Phase 2** (security telemetry, detections as code, adversary emulation, automated response). Stages 1–2 already cover nearly all of `blue.md` Phase 1.

---

## Deliberately Left Out (for now)

| Topic | Why it waits |
|---|---|
| SRE depth (SLOs and burn-rate alerting, chaos engineering, continuous profiling) | Good, but platform job ads rarely require it. Learn it if your team owns reliability. |
| Argo CD fleet management (ApplicationSets), Argo Rollouts | Learned fastest on a real multi-cluster platform. |
| Backstage / Port developer portals | TypeScript-heavy and only matters where a portal exists. Crossplane fits your Go and Operator strengths better. |
| vCluster, Karpenter | Pick up on the job when tenancy or cost becomes your problem. |
| Actions Runner Controller, Harbor, multi-arch builds | CI infrastructure; only matters if your team owns it. If so: BuildKit rootless or Buildah, since Kaniko was archived in 2025. |
| Terragrunt | Only if your market's job ads ask for it. |
