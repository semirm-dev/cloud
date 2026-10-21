# Study Checklist: DevSecOps → DFIR

Companion to `blue.md`. For each week: what to **learn**, the **tools**, where to **practice**, and how to **test yourself**. Tick a box only when you can do it without notes.

---

## Phase 1: DevSecOps Foundations (Weeks 1 – 12)

### Weeks 1–2: Terraform & IaC Security

**Learn**
- [ ] Terraform core workflow: `init`/`plan`/`apply`, providers, and how the dependency graph decides ordering
- [ ] Module design: inputs, outputs, versioned sources, and keeping modules small and composable
- [ ] State: what's inside it (resource attributes, often secrets), why it's a privileged secret, and who can read it
- [ ] S3 remote backend: encryption, bucket policy, versioning, and native locking with `use_lockfile = true`
- [ ] Drift: what causes it, how `terraform plan -detailed-exitcode` reveals it, and running it on a schedule in CI
- [ ] Common IaC misconfigurations: public S3 buckets, `"Action": "*"` / `"Resource": "*"` IAM, open security groups, unencrypted volumes
- [ ] Static scanning: how `trivy config` and Checkov differ, severity levels, and suppressing a finding with a justification
- [ ] Policy-as-code: writing Rego with Conftest against `terraform show -json` plan output
- [ ] Module tests with Terratest: apply, assert, destroy, and why tests need their own throwaway AWS account or prefix
- [ ] OpenTofu vs Terraform: what diverged after the license change and what's still compatible

**Tools**
- **Terraform / OpenTofu**: define the AWS landing zone (VPC, EKS, IAM roles) as code
- **`tflint`**: catch provider-specific errors and bad practices before `plan`
- **`trivy config`**: scan Terraform for misconfigurations and fail the PR on HIGH
- **Checkov**: second scanner with a large built-in policy set and graph-based checks
- **OPA/Conftest**: enforce your own rules (tags, regions, no wildcard IAM) on plan JSON
- **Terratest (Go)**: integration-test modules by deploying them for real

**Practice**
- [HashiCorp Terraform tutorials](https://developer.hashicorp.com/terraform/tutorials): work through the AWS and modules tracks to fill gaps in core syntax
- [TerraGoat](https://github.com/bridgecrewio/terragoat): scan this deliberately vulnerable Terraform repo with `trivy config` and Checkov, then fix every HIGH finding
- [CloudGoat](https://github.com/RhinoSecurityLabs/cloudgoat): deploy a scenario (it's Terraform under the hood), exploit it, then find the line of Terraform that caused it
- [The Big IAM Challenge](https://bigiamchallenge.com): read and exploit misconfigured IAM and resource policies to train your eye for over-broad IAM
- [Terraform S3 backend docs](https://developer.hashicorp.com/terraform/language/backend/s3): set up encrypted state with `use_lockfile = true` and verify a second `apply` is blocked by the lock
- Own lab ([lab.md](lab.md)): provision the EKS production checklist's VPC, EKS and IAM with Terraform, test once, then `terraform destroy` the same day

**Test yourself**
- [ ] Explain out loud why Terraform state must be treated as a secret, and list three things in it an attacker would want
- [ ] Without notes, write an S3 backend block with encryption and native locking
- [ ] Write a Conftest Rego rule that rejects any IAM policy with `"Action": "*"` and show it failing on a plan
- [ ] Plant a public S3 bucket in a PR and confirm the pipeline fails on HIGH before merge
- [ ] Explain how you would detect drift caused by someone editing a security group in the console

### Week 3: CI/CD Pipeline Security

**Learn**
- [ ] Poisoned Pipeline Execution: direct vs indirect, and why running untrusted PR code with secrets is the core risk
- [ ] `pull_request` vs `pull_request_target`: what each can access, and the "pwn request" pattern
- [ ] Script injection: how `${{ github.event.issue.title }}` in a `run:` step becomes shell execution, and the env-var fix
- [ ] Third-party actions: why tags are mutable, why pinning by commit SHA matters, and the tj-actions/changed-files compromise as an example
- [ ] `GITHUB_TOKEN` scoping: default permissions, per-job `permissions:`, and `permissions: {}` at the top level
- [ ] OIDC federation: the token's `sub`/`aud` claims and scoping an AWS trust policy to repo + branch + environment
- [ ] Environment protection rules: required reviewers and branch restrictions for deploy jobs
- [ ] Self-hosted runners: why persistent runners leak state between jobs and must be ephemeral
- [ ] AI agents in CI: prompt injection via issues/PRs/comments, and treating the agent as an untrusted identity

**Tools**
- **GitHub Actions**: the pipeline you harden
- **OIDC → AWS STS / GCP Workload Identity**: replace stored cloud keys with short-lived federated credentials
- **StepSecurity Harden-Runner**: monitor and restrict network egress from runners
- **OpenSSF Scorecard**: score the repo's security practices (target ≥ 7)
- **zizmor**: lint workflows for injection, unpinned actions and over-broad permissions
- **Dependabot / Renovate**: keep SHA-pinned actions and dependencies updated

**Practice**
- [CI/CD Goat](https://github.com/cider-security-research/cicd-goat): run the deliberately vulnerable CI/CD environment locally and solve its CTF challenges
- [GitHub Actions Goat](https://github.com/step-security/github-actions-goat): work through the vulnerable workflows and see what Harden-Runner detects
- [OWASP Top 10 CI/CD Security Risks](https://owasp.org/www-project-top-10-ci-cd-security-risks/): map each risk to a control in your own pipeline
- [GitHub Security Lab: preventing pwn requests](https://securitylab.github.com/resources/github-actions-preventing-pwn-requests/) and [untrusted input](https://securitylab.github.com/resources/github-actions-untrusted-input/): reproduce one injection in a scratch repo, then fix it
- [GitHub OIDC for AWS](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services): replace any static AWS keys in the Weeks 1–2 pipeline with an OIDC role
- Own lab ([lab.md](lab.md)): add a `helm/kind-action` job that spins up a throwaway kind cluster, with SHA-pinned actions and least-privilege `permissions:`, and run zizmor and Scorecard on the repo

**Test yourself**
- [ ] Explain why `pull_request_target` plus `actions/checkout` of the PR head is dangerous
- [ ] Without notes, write an AWS IAM trust policy that only allows OIDC tokens from `repo:<you>/security-lab:environment:prod`
- [ ] Spot the injection: given a workflow using `${{ github.event.pull_request.title }}` in `run:`, fix it in under 2 minutes
- [ ] Run zizmor on your workflows and get zero high-severity findings
- [ ] Explain what an AI coding agent in CI should and shouldn't be allowed to do, and why

### Week 4: Secrets Management & Argo CD Hardening

**Learn**
- [ ] Secret sprawl: where secrets leak (Git history, CI variables, logs, container images) and why deleting the commit isn't enough
- [ ] Vault basics: secrets engines, auth methods, policies, tokens and leases
- [ ] Vault Kubernetes auth: how a pod's service account token is exchanged for a Vault token, bound to namespace and SA
- [ ] Dynamic database credentials: per-lease Postgres users, TTLs, renewal and revocation
- [ ] Vault audit device: what gets logged, HMAC'd values, and why audit logs matter for later investigations
- [ ] External Secrets Operator: `SecretStore` vs `ClusterSecretStore`, `ExternalSecret`, refresh interval
- [ ] Sealed Secrets vs ESO + Vault: no central audit, re-sealing on rotation, controller key as single point of compromise
- [ ] Argo CD AppProjects: restricting source repos, destinations and cluster-scoped resources
- [ ] Argo CD RBAC via Keycloak SSO groups, and disabling the local `admin` account

**Tools**
- **HashiCorp Vault**: Kubernetes auth, dynamic DB credentials, leases, audit device
- **External Secrets Operator**: sync Vault secrets into Kubernetes Secrets
- **TruffleHog / Gitleaks**: pre-commit hooks and full Git history scans for leaked credentials
- **Argo CD**: the GitOps controller you lock down

**Practice**
- [OWASP WrongSecrets](https://github.com/OWASP/wrongsecrets): solve the challenges to see every way secrets get stored wrongly, including in Kubernetes and Vault
- [Vault dynamic database secrets tutorial](https://developer.hashicorp.com/vault/tutorials/db-credentials/database-secrets): issue and revoke Postgres credentials by hand before automating it
- [Vault Kubernetes auth docs](https://developer.hashicorp.com/vault/docs/auth/kubernetes): configure the auth method and bind a role to one namespace and service account
- [ESO HashiCorp Vault provider](https://external-secrets.io/latest/provider/hashicorp-vault/): connect ESO to Vault with Kubernetes auth
- [Argo CD projects](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/) and [RBAC](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/): build a restricted AppProject and map Keycloak groups to roles
- Own lab ([lab.md](lab.md)): install Vault, ESO and Argo CD on the kind `lab` cluster with Helm, deploy Postgres plus an app using dynamic creds, and plant a fake key to confirm Gitleaks blocks the commit

**Test yourself**
- [ ] Explain the three reasons to move from Sealed Secrets to ESO + Vault, as you would to a hiring manager
- [ ] Without notes, write an `ExternalSecret` that pulls one key from Vault into a Kubernetes Secret
- [ ] Revoke a Vault lease and show the app's Postgres user stops working
- [ ] Find a planted secret in old Git history with TruffleHog or Gitleaks in under 5 minutes
- [ ] Explain why a default Argo CD install is effectively cluster-admin, and which AppProject fields close that gap

### Week 5: Software Supply Chain

**Learn**
- [ ] Supply chain attack types: dependency confusion, typosquatting, slopsquatting, maintainer takeover, build system compromise
- [ ] SBOMs: SPDX vs CycloneDX, what they contain, and what they don't prove
- [ ] Vulnerability scanning: matching SBOM packages to advisories, false positives, and fixing vs accepting a CVE
- [ ] Sigstore keyless signing: Fulcio short-lived certs, Rekor transparency log, OIDC identity of the signer
- [ ] Attestations vs signatures: signing an image vs attaching provenance or SBOM as an in-toto attestation
- [ ] SLSA levels and what build provenance proves about where and how an artifact was built
- [ ] Vetting a new dependency: age, maintainers, download counts, recent ownership changes
- [ ] Go module integrity: `go.sum`, `GOSUMDB`, `GOFLAGS=-mod=readonly`, and `GOPRIVATE`
- [ ] SAST basics: what Semgrep rules catch and where they produce noise

**Tools**
- **Syft**: generate SBOMs from images and source
- **Grype / Trivy**: scan images and SBOMs for CVEs, block on CRITICAL
- **Cosign**: keyless image signing and attestation
- **Semgrep**: SAST on the Go service
- **SLSA provenance (`slsa-github-generator`)**: generate signed build provenance in GitHub Actions
- **OSV-Scanner**: check lockfiles against the OSV database
- **Socket or deps.dev**: check package reputation before adding a dependency

**Practice**
- [Sigstore docs](https://docs.sigstore.dev/): follow the Cosign quickstart and sign and verify an image keylessly from GitHub Actions
- [slsa-github-generator](https://github.com/slsa-framework/slsa-github-generator): add the Go builder or container generator to your pipeline and verify the provenance
- [Chainguard Academy](https://edu.chainguard.dev/): work through the Sigstore, SBOM and SLSA material
- [OpenSSF Developing Secure Software (LFD121)](https://training.linuxfoundation.org/training/developing-secure-software-lfd121/): free course; do the supply chain and dependency sections
- [Semgrep Academy](https://semgrep.dev/learn): learn to read and tune rules, then run Semgrep on your Go service
- Own lab ([lab.md](lab.md)): build the Go service in CI, push the signed image, and keep it ready for Weeks 9–10 when Kyverno will verify the signature on the kind cluster

**Test yourself**
- [ ] Explain keyless signing end to end: who issues the cert, what's logged in Rekor, and what `cosign verify` checks
- [ ] Without notes, write the `cosign verify` command with `--certificate-identity` and `--certificate-oidc-issuer` for your workflow
- [ ] Explain what an SBOM doesn't tell you, and why a clean scan isn't proof of safety
- [ ] Given a package name an AI assistant suggested, decide in under 5 minutes whether it's safe to add, and say which signals you used
- [ ] Introduce a dependency with a known CRITICAL CVE and confirm the pipeline blocks

### Weeks 6–8: CKA (prerequisite for CKS)

**Learn**
- [ ] CKA curriculum domains and their weights, and which ones you rarely touch day to day
- [ ] kubeadm: `init`, `join`, certificates, static pod manifests, and where the kubelet config lives
- [ ] Cluster upgrades with kubeadm: control plane first, drain/uncordon nodes, version skew rules
- [ ] etcd backup and restore with `etcdctl snapshot save/restore`, including certs and data directory changes
- [ ] Troubleshooting a broken node or control plane: kubelet logs via `journalctl`, static pod errors, `crictl`
- [ ] Networking: Services, DNS resolution, CNI, NetworkPolicy, Ingress and Gateway API
- [ ] Storage: StorageClass, PV, PVC, access modes and reclaim policies
- [ ] RBAC: Role vs ClusterRole, bindings, and `kubectl auth can-i --as`
- [ ] Exam speed: imperative commands, `--dry-run=client -o yaml`, `kubectl explain`, aliases, switching contexts

**Tools**
- **kubeadm**: build, upgrade and repair clusters by hand
- **`kubectl`**: everything in the exam
- **`etcdctl`**: snapshot and restore etcd
- **killer.sh**: exam simulator

**Practice**
- [killer.sh](https://killer.sh/): use both CKA simulator sessions that come with the exam, the first early in Week 7 and the second a few days before the exam
- [Killercoda CKA scenarios](https://killercoda.com/killer-shell-cka): free browser-based tasks; do them daily for speed
- [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way): build a cluster without kubeadm once to understand what kubeadm automates
- [etcd backup and restore docs](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/): practice snapshot and restore until you can do it from memory
- [CNCF curriculum](https://github.com/cncf/curriculum): check the current CKA PDF and tick off each domain
- Own lab ([lab.md](lab.md)): use the 2–3 kubeadm VMs to install, upgrade one minor version, back up etcd, break it, and restore

**Test yourself**
- [ ] Without notes, back up and restore etcd on a kubeadm cluster in under 10 minutes
- [ ] Upgrade a kubeadm control plane and one worker by one minor version without docs, except the official upgrade page
- [ ] Fix a node in `NotReady` caused by a stopped or misconfigured kubelet in under 5 minutes
- [ ] Explain how a pod resolves `svc.namespace.svc.cluster.local`, step by step
- [ ] Score at least 80% on a killer.sh CKA session before booking the exam

### Weeks 9–10: Cluster Hardening & Admission Control (CKS domains)

**Learn**
- [ ] Pod breakout paths: `privileged`, `hostPID`, `hostNetwork`, `hostPath` mounts, and dangerous capabilities like `CAP_SYS_ADMIN`
- [ ] Pod Security Standards (Privileged/Baseline/Restricted) and Pod Security Admission labels on namespaces
- [ ] `securityContext`: `runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation`, dropping capabilities
- [ ] seccomp `RuntimeDefault` and custom profiles; AppArmor profiles on nodes
- [ ] RBAC risks: wildcard verbs, `escalate`/`bind`/`impersonate`, `create pods` as a privilege path, reading Secrets
- [ ] API server hardening: anonymous auth, authorization modes, kubelet authentication, restricting access to the API endpoint
- [ ] Admission control: validating vs mutating webhooks and how Kyverno fits in
- [ ] Kyverno `verifyImages` for Cosign signatures, and policies blocking `hostPID`, `CAP_SYS_ADMIN` and root
- [ ] NetworkPolicy: default-deny, namespace isolation, and egress control
- [ ] CIS Kubernetes Benchmark: what `kube-bench` checks and which findings managed clusters can't fix

**Tools**
- **Kyverno**: admission policies, including Cosign image verification
- **Pod Security Standards**: built-in namespace-level pod restrictions
- **seccomp / AppArmor**: restrict syscalls and file access for containers
- **`kube-bench`**: run CIS Benchmark checks on nodes and control plane
- **`kubescape`**: scan cluster and manifests against NSA/MITRE/CIS frameworks
- **NetworkPolicies**: restrict pod-to-pod and egress traffic

**Practice**
- [Kubernetes Goat](https://madhuakula.com/kubernetes-goat/): deploy the vulnerable cluster and work through the scenarios, then write a Kyverno policy that would have prevented each one
- [Bad Pods](https://github.com/BishopFox/badPods): run each pod manifest, escape to the node, then confirm your Kyverno/PSA setup rejects it
- [Killercoda CKS scenarios](https://killercoda.com/killer-shell-cks): free hands-on tasks for each CKS domain
- [Wiz K8s LAN Party](https://k8slanparty.com/): CTF on Kubernetes network misconfigurations
- [Kyverno policy library](https://kyverno.io/policies/) and [verifyImages docs](https://kyverno.io/docs/policy-types/cluster-policy/verify-images/): start from library policies and add Cosign verification for your Week 5 image
- Own lab ([lab.md](lab.md)): harden the kind `lab` cluster (Cilium enforces NetworkPolicy), apply default-deny, run `kube-bench` on a kubeadm VM, and document the remaining findings

**Test yourself**
- [ ] Explain how `hostPID: true` plus `privileged: true` gives you root on the node
- [ ] Without notes, write a pod spec that passes the Restricted Pod Security Standard
- [ ] Write a Kyverno policy from memory that rejects containers running as root, and show it blocking a test pod
- [ ] Deploy an unsigned image and show Kyverno rejecting it, then deploy your signed one and show it admitted
- [ ] Given a ClusterRole, name which verbs or resources make it equivalent to cluster-admin
- [ ] Write a default-deny NetworkPolicy plus one allow rule in under 5 minutes

### Week 11: Runtime Detection & Audit Logging (CKS domain, bridge to Phase 2)

**Learn**
- [ ] How Falco works: syscall events from the kernel, the `modern_ebpf` driver, and enrichment with container/Kubernetes metadata
- [ ] Falco rule anatomy: `rule`, `condition`, `output`, `priority`, lists and macros
- [ ] Tuning: overriding default rules, exceptions, and why noisy rules get ignored
- [ ] What a reverse shell and a container escape look like at syscall level
- [ ] Kubernetes audit policy: stages, levels (`None`, `Metadata`, `Request`, `RequestResponse`) and rule ordering
- [ ] Why `RequestResponse` on Secrets is a trade-off (it logs secret values) and how to control access to audit logs
- [ ] Audit log backends: log file vs webhook, and enabling them via API server flags in a kubeadm static pod
- [ ] Falcosidekick: forwarding alerts to Slack, Loki or a SIEM
- [ ] Mapping detections to MITRE ATT&CK for Containers techniques

**Tools**
- **Falco (`modern_ebpf` driver)**: runtime syscall detection
- **Kubernetes API server audit policy**: record who did what to which object
- **Falcosidekick**: route Falco alerts to other systems

**Practice**
- [Falco docs](https://falco.org/docs/) and [rules concepts](https://falco.org/docs/concepts/rules/): install with Helm and write your first custom rule
- [falcosecurity/rules](https://github.com/falcosecurity/rules): read the default rules for shells in containers and writes below `/etc`, and adapt them
- [falcosecurity/event-generator](https://github.com/falcosecurity/event-generator): generate suspicious activity to confirm your rules fire
- [Kubernetes auditing docs](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/): write the audit policy and enable it on the API server
- [Kubernetes Goat](https://madhuakula.com/kubernetes-goat/): rerun earlier attack scenarios with Falco running and check what it catches and misses
- Own lab ([lab.md](lab.md)): run Falco on the kind `lab` cluster (or a kubeadm VM if the WSL2 kernel doesn't support the driver), send alerts through Falcosidekick to Loki, and enable the audit policy on a kubeadm VM

**Test yourself**
- [ ] Without notes, write a Falco rule that fires on an outbound shell connection from a container
- [ ] Simulate a reverse shell and a write to `/etc` in a pod, and show both alerts within seconds
- [ ] Without notes, write an audit policy: `RequestResponse` for Secrets and RBAC objects, `Metadata` for everything else
- [ ] From an audit log, find who deleted a given Secret and when, in under 5 minutes
- [ ] Explain what Falco can see that audit logs can't, and the reverse

### Week 12: CKS + Job Readiness (buffer week)

**Learn**
- [ ] CKS curriculum domains and weights; re-check weak areas from killer.sh results
- [ ] Exam speed for CKS-specific tasks: AppArmor, seccomp, audit policy, Falco, image scanning, admission configuration
- [ ] Editing static pod manifests safely (back up first, wait for the API server to restart)
- [ ] How to tell the "secure delivery path" story in one diagram: commit → IaC scan → OIDC → Vault/ESO → signed image → admission → runtime
- [ ] How to frame your existing security work (firewall/VPN Operator, AWS Shield Operator, RBAC/IAM, Keycloak SSO, Sealed Secrets) as security achievements on a CV

**Tools**
- **killer.sh**: CKS simulator
- **`kubectl`, Kyverno, Falco, Trivy, `kube-bench`**: everything from Weeks 9–11, at exam speed

**Practice**
- [killer.sh](https://killer.sh/): use both CKS simulator sessions; redo every question you missed until it's fast
- [Killercoda CKS scenarios](https://killercoda.com/killer-shell-cks): daily speed drills on weak domains
- [Wiz EKS Cluster Games](https://eksclustergames.com/): CTF on EKS misconfigurations, a good warm-up for cloud-side Kubernetes interviews
- [CNCF curriculum](https://github.com/cncf/curriculum): tick off the current CKS PDF line by line
- Own lab ([lab.md](lab.md)): rebuild the kind `lab` cluster from Git with the full Phase 1 stack in one command, and use it for the capstone diagram and write-up

**Test yourself**
- [ ] Score at least 80% on a killer.sh CKS session before the exam
- [ ] Present the capstone diagram out loud in 5 minutes, naming the threat each control stops
- [ ] Destroy and rebuild the whole lab from Git without manual steps
- [ ] Answer "tell me about a security problem you solved" with a story from your CV in under 2 minutes
- [ ] Explain how you'd investigate a Falco "shell in container" alert using only the tools you built in Phase 1

---

## Phase 2: Detection & Investigation (Weeks 13 – 24)

### Weeks 13–14: Security Telemetry Pipeline

**Learn**
- [ ] CloudTrail record anatomy: `userIdentity`, `eventSource`, `eventName`, `sourceIPAddress`, `userAgent`, `errorCode`, `requestParameters`
- [ ] CloudTrail management vs data events: data events (S3 object reads, Lambda invokes) are off by default, which is a common blind spot
- [ ] CloudTrail limits: Event history keeps 90 days of management events only; a trail to S3 is what you keep long term
- [ ] VPC Flow Logs fields: 5-tuple, action ACCEPT/REJECT, bytes. No payload, no hostnames
- [ ] Kubernetes audit levels (`None`, `Metadata`, `Request`, `RequestResponse`) and stages, plus where `user.username`, `sourceIPs` and `objectRef` live in an event
- [ ] Linux auth sources: `/var/log/auth.log` vs `/var/log/secure` vs journald; what successful and failed sshd and sudo lines look like
- [ ] Elastic Common Schema: `event.category`/`event.action`/`event.outcome`, `user.name`, `source.ip`, `cloud.*`, `orchestrator.*`. Why normalizing lets one query cover many sources
- [ ] Never sample or drop security events: audit and auth events go through unfiltered, and only debug noise gets cut
- [ ] eBPF sources: Cilium Hubble flows (network, with pod identity) vs Tetragon process events (exec, file, syscall)
- [ ] Hot/warm/cold retention tiers, cost per GB, and compliance retention for audit logs (often 1 year or more)

**Tools**
- **Vector or Fluent Bit**: collect, parse and remap logs to ECS before they reach the SIEM
- **Elastic Security or OpenSearch Security Analytics**: the SIEM where everything lands and gets searched
- **AWS CloudTrail**: the API audit trail for every AWS account
- **VPC Flow Logs**: network metadata for the VPC
- **Linux auth logs**: SSH and sudo activity on hosts and nodes
- **Cilium Hubble / Tetragon**: eBPF network-flow and process telemetry from the cluster

**Practice**
- [Elastic Common Schema reference](https://www.elastic.co/docs/reference/ecs): map one raw CloudTrail event and one Kubernetes audit event to ECS fields by hand
- [Elastic AWS CloudTrail integration](https://www.elastic.co/docs/reference/integrations/aws/cloudtrail): ingest a trail from S3 and check which ECS fields it fills in
- [flAWS 2 (Defender path)](http://flaws2.cloud): work through raw CloudTrail logs with `jq`, then load the same logs into your SIEM
- [OTRF Security-Datasets](https://github.com/OTRF/Security-Datasets): load prerecorded attack datasets so you have known-bad data to search before your own pipeline is ready
- [kind auditing guide](https://kind.sigs.k8s.io/docs/user/auditing/): **your lab.** Add your Week 11 audit policy to `platform-lab/kind.yaml`, enable Hubble on the Cilium you already install, and ship audit, Falco (via [Falcosidekick](https://github.com/falcosecurity/falcosidekick)), Hubble and node auth logs to one SIEM index pattern
- [Tetragon getting started](https://tetragon.io/docs/getting-started/): deploy it on the kind cluster and compare its exec events with Falco's output for the same reverse shell

**Test yourself**
- [ ] Explain why trace-style sampling is fine for latency debugging but unacceptable for audit logs
- [ ] Without notes, list five CloudTrail fields you would check first in any investigation, and why each matters
- [ ] Explain one attack that VPC Flow Logs miss and one that CloudTrail misses
- [ ] From memory, write the audit policy rule that logs Secrets at `RequestResponse`, and explain why logging Secrets at `RequestResponse` can leak the secret values into your SIEM
- [ ] Run one ES|QL query that returns events from at least three different sources (audit, CloudTrail, auth) by filtering on a single ECS field
- [ ] Explain how you'd tier retention for a 1-year audit requirement without keeping it all in hot storage

### Week 15: Cloud-Native Detection Services

**Learn**
- [ ] GuardDuty data sources: CloudTrail management events, VPC Flow Logs and DNS logs, all read without you enabling them yourself
- [ ] GuardDuty protection plans: EKS Protection (audit log monitoring), Runtime Monitoring (agent on EKS/EC2/ECS), S3 Protection, Malware Protection
- [ ] GuardDuty finding type naming (`ThreatPurpose:ResourceType/ThreatFamily`) and severity levels
- [ ] Security Hub as an aggregator: findings formats (ASFF; OCSF in the newer Security Hub), cross-account and cross-region aggregation
- [ ] GCP Security Command Center tiers and its main detectors (Event Threat Detection, Container Threat Detection)
- [ ] Routing findings out: EventBridge rules to a SIEM or a notification target
- [ ] What managed services can't see: your app logic, Keycloak, in-cluster RBAC misuse that looks legitimate, slow insider activity

**Tools**
- **Amazon GuardDuty (incl. EKS Protection & Runtime Monitoring)**: managed threat detection for AWS accounts and EKS
- **AWS Security Hub**: aggregates and normalizes findings across services and accounts
- **GCP Security Command Center**: the GCP equivalent for findings and threat detection

**Practice**
- [Amazon GuardDuty Workshop](https://catalog.workshops.aws/guardduty/en-US/introduction): run the attack simulation and investigate each finding it produces
- [GuardDuty sample findings](https://docs.aws.amazon.com/guardduty/latest/ug/sample_findings.html): generate sample findings to test your EventBridge-to-SIEM route without a real attack
- [amazon-guardduty-tester](https://github.com/awslabs/amazon-guardduty-tester): trigger real findings in a sandbox account, then find the matching CloudTrail and flow-log evidence yourself
- [GuardDuty active finding types](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_finding-types-active.html): use it as the source for your coverage map (what's covered vs. what needs a custom rule)
- **Your lab:** GuardDuty can't see kind. Write down which Week 13–14 lab detections (Falco, audit) have a GuardDuty equivalent on EKS, then confirm it on the same-day EKS cluster from lab.md

**Test yourself**
- [ ] Explain which three data sources GuardDuty reads by default, and what you lose if you also disable your own CloudTrail trail
- [ ] Explain the difference between EKS Protection and Runtime Monitoring, and name one attack only Runtime Monitoring catches
- [ ] Without notes, decode the finding type `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS` and say what you'd check first
- [ ] Name three things in your stack that no managed service will detect, and the log source you'd use instead
- [ ] Write the EventBridge event pattern that sends only GuardDuty findings with severity 7 or higher to your SIEM

### Weeks 16–17: Detection Query Languages & Logic

**Learn**
- [ ] ES|QL pipeline model: `FROM` → `WHERE` → `EVAL` → `STATS ... BY` → `SORT`/`LIMIT`
- [ ] EQL event categories (`process where`, `network where`, `file where`) and `sequence by <field> with maxspan=` for ordered multi-step behavior
- [ ] When to use a single-event match, a threshold/aggregation (counts per identity), or a sequence
- [ ] Translating between languages: SPL `stats count by`, KQL `summarize count() by`, ES|QL `STATS COUNT(*) BY`
- [ ] Time windows and bucketing: why a 5-minute burst disappears in a 24-hour count
- [ ] Baseline vs anomaly: "first time seen" logic for identities, IPs, user agents
- [ ] False positives: tuning with allowlists by identity or `userAgent` without blinding the rule
- [ ] Kubernetes audit fields that matter for detections: `verb`, `objectRef.resource`, `responseStatus.code`, `user.username`, `requestObject`
- [ ] CloudTrail detections: `errorCode: AccessDenied` bursts, `AuthorizeSecurityGroupIngress` with `0.0.0.0/0`, `GetCallerIdentity` as recon

**Tools**
- **EQL and ES|QL (primary)**: write the detections and hunt queries in Elastic
- **Splunk SPL**: read and translate (Splunk BOTS uses it)
- **Microsoft KQL**: read and translate (Sentinel, Defender, Entra logs use it)

**Practice**
- [ES|QL reference](https://www.elastic.co/docs/reference/query-languages/esql) and [EQL reference](https://www.elastic.co/docs/reference/query-languages/eql): write the 8 milestone detections against your Weeks 13–14 data
- [Elastic detection-rules, AWS rules](https://github.com/elastic/detection-rules/tree/main/rules/integrations/aws): read 10 production rules and compare their logic and exclusions with yours
- [Splunk BOTS v3 dataset](https://github.com/splunk/botsv3): load it into a free Splunk instance and answer the AWS-related questions with SPL
- [Kusto Detective Agency](https://detective.kusto.io): solve the cases to learn KQL by investigating
- [KC7](https://kc7cyber.com): play one full game; it's KQL investigation against realistic company logs
- **Your lab:** in the kind cluster, `kubectl exec` into a pod, spawn a shell and `curl` out, then confirm your EQL sequence (shell then outbound connection) fires on Falco/Tetragon events and doesn't fire on a plain `kubectl exec ls`

**Test yourself**
- [ ] Without notes, write an EQL sequence for a shell process in a container followed by an outbound network connection from the same container within 1 minute
- [ ] Without notes, write an ES|QL query that counts Kubernetes `403` responses per `user.username` in 5-minute buckets and returns the ones above 20
- [ ] Translate that same query into SPL and KQL
- [ ] Explain when a threshold rule beats a sequence rule, with one example of each from your 8 detections
- [ ] Write a query for a ClusterRoleBinding to `cluster-admin` created by anyone other than your GitOps service account
- [ ] Explain how you'd tune the security-group `0.0.0.0/0` rule for a team that legitimately opens port 443 to the internet

### Week 18: Identity Attacks

**Learn**
- [ ] IAM privilege-escalation paths: `iam:PassRole` + `ec2:RunInstances`/`lambda:CreateFunction`, `CreateAccessKey` on another user, `UpdateAssumeRolePolicy`, `CreatePolicyVersion` with `--set-as-default`, `AttachUserPolicy`
- [ ] Access key prefixes: `AKIA` (long-term user key) vs `ASIA` (temporary STS credentials), and what each implies in an investigation
- [ ] Role chaining in CloudTrail: following `AssumeRole` via `userIdentity.sessionContext`, role session name and `sourceIdentity`
- [ ] Token theft: stolen instance-role credentials used from outside AWS, stolen kubeconfig or service account tokens, OIDC refresh tokens
- [ ] Keycloak events: user events (`LOGIN`, `LOGIN_ERROR`, `CODE_TO_TOKEN`) vs admin events; they're off by default per realm and need to reach your SIEM
- [ ] Entra ID sign-in logs (interactive vs non-interactive, `conditionalAccessStatus`, `deviceDetail`) and the Okta System Log (`eventType`, `outcome.result`); read the schemas, no tenant needed
- [ ] Impossible travel and new-device logic, and why VPNs and cloud egress IPs make it noisy

**Tools**
- **CloudTrail**: evidence of IAM changes, `AssumeRole` chains and key creation
- **Keycloak event logs**: SSO login and admin activity for your own services
- **Entra ID / Okta sign-in log schemas**: what enterprise identity evidence looks like
- **PMapper or Cloudsplaining**: find which principals can escalate before an attacker does

**Practice**
- [Rhino Security Labs AWS IAM Privilege Escalation](https://github.com/RhinoSecurityLabs/AWS-IAM-Privilege-Escalation): pick 3 methods, run them in a sandbox account, and capture the CloudTrail events each leaves
- [Hacking the Cloud: IAM privilege escalation](https://hackingthe.cloud/aws/exploitation/iam_privilege_escalation/): read the attacker view of each permission you write a detection for
- [PMapper](https://github.com/nccgroup/PMapper): graph your sandbox account and find every principal that can reach admin
- [CloudGoat](https://github.com/RhinoSecurityLabs/cloudgoat): play `iam_privesc_by_rollback` and `iam_privesc_by_attachment` as the attacker, then investigate your own trail as the defender
- [PwnedLabs](https://pwnedlabs.io): do the free AWS labs that cover IAM enumeration and credential abuse
- **Your lab:** deploy Keycloak on the kind cluster, enable user and admin events for the realm, ship them to the SIEM and trigger a brute force plus a login from a new IP and browser

**Test yourself**
- [ ] Explain how `iam:PassRole` plus `lambda:CreateFunction` gives escalation without the attacker ever touching an IAM policy
- [ ] Without notes, write a query for `CreateAccessKey` where the requesting identity is not the user the key belongs to
- [ ] Given a CloudTrail event signed with an `ASIA` key, explain how you'd trace it back to the original human or workload
- [ ] Name the Keycloak event types you'd alert on for credential stuffing and for admin takeover
- [ ] Explain why impossible-travel alerts are noisy and two ways to cut the noise without losing real hits

### Week 19: Sigma & ATT&CK (read and adapt, not build)

**Learn**
- [ ] Sigma rule structure: `logsource` (`product`/`category`/`service`), `detection` selections, `condition`, `falsepositives`, `level`
- [ ] Field modifiers (`|contains`, `|startswith`, `|endswith`, `|re`) and how they become query syntax
- [ ] pySigma backends and processing pipelines: why field mapping (Sigma names → ECS) breaks most rules out of the box
- [ ] ATT&CK structure: tactics → techniques → sub-techniques, and the Cloud (IaaS, Identity Provider) and Containers matrices
- [ ] Navigator layers: scoring techniques to show coverage, and why "covered" doesn't mean "detected reliably"
- [ ] The Microsoft Threat Matrix for Kubernetes as a Kubernetes-specific view of ATT&CK

**Tools**
- **Sigma**: the vendor-neutral rule format the community shares detections in
- **`sigma-cli` / pySigma**: convert Sigma rules to your SIEM's query language
- **MITRE ATT&CK Navigator**: build and visualize your coverage layer

**Practice**
- [SigmaHQ rules](https://github.com/SigmaHQ/sigma): pick 5 rules under `rules/cloud/aws` and `rules/linux`, then convert and adapt them to your SIEM
- [sigma-cli](https://github.com/SigmaHQ/sigma-cli): install the Elasticsearch backend and run `sigma convert` with an ECS pipeline; fix the fields it gets wrong
- [Uncoder.io](https://uncoder.io): cross-check your conversions and compare SPL, KQL and ES|QL output for the same rule
- [ATT&CK Navigator](https://mitre-attack.github.io/attack-navigator/): build a layer scoring your Weeks 16–18 detections
- [Threat Matrix for Kubernetes](https://microsoft.github.io/Threat-Matrix-for-Kubernetes/): mark which techniques your kind-lab audit and Falco detections cover
- **Your lab:** run each of the 5 converted rules against your kind and CloudTrail data, and record which ones fire, stay silent or are too noisy

**Test yourself**
- [ ] Without notes, write a Sigma rule for CloudTrail `StopLogging` or `DeleteTrail`
- [ ] Explain why a correctly converted Sigma rule can still never fire in your SIEM
- [ ] Explain the difference between a tactic and a technique, using one cloud example
- [ ] Name three ATT&CK techniques in your coverage layer marked "covered" that you have never actually seen fire
- [ ] From memory, map your 8 Weeks 16–17 detections to ATT&CK technique IDs

### Weeks 20–21: Adversary Emulation & Investigation

**Learn**
- [ ] Stratus Red Team lifecycle: `warmup` → `detonate` → `revert` → `cleanup`, and why you always clean up
- [ ] Atomic Red Team test structure (technique ID, executor, cleanup) and what it's useful for on Linux nodes
- [ ] Peirates: what an attacker does from inside a compromised pod (service account token theft, secret reads, pod creation)
- [ ] Investigation questions to answer only from logs: which identity, from which IP and user agent, what was touched, when, in what order
- [ ] Pivoting: from one alert to the identity, then to all its activity before and after
- [ ] Timeline building: UTC everywhere, log delivery delay (CloudTrail usually within minutes), event time vs ingest time
- [ ] Scoring results as detected / missed / noisy, and writing the gap down instead of hiding it

**Tools**
- **Stratus Red Team (AWS, GCP, Kubernetes techniques)**: detonate cloud and Kubernetes attack techniques on demand
- **Atomic Red Team**: run small, scripted ATT&CK tests on Linux hosts and nodes
- **Peirates (Kubernetes)**: emulate an attacker inside a pod

**Practice**
- [Stratus Red Team technique list](https://stratus-red-team.cloud/attack-techniques/list/): pick 6 techniques across AWS and Kubernetes (e.g. `aws.defense-evasion.cloudtrail-stop`, `aws.persistence.iam-create-admin-user`, `k8s.privilege-escalation.privileged-pod`), detonate and investigate each
- [Grimoire](https://github.com/DataDog/grimoire): detonate Stratus techniques and get the exact CloudTrail events they produced, to check your investigation against
- [Invictus aws_dataset](https://github.com/Invictus-ir/aws_dataset): investigate a prerecorded Stratus attack from the CloudTrail logs alone before looking at the answer
- [Peirates](https://github.com/inguardians/peirates): **your lab.** Run it from a pod in the kind cluster, then rebuild what it did using only audit, Falco and Hubble logs
- [Atomic Red Team](https://github.com/redcanaryco/atomic-red-team): run Linux atomics (credential access, persistence) on a kind node container and check your auth-log and Tetragon coverage
- [CyberDefenders](https://cyberdefenders.org) / [Blue Team Labs Online](https://blueteamlabs.online): do 2 cloud or log-analysis investigations against data you didn't generate

**Test yourself**
- [ ] For one detonated technique, write a one-page timeline from memory of the logs: identity, source IP, actions, timestamps
- [ ] Explain why you investigate from logs before reading the technique's documentation
- [ ] Without notes, write the query that pivots from one suspicious access key to everything it did in the past 24 hours
- [ ] Explain how CloudTrail delivery delay and clock skew can put events in the wrong order on your timeline
- [ ] For each technique you scored "missed", name the log source or query that would have caught it
- [ ] Explain what Peirates did with the service account token and which audit-log fields prove it

### Weeks 22–23: IR Playbooks & Containment

**Learn**
- [ ] IR lifecycle: prepare, detect, contain, eradicate, recover, lessons learned; and how NIST SP 800-61r3 now maps it to the CSF 2.0 functions
- [ ] Containment that preserves evidence: snapshot before terminate, isolate before delete, export logs before rotating anything
- [ ] Leaked IAM key: deactivate (not delete) the key, revoke active role sessions with a `aws:TokenIssueTime` deny, check for persistence (new users, keys, roles)
- [ ] Compromised EC2: termination protection, quarantine security group, EBS snapshot, memory capture before shutdown; existing tracked connections can survive a security-group change
- [ ] Compromised pod: deny-all NetworkPolicy by label, cordon the node, capture the container filesystem and logs before you scale to zero
- [ ] Compromised Keycloak account: disable the user, sign out sessions, revoke tokens (realm "not before"), review admin events
- [ ] Chain of custody basics: hash every artifact, record who collected what and when

**Tools**
- **AWS CLI**: isolate, snapshot, deactivate keys and export evidence in AWS
- **`kubectl`**: cordon, isolate, capture and scale down workloads
- **AWS Security Incident Response Guide**: AWS's reference for cloud IR preparation and response
- **NIST SP 800-61r3**: the incident response framework you structure playbooks around

**Practice**
- [AWS Security Incident Response Guide](https://docs.aws.amazon.com/whitepapers/latest/aws-security-incident-response-guide/welcome.html): read the containment and forensics sections before writing your playbooks
- [NIST SP 800-61r3](https://csrc.nist.gov/pubs/sp/800/61/r3/final): use it to structure the sections of your 4 playbooks
- [aws-incident-response-playbooks](https://github.com/aws-samples/aws-incident-response-playbooks): compare your leaked-key and compromised-EC2 playbooks with AWS's examples
- [AWS CIRT: Unauthorized IAM Credential Use](https://catalog.workshops.aws/aws-cirt-unauthorized-iam-credential-use): run the simulation and use it as the end-to-end test of your leaked-key playbook
- [AWS CIRT: Cryptominer Based Security Events](https://catalog.workshops.aws/aws-cirt-cryptominer-simulation-and-detection): run it and test your compromised-EC2 playbook against it
- **Your lab:** run the compromised-pod and compromised-Keycloak playbooks on the kind cluster, timing each step and noting any command that destroyed evidence

**Test yourself**
- [ ] Explain why you deactivate a leaked access key instead of deleting it
- [ ] Without notes, write the AWS CLI commands to isolate an instance, enable termination protection and snapshot its volumes
- [ ] Explain why deactivating an IAM user's key doesn't kill a role session the attacker already assumed, and how you revoke it
- [ ] Without notes, write the NetworkPolicy that isolates one pod by label while you collect evidence
- [ ] Explain the order of operations for a compromised pod and what evidence you lose if you scale to zero first
- [ ] Explain why swapping a security group may not cut an attacker's existing connection

### Week 24: Capstone + Cert (buffer week)

**Learn**
- [ ] How to write an investigation report: executive summary, timeline, scope, root cause, containment, recommendations
- [ ] Sanitizing lab material: remove account IDs, keys, IPs and internal hostnames before publishing
- [ ] AWS Security – Specialty domains: detection, incident response, infrastructure security, IAM, data protection, governance
- [ ] Exam-heavy services you haven't used yet in this phase: KMS key policies, Macie, Detective, AWS Organizations SCPs
- [ ] Gaps from the Weeks 20–21 "missed" list and how you'd close each one

**Tools**
- **AWS CLI**: re-run the playbook end to end for the write-up
- **Elastic Security or OpenSearch Security Analytics**: pull the screenshots and queries for the case study

**Practice**
- [AWS Certified Security – Specialty](https://aws.amazon.com/certification/certified-security-specialty/): download the exam guide and check yourself against each task statement
- [Amazon GuardDuty Workshop](https://catalog.workshops.aws/guardduty/en-US/introduction): redo it quickly as exam review for detection and response questions
- [AWS CIRT: SSRF on IMDSv1](https://catalog.workshops.aws/aws-cirt-ssrf-imdsv1-simulation-and-detection): run one more full investigation as the timeline for your write-up
- [Splunk BOTS v3](https://github.com/splunk/botsv3): answer any AWS questions you skipped in Weeks 16–17 as a timed final check
- **Your lab:** rebuild the kind cluster from scratch with the full pipeline from Git, then detonate one technique and run its playbook end to end for the capstone

**Test yourself**
- [ ] Explain your pipeline in 2 minutes: sources, normalization, SIEM, retention
- [ ] Without notes, write the full timeline of one investigation from the capstone
- [ ] Explain which of your detections GuardDuty already covers and why you kept or dropped yours
- [ ] Pass a full-length practice exam for AWS Security – Specialty and review every wrong answer
- [ ] Explain one playbook step you changed after running it, and why

---

## Phase 3: DFIR (Weeks 25 – 36)

### Weeks 25–26: Windows & Active Directory for Defenders

**Learn**
- [ ] Kerberos flow: AS-REQ/TGT, TGS-REQ/service ticket, and where an attacker abuses each step
- [ ] Kerberoasting: why any domain user can request a ticket for an SPN account and crack it offline; why RC4 (etype 0x17) in 4769 matters
- [ ] Pass-the-hash: NTLM authentication with a hash instead of a password, and how it looks in 4624 (logon type 3, NTLM)
- [ ] DCSync: replication rights (`DS-Replication-Get-Changes-All`) abused from a non-DC, and why event 4662 with replication GUIDs is the signal
- [ ] Persistence: new services (7045 / 4697), scheduled tasks (4698), Run keys, new local admin (4720 + 4732)
- [ ] Logon types (2, 3, 4, 5, 10) and what each tells you about how the attacker got in
- [ ] Sysmon events 1 (process), 3 (network), 10 (process access, e.g. LSASS), 11 (file create), and why Sysmon is richer than 4688
- [ ] Where Windows artifacts live: `C:\Windows\System32\winevt\Logs`, Prefetch, Amcache, Shimcache, registry hives

**Tools**
- **Sysmon (SwiftOnSecurity / Olaf Hartong config)**: endpoint telemetry beyond native Windows logs
- **Winlogbeat**: ship Windows and Sysmon events into your SIEM
- **Atomic Red Team**: run single ATT&CK techniques to validate detections
- **Chainsaw / Hayabusa**: fast Sigma-based hunting over offline `.evtx` files
- **Eric Zimmerman's tools (EvtxECmd, PECmd, Timeline Explorer)**: parse Windows artifacts into timelines

**Practice**
- [GOAD (Game of Active Directory)](https://github.com/Orange-Cyberdefense/GOAD): build a vulnerable AD lab if you'd rather not hand-build the DC + workstation
- [EVTX-ATTACK-SAMPLES](https://github.com/sbousseaden/EVTX-ATTACK-SAMPLES): run Chainsaw/Hayabusa over real attack `.evtx` files, grouped by ATT&CK tactic
- [Security Datasets (OTRF)](https://github.com/OTRF/Security-Datasets): load recorded Kerberoasting/DCSync datasets into your SIEM and write queries against them
- [TryHackMe: Windows Logging for SOC](https://tryhackme.com/room/windowsloggingforsoc): guided 4688 vs Sysmon 1 practice on sample logs
- [Ultimate Windows Security event encyclopedia](https://www.ultimatewindowssecurity.com/securitylog/encyclopedia/): look up every event ID you meet and its fields
- Your lab: run the Windows VMs next to the kind cluster and ship Winlogbeat into the same SIEM you built in Phase 2, so Windows and Kubernetes events share one timeline

**Test yourself**
- [ ] Explain why Kerberoasting needs no admin rights and what a defender changes to make it fail (AES-only, long gMSA passwords)
- [ ] From memory, list the event IDs for logon, failed logon, process creation, service ticket, account created, and service installed
- [ ] Given a 4624 event, say what logon type 3 with NTLM from a workstation to a server suggests
- [ ] Write a detection that fires on DCSync from a host that isn't a domain controller, and trigger it with Atomic Red Team
- [ ] Explain why Sysmon 10 targeting `lsass.exe` is high signal, and which legitimate processes cause false positives

### Week 27: Cloud & Kubernetes Forensics (your specialty)

**Learn**
- [ ] CloudTrail record fields: `userIdentity` (type, `accessKeyId`, `arn`), `sourceIPAddress`, `userAgent`, `eventSource`, `errorCode`, and what management vs data events cover
- [ ] Access key types: `AKIA` (long-term) vs `ASIA` (temporary STS); following `AssumeRole` chains back to the original identity
- [ ] Typical stolen-key sequence: `GetCallerIdentity` → recon (`List*`/`Describe*`) → persistence (`CreateUser`, `CreateAccessKey`, `AttachUserPolicy`, new roles/trust policies) → access (`GetObject`, `ListBucket`)
- [ ] S3 evidence: CloudTrail data events vs S3 server access logs, and which one you need to prove which objects were read
- [ ] AWS acquisition order: isolate (restrictive security group, revoke sessions), snapshot EBS, capture memory, then export logs and snapshots to a separate forensic account
- [ ] Kubernetes audit log fields (`user`, `verb`, `objectRef`, `sourceIPs`, `responseStatus`) and the audit policy levels (`None`, `Metadata`, `Request`, `RequestResponse`)
- [ ] Kubernetes evidence: `kubectl debug` ephemeral containers, forensic container checkpointing, node snapshots, and why you capture before the pod is rescheduled
- [ ] Chain of custody for cloud evidence: hashes, who exported what and when, read-only storage (S3 Object Lock)
- [ ] Blast-radius scoping: what the key's policies allowed (could reach) vs what CloudTrail shows (actually touched)

**Tools**
- **CloudTrail Lake or Athena**: SQL over CloudTrail for timeline building
- **S3 server access logs**: object-level access evidence
- **VPC Flow Logs**: network evidence for exfiltration and C2 from instances
- **Kubernetes audit logs**: who did what against the API server
- **Invictus IR cloud forensics material (`invictus-aws`)**: scripted AWS evidence acquisition and analysis
- **AWS IR workshops**: guided AWS incident simulations
- **Stratus Red Team**: generate realistic AWS/Kubernetes attacker activity

**Practice**
- [AWS CIRT public workshops](https://aws.amazon.com/blogs/security/aws-cirt-announces-the-release-of-five-publicly-available-workshops/): do the unauthorized IAM credential use and S3 ransomware workshops end to end
- [flAWS 2 (Defender track)](http://flaws2.cloud/): investigate a breach from the supplied CloudTrail logs with Athena/jq
- [invictus-aws](https://github.com/invictus-ir/invictus-aws): run its acquisition and analysis against your own test account after a Stratus Red Team run
- [PwnedLabs](https://pwnedlabs.io/): do the cloud-focused DFIR labs that hand you CloudTrail/log exports
- [SANS Enterprise Cloud Forensics & IR poster](https://www.sans.org/posters/enterprise-cloud-forensics-incident-response-poster): keep the log-source and CLI evidence cheat sheet next to you
- Your lab: enable a `RequestResponse` audit policy on the kind cluster, run Peirates or a Stratus Kubernetes technique, then rebuild the attack from the audit log and checkpoint the compromised container

**Test yourself**
- [ ] From a CloudTrail export, find the first API call made by a leaked key and the IP and user agent it came from
- [ ] Explain why an `ASIA` key in an event doesn't tell you who the attacker is, and how you trace it back
- [ ] List from memory the IAM actions that mean persistence, and write the Athena query that finds them in a time window
- [ ] Prove which S3 objects were read, and explain what you lose if data events or server access logs were off
- [ ] Explain the order "snapshot first, then terminate" and what evidence is lost if you reverse it
- [ ] Write the scoping answer for a leaked key: could reach vs actually touched, in three sentences

### Week 28: Phishing Analysis & Threat Intelligence

**Learn**
- [ ] Reading headers bottom up: `Received` chain, `Return-Path`, `Reply-To`, `Message-ID`, and where spoofing shows
- [ ] SPF, DKIM, DMARC: what each one checks, and how to read `Authentication-Results`
- [ ] Common lures: credential-harvest pages, HTML smuggling, malicious Office/OneNote/ISO/LNK attachments, QR codes
- [ ] OAuth consent phishing and adversary-in-the-middle (AiTM) kits that steal session cookies and bypass MFA
- [ ] Safe handling: defanging IoCs, detonating only in a sandbox, never clicking from your own machine
- [ ] IoC types and the Pyramid of Pain: why hashes are weak and TTPs are strong
- [ ] Threat intel basics: STIX objects, feeds, sharing levels (TLP), and turning intel into SIEM lookups

**Tools**
- **Email header analysis (e.g. MXToolbox header analyzer)**: parse the delivery path and auth results
- **Any.Run / Hybrid Analysis**: detonate URLs and attachments, collect behaviour and IoCs
- **MISP or OpenCTI**: store, correlate and share IoCs

**Practice**
- [phishing_pot](https://github.com/rf-peixoto/phishing_pot): pick 5 real `.eml` samples and triage them end to end
- [MXToolbox Email Header Analyzer](https://mxtoolbox.com/EmailHeaders.aspx): check your header reading against the tool
- [Any.Run](https://app.any.run/) and [Hybrid Analysis](https://www.hybrid-analysis.com/): search public reports for your samples' hashes/URLs, or detonate them
- [MISP](https://www.misp-project.org/): run it in Docker, create an event per sample and export IoCs
- [Blue Team Labs Online](https://blueteamlabs.online/): do the free phishing analysis challenges
- Your lab: deploy MISP or OpenCTI with Helm on the kind cluster and feed its IoC export into your SIEM as a lookup

**Test yourself**
- [ ] From a raw `.eml`, find the real sending server and say whether SPF, DKIM and DMARC passed
- [ ] Explain why an AiTM phish beats MFA, and which sign-in log fields show the stolen session being reused
- [ ] Triage a sample in under 30 minutes: verdict, IoCs, affected users, and recommended action
- [ ] Turn 5 IoCs into SIEM lookups and show a hit on a test event
- [ ] Explain the Pyramid of Pain and give one IoC from each level

### Weeks 29–30: Host & Container Forensics

**Learn**
- [ ] Order of volatility: memory, processes and network state before disk
- [ ] `/proc/<pid>` evidence: `exe`, `cmdline`, `environ`, `maps`, `fd`; recovering a deleted binary from `/proc/<pid>/exe`
- [ ] Linux persistence: cron, systemd units, `~/.bashrc`, `authorized_keys`, `LD_PRELOAD`, new users in `/etc/passwd`
- [ ] Linux log and history sources: `auth.log`/`secure`, `journalctl`, shell history, `wtmp`/`btmp`/`lastlog`
- [ ] Container layers: overlayfs upper dir holds what changed; diffing a running container against its image
- [ ] Container escape signs: privileged pods, host mounts, `nsenter`, unexpected processes on the node
- [ ] Memory forensics with Volatility 3: Linux symbol tables from `dwarf2json`, and plugins like `linux.pslist`, `linux.bash`, `linux.sockstat`
- [ ] EBS snapshot workflow: snapshot, share to the forensic account, create a volume, attach read-only to a forensic instance, hash it
- [ ] Building a super timeline from file timestamps and logs, and the limits of timestamps (MACB, timestomping)

**Tools**
- **`/proc` analysis**: live triage of running processes
- **Container image diffing (`docker diff`, layer comparison)**: find files the attacker added or changed
- **Volatility 3 + `dwarf2json`**: Linux memory analysis
- **AWS EBS snapshot workflow**: disk acquisition in AWS
- **Plaso (`log2timeline`)**: build a timeline from a disk image
- **Velociraptor**: collect artifacts from live Linux/Windows hosts at scale

**Practice**
- [Volatility 3 docs](https://volatility3.readthedocs.io/): follow the Linux symbol tables section and build symbols for your lab kernel with [dwarf2json](https://github.com/volatilityfoundation/dwarf2json)
- [TryHackMe: Volatility Essentials](https://tryhackme.com/room/volatilityessentials): guided memory analysis case
- [CyberDefenders](https://cyberdefenders.org/blueteam-ctf-challenges/): filter for Endpoint Forensics and do 2 Linux disk/memory labs
- [Kubernetes forensic container checkpointing](https://kubernetes.io/blog/2022/12/05/forensic-container-checkpointing-alpha/): checkpoint a running container and analyse the archive offline
- Your lab: run a pod that drops a script and beacons out (Falco will alert from Week 11), then `kubectl debug`, checkpoint it, diff it against its image and recover the script

**Test yourself**
- [ ] Recover a binary that was deleted from disk but is still running, from memory
- [ ] List 6 Linux persistence locations from memory and the command to check each
- [ ] From a container, show every file added since the image was built
- [ ] Explain why Volatility needs a symbol table for the exact kernel and how you'd get one for an EKS node
- [ ] Walk through the EBS snapshot workflow out loud, including where you hash and why the evidence volume is read-only
- [ ] From a compromised Linux image, decode an obfuscated (base64) dropper and pull out the C2 address

### Week 31: Network Forensics

**Learn**
- [ ] TCP/IP basics for investigators: handshake, ports, TLS SNI and JA3/JA4 fingerprints when payloads are encrypted
- [ ] Beaconing: fixed intervals with jitter, small regular payloads, long-lived connections
- [ ] DNS tunnelling: long/high-entropy subdomains, many unique queries to one domain, TXT/NULL records
- [ ] Exfiltration patterns: large outbound flows, HTTP POSTs, uploads to cloud storage
- [ ] Zeek logs (`conn.log`, `dns.log`, `http.log`, `ssl.log`, `files.log`) and how `uid` links them
- [ ] Extracting files from a pcap (Wireshark Export Objects, Zeek file extraction) and hashing them
- [ ] Flow data vs full packet capture: what VPC Flow Logs and Hubble can and can't tell you

**Tools**
- **Wireshark / TShark**: packet-level analysis and filtering
- **Zeek**: turn pcaps into structured logs for hunting
- **Cilium Hubble**: pod-to-pod and egress flow visibility in Kubernetes

**Practice**
- [Malware-Traffic-Analysis.net training exercises](https://www.malware-traffic-analysis.net/training-exercises.html): do 3 exercises and compare your answers to the published ones
- [TryHackMe: Zeek Exercises](https://tryhackme.com/room/zeekbroexercises): anomalous DNS and phishing traffic with Zeek
- [Wireshark sample captures](https://wiki.wireshark.org/SampleCaptures): practise protocol filters on known-good traffic first
- [Zeek docs](https://docs.zeek.org/en/master/): read the log reference for `conn`, `dns`, `http`, `ssl`
- Your lab: generate beacon and DNS-tunnel traffic from a pod, watch it with [Hubble](https://docs.cilium.io/en/stable/observability/hubble/), and capture the same traffic as a pcap for Zeek

**Test yourself**
- [ ] From a pcap, find the beacon interval and the C2 host
- [ ] Find DNS-tunnelling queries in `dns.log` and explain what made them stand out
- [ ] Extract every file transferred over HTTP from a pcap and hash them
- [ ] Explain what you can still learn from TLS traffic you can't decrypt
- [ ] Write the TShark command that lists all DNS queries with their source IP, from memory

### Weeks 32–35: Practical Labs & Incident Command

**Learn**
- [ ] Investigation write-up format: scope, evidence, timeline, findings, IoCs, ATT&CK mapping
- [ ] Incident roles: commander, ops, comms, scribe, and why the commander doesn't do hands-on work
- [ ] Severity matrix Sev-0 to Sev-3: what triggers each and who gets paged
- [ ] Preserve evidence before remediating: snapshot first, then terminate
- [ ] Need-to-know communication: out-of-band channels when the attacker may read Slack or email
- [ ] Legal/disclosure clocks: GDPR 72 h to the authority (Art. 33), NIS2 24 h early warning and 72 h notification (Art. 23)
- [ ] NIST SP 800-61r3: how IR maps to the CSF 2.0 functions
- [ ] Blameless post-mortems: timeline, contributing factors, tracked actions with owners and dates

**Tools**
- **CyberDefenders / Blue Team Labs Online / LetsDefend**: investigation practice platforms
- **Timeline Explorer or a spreadsheet**: build and share the incident timeline
- **MITRE ATT&CK Navigator**: map the timeline to techniques for the report

**Practice**
- [CyberDefenders](https://cyberdefenders.org/blueteam-ctf-challenges/): filter for cloud and Kubernetes labs first, then a few Windows ones
- [Blue Team Labs Online](https://blueteamlabs.online/): investigations and incident response challenges
- [LetsDefend](https://letsdefend.io/): work alerts in the SOC simulator and write up each case
- [The DFIR Report](https://thedfirreport.com/): read one case a week and redraw its timeline from memory
- [PagerDuty Incident Response docs](https://response.pagerduty.com/) and [Google SRE: Managing Incidents](https://sre.google/sre-book/managing-incidents/): adopt the roles and handoffs for your mock incidents
- [Backdoors & Breaches](https://www.blackhillsinfosec.com/projects/backdoorsandbreaches/) or [CISA tabletop packages](https://www.cisa.gov/resources-tools/services/cisa-tabletop-exercise-packages): run a tabletop
- Your lab: run 2 mock incidents (a leaked AWS key and a cryptominer pod) with Stratus Red Team, play commander, and write the full IR report

**Test yourself**
- [ ] 8–10 investigations done, each with a written timeline
- [ ] Explain each incident role and what happens when the commander also starts debugging
- [ ] Classify 3 scenarios on your Sev-0 to Sev-3 matrix and justify each
- [ ] State the GDPR and NIS2 clocks from memory and when each starts
- [ ] Write an executive summary of one incident in 5 sentences, no jargon
- [ ] Produce a post-mortem with at least 3 actions, each with an owner and a due date

### Week 36: Capstone (buffer week)

**Learn**
- [ ] Sanitising a case study: remove account IDs, IPs, names and anything that identifies the employer
- [ ] Telling the story end to end: detection → triage → investigation → containment → lessons
- [ ] Exam format for your chosen cert: BTL1 (practical, 24 h) or CCD (practical, 48 h), and the note-taking setup you'll use

**Tools**
- **Your Phase 2 pipeline and Weeks 22–23 playbooks**: source material for the case study

**Practice**
- [BTL1](https://securityblue.team/certifications/blue-team-level-1) or [CCD](https://cyberdefenders.org/blue-team-training/courses/certified-cyberdefender-certification/): book the exam and do one timed practice lab first
- [SANS Hunt Evil poster](https://www.sans.org/posters/hunt-evil/): quick Windows refresher before a Windows-heavy exam
- Your lab: re-run one mock incident from scratch on a fresh kind cluster and record the detection firing for the case study

**Test yourself**
- [ ] Case study published, with detection, timeline and containment, and nothing sensitive in it
- [ ] Explain the case study in 5 minutes to someone non-technical
- [ ] Pass BTL1 or CCD

---

## After Week 36: Real Incidents

**Learn**
- [ ] How real IR teams run: on-call rotation, handoffs, retainer vs internal teams, working with legal and insurers
- [ ] Post-mortem writing: read real ones and copy the structure ([danluu/post-mortems](https://github.com/danluu/post-mortems), [Google SRE: Postmortem Culture](https://sre.google/sre-book/postmortem-culture/))
- [ ] Evidence handling under legal hold, and when to stop and call counsel
- [ ] The next certs: GCFR (FOR509) and GCFA, and how to pitch them to your employer

**Test yourself**
- [ ] On the security on-call or incident rotation at work
- [ ] At least 3 real incidents worked, with post-mortems you wrote
- [ ] Can tell 2 incident stories in STAR format: what you found, how, and what changed afterwards
- [ ] Can walk an interviewer through a cloud investigation from first alert to scoping answer without notes
- [ ] Applied to IR roles
