# Master Roadmap: DevSecOps → DFIR, Cloud Specialization (4 Hours / Day)

This is the direct path from DevSecOps to DFIR (Digital Forensics & Incident Response), specializing in cloud, and it's self-contained. It favors operations and investigation over software development.

**If you follow `platform_first.md` first:** its Stages 1–2 cover Phase 1 here (Weeks 1–12), including CKA and CKS. Start at Phase 2.

---

**Candidate Background (from CV):**
- **11+ years** building systems: Go (low-latency, Aeron), Kubernetes Operators/CRDs, Helm, Argo CD app-of-apps, AWS/GCP, observability (Prometheus, Grafana, Loki, OTel Collector, Elasticsearch, Jaeger), Keycloak SSO, Sealed Secrets (MFC).
- **Security work you already have (lead with it):** the Cisco Secure Firewall Cloud Native config Operator, the AWS Shield protection Operator, tightening Kubernetes RBAC and AWS IAM, Keycloak SSO across Grafana/Argo CD/.NET services, GitOps secrets with Sealed Secrets at MFC.
- **Gaps for the switch:** no Terraform/IaC on the CV, no CI pipeline ownership (only Argo CD on the deploy side), no certifications, no Windows/AD security, no SIEM/detection work.
- **Windows exposure:** developer-side only (Windows Embedded at Agilent, Windows Server services at MFC).

**Target roles, in order:**
1. **Senior DevSecOps / Cloud Security Engineer**: what you get hired into first (end of Phase 1).
2. **DFIR (Digital Forensics & Incident Response), cloud specialization**: the destination. Incident Response = contain and stop the attack; Digital Forensics = collect and analyze evidence to work out what happened, how and why. Titles: Incident Responder, DFIR Analyst/Consultant, Cloud Incident Response Engineer, CSIRT member. Employers: IR consultancies (Mandiant, CrowdStrike Services, Unit 42, Kroll), cloud vendors (AWS CIRT, Wiz), internal CSIRTs.
3. Detection engineering is a **skill set** you learn on the way (logs, queries, attacker techniques), not a target role. It's too coding-heavy for what you want. Skip tier-1 SOC roles too: they would reset your seniority.

**Commitment:** 4 h/day, 6 days/week (~24 h/week), **36 weeks (~9 months)**. Each phase ends with a buffer week. If you fall behind, use it to catch up. Don't compress the next phase.

---

## Daily Study Framework
- **Hour 1: Threat model and theory.** What is the attacker doing, and which control or signal catches it? (MITRE ATT&CK Cloud/Containers/Enterprise, writeups, docs.)
- **Hours 2–3: Hands-on lab.** Terminal work only: build it, write the rule, write the policy.
- **Hour 4: Break your own work.** Attack or bypass what you built, then fix it. In Phase 1 this means misconfiguring on purpose and confirming the scanner or policy catches it.

Commit every lab to one public repo (`security-lab/`). It doubles as your portfolio. Publish a short write-up on `semirmahovkic.xyz/blog` at the end of each phase.

---

## Phase 1: DevSecOps Foundations (Weeks 1 – 12)
*Objective: close the IaC/CI gap, secure the delivery path you already know, earn CKA → CKS, and become hireable as a DevSecOps engineer.*

### Weeks 1–2: Terraform & IaC Security
- **Threat model:** public buckets, over-broad IAM, unencrypted state, drift.
- **Tooling:** Terraform / OpenTofu, `tflint`, `trivy config` (replaces tfsec), Checkov, OPA/Conftest, Terratest (Go).
- **Topics:** reusable module design; encrypted remote state treated as a privileged secret; drift detection with `terraform plan` in CI; policy-as-code against `terraform show -json`; module tests with Terratest.
- **Milestone:** a module-based AWS landing zone (VPC, EKS, IAM roles) with scanning that fails the PR on HIGH findings. State in S3 with native locking (`use_lockfile = true`, no DynamoDB).

### Week 3: CI/CD Pipeline Security
- **Threat model:** poisoned pipelines, `pull_request_target` abuse, script injection, compromised third-party actions, persistent self-hosted runners, long-lived cloud keys, AI coding agents hijacked by prompt injection hidden in issues, PRs or comments.
- **Tooling:** GitHub Actions, OIDC → AWS STS / GCP Workload Identity, StepSecurity Harden-Runner, OpenSSF Scorecard, zizmor (Actions linter), Dependabot / Renovate.
- **Topics:** OIDC trust policies scoped to repo + branch + environment; actions pinned by commit SHA; least-privilege `permissions:` per job; environment protection rules; why self-hosted runners must be ephemeral; treating AI agents in CI as untrusted identities (read-only tokens by default, no merge or deploy rights, no cloud credentials, human approval before their changes run).
- **Milestone:** a pipeline with **zero static cloud secrets**, actions pinned by SHA, least-privilege `permissions:` per job, and Scorecard ≥ 7.

### Week 4: Secrets Management & Argo CD Hardening
- **Threat model:** secrets in Git or CI settings, long-lived database passwords, the GitOps controller as a cluster-admin backdoor.
- **Tooling:** HashiCorp Vault (Kubernetes auth, dynamic DB credentials, leases, audit device), External Secrets Operator, TruffleHog / Gitleaks pre-commit and history scans.
- **Topics:** moving from Sealed Secrets (which you've run at MFC) to ESO + Vault, and why: Sealed Secrets has no central audit, rotation means re-sealing every secret, and the controller key is a single point of compromise; Argo CD AppProjects restricting repos, destinations and cluster-scoped resources; RBAC through Keycloak SSO groups; local admin disabled.
- **Milestone:** Argo CD deploys an app whose Postgres credentials are dynamic Vault secrets delivered through ESO. Nothing in Git is cleartext, and Gitleaks blocks a planted key.

### Week 5: Software Supply Chain
- **Threat model:** malicious dependencies, unsigned images, tampered artifacts, slopsquatting (attackers register package names that AI assistants hallucinate).
- **Tooling:** Syft (SBOM), Grype / Trivy, Cosign keyless signing, Semgrep (SAST), SLSA provenance (`slsa-github-generator`), OSV-Scanner, Socket or deps.dev for package reputation.
- **Topics:** verifying a new dependency is real and established before adding it (age, maintainers, downloads); lockfiles and Go checksum DB (`GOSUMDB`) so a dependency can't silently change.
- **Milestone:** a pipeline that builds a Go service, generates an SBOM, signs the image and attests its provenance with Cosign, and blocks on CRITICAL CVEs.

### Weeks 6–8: CKA (prerequisite for CKS)
- **CKS requires a passed, active CKA.** Your daily Kubernetes experience makes this mostly exam practice: kubeadm, etcd backup/restore, troubleshooting, networking. Use the killer.sh simulator.
- **Milestone:** **pass CKA by the end of Week 8.**

### Weeks 9–10: Cluster Hardening & Admission Control (CKS domains)
- **Threat model:** privileged pod breakouts, hostPath/hostPID, root containers, weak RBAC, anonymous API access.
- **Tooling:** Kyverno, Pod Security Standards, seccomp, AppArmor, `kube-bench`, `kubescape`, NetworkPolicies.
- **Milestone:** a hardened kind/kubeadm cluster with Kyverno policies that reject unsigned images (Cosign verification), `hostPID`, `CAP_SYS_ADMIN` and root users. It should pass `kube-bench`, with any remaining findings documented.

### Week 11: Runtime Detection & Audit Logging (CKS domain, bridge to Phase 2)
- **Threat model:** reverse shells, container escapes, unauthorized API actions.
- **Tooling:** Falco (`modern_ebpf` driver), Kubernetes API server audit policy, Falcosidekick.
- **Milestone:** custom Falco rules catch a simulated reverse shell and a write to `/etc`. The audit policy logs `RequestResponse` on Secrets and RBAC objects and `Metadata` on everything else.

### Week 12: CKS + Job Readiness (buffer week)
- **Pass CKS.**
- **Capstone write-up:** "Secure delivery path from commit to pod". Cover IaC scanning, OIDC, Vault/ESO, signed images, admission control and runtime detection, all in one diagram.
- **CV:** rewrite around the Cisco firewall/VPN Operator, AWS Shield Operator, RBAC/IAM tightening, Keycloak SSO and Sealed Secrets, plus the Phase 1 lab. **Start applying for DevSecOps roles from Week 10.**

---

## Phase 2: Detection & Investigation (Weeks 13 – 24)
*Objective: learn what attacks look like in logs and how to find them with queries. Queries are your main IR tool. Your telemetry background pays off here.*

### Weeks 13–14: Security Telemetry Pipeline
- **Threat model:** blind spots, unmonitored privilege escalation, quiet lateral movement.
- **Tooling:** Vector or Fluent Bit, Elastic Security or OpenSearch Security Analytics, AWS CloudTrail, VPC Flow Logs, Linux auth logs.
- **Key point:** this is the OTel/Loki pipeline you already know, pointed at security sources. Spend the effort on normalization (Elastic Common Schema), retention and cost, not on plumbing.
- **Topics:** security data can't be sampled the way traces are, so audit and security events go through unsampled and filters must never drop them; eBPF sources (Cilium Hubble flows, Tetragon process events); hot/warm/cold retention tiers, since audit logs often have compliance retention.
- **Milestone:** Kubernetes audit logs, Falco events, CloudTrail and auth logs arrive normalized to ECS and searchable in a single SIEM.

### Week 15: Cloud-Native Detection Services
- **Tooling:** Amazon GuardDuty (incl. EKS Protection & Runtime Monitoring), AWS Security Hub, GCP Security Command Center.
- **Key point:** in production, most cloud detections start from these managed services. Learn what they cover so your custom rules fill the gaps instead of duplicating them.
- **Milestone:** GuardDuty and Security Hub findings route into your SIEM, with a written map of what they cover versus what your custom rules cover.

### Weeks 16–17: Detection Query Languages & Logic
- **Tooling:** EQL and ES|QL (primary), Splunk SPL and Microsoft KQL (enough to read and translate).
- **Milestone:** 8 detections, including:
  1. A shell spawned in a container, followed by an outbound connection (EQL sequence).
  2. A burst of Kubernetes RBAC `403 Forbidden` responses from one identity.
  3. Creation of a cluster-admin ClusterRoleBinding.
  4. Unusual `sts:AssumeRole` chains / S3 enumeration.
  5. Security group opened to `0.0.0.0/0`.

### Week 18: Identity Attacks
- **Threat model:** IAM privilege escalation paths (`iam:PassRole`, `CreateAccessKey`, `UpdateAssumeRolePolicy`), token theft, OIDC/SSO abuse.
- **Tooling:** CloudTrail, Keycloak event logs (you already run it), Entra ID / Okta sign-in log schemas, PMapper or Cloudsplaining.
- **Milestone:** detections for 3 IAM privilege-escalation paths and impossible-travel / new-device sign-ins in Keycloak.

### Week 19: Sigma & ATT&CK (read and adapt, not build)
- **Tooling:** Sigma, `sigma-cli` / pySigma, MITRE ATT&CK Navigator.
- **Milestone:** adapt 5 community Sigma rules to your SIEM and map your detections to an ATT&CK coverage layer. No CI test harness: that's detection-engineering work you don't need.

### Weeks 20–21: Adversary Emulation & Investigation
- **Tooling:** Stratus Red Team (AWS, GCP, Kubernetes techniques), Atomic Red Team, Peirates (Kubernetes).
- **Milestone:** detonate 6 techniques in a sandbox account, then investigate each one *only from the logs*: which identity, which source IP, what was touched, when. Score each technique *detected / missed / noisy* and write a one-page timeline per technique.

### Weeks 22–23: IR Playbooks & Containment
- **Tooling:** AWS CLI, `kubectl`, AWS Security Incident Response Guide, NIST SP 800-61r3.
- **Topics:** the IR lifecycle (prepare, detect, contain, eradicate, recover, lessons learned); containment that preserves evidence (snapshot before terminate, isolate before delete).
- **Milestone:** written playbooks for 4 scenarios: leaked IAM access key, compromised EC2 instance, compromised pod, compromised Keycloak account. Each lists exact CLI commands to isolate (quarantine security group, cordon node, scale to zero), preserve (EBS snapshot, memory capture, log export), and revoke (deactivate keys, kill sessions). Run each one end to end in the lab.

### Week 24: Capstone + Cert (buffer week)
- **Write-up:** "Investigating attacks in AWS and Kubernetes". Show the pipeline, the emulation results, one full investigation timeline and one playbook run.
- **Cert:** AWS Certified Security – Specialty. Recommended: cloud is where your investigations will happen.

---

## Phase 3: DFIR (Weeks 25 – 36)
*Objective: the core of the roadmap. Investigate incidents end to end, with cloud as your specialty. Windows and endpoint forensics stay in because real incidents cross over (phished laptop → stolen cloud credentials → S3 exfiltration).*

### Weeks 25–26: Windows & Active Directory for Defenders
- **Threat model:** Kerberoasting, pass-the-hash, DCSync, malicious services, persistence via scheduled tasks.
- **Tooling:** a small AD lab (1 DC + 1 workstation), Sysmon (SwiftOnSecurity / Olaf Hartong config), Winlogbeat → your SIEM, Atomic Red Team.
- **Key events:** 4624/4625 (logon), 4688 (process creation), 4769 (Kerberos service ticket), 4720 (account created), Sysmon 1/3/10/11.
- **Milestone:** detections for Kerberoasting, DCSync and a new local admin, validated with Atomic Red Team.

### Week 27: Cloud & Kubernetes Forensics (your specialty)
- **Threat model:** stolen credentials used from attacker infrastructure, persistence via new IAM users/keys/roles, data exfiltration from S3, cryptominers in pods.
- **Tooling:** CloudTrail Lake or Athena, S3 server access logs, VPC Flow Logs, Kubernetes audit logs, Invictus IR cloud forensics material, AWS IR workshops.
- **Topics:** evidence acquisition in AWS (isolate, snapshot EBS, capture memory, export logs to a separate forensic account) and in Kubernetes (`kubectl debug`, checkpointing containers, node snapshots); chain of custody for cloud evidence; scoping the blast radius of a stolen key.
- **Milestone:** from a simulated leaked-key incident, build the full timeline from CloudTrail: first attacker API call, recon, persistence, and data accessed. Write the scoping answer: what the attacker could reach and what they actually touched.

### Week 28: Phishing Analysis & Threat Intelligence
- **Tooling:** email header analysis, URL/attachment sandboxing (Any.Run, Hybrid Analysis), MISP or OpenCTI basics.
- **Milestone:** triage 5 phishing samples end to end and turn their IoCs into SIEM lookups.

### Weeks 29–30: Host & Container Forensics
- **Tooling:** `/proc` analysis, container image diffing, Volatility 3 (Linux symbols built with `dwarf2json`; set aside a day just for this), AWS EBS snapshot workflow.
- **Milestone:** take an infected container/Linux image, recover the dropped script, decode the C2 address and rebuild the attacker's timeline.

### Week 31: Network Forensics
- **Tooling:** Wireshark/TShark, Zeek, Cilium Hubble.
- **Milestone:** in a multi-stage attack pcap, find the beacon interval, the exfiltrated files and the DNS-tunnelling queries, and document the IoCs.

### Weeks 32–35: Practical Labs & Incident Command
- **Platforms:** CyberDefenders, Blue Team Labs Online, LetsDefend. Complete 8–10 investigations, mostly cloud and container, plus a few Windows. Write a full timeline for each.
- **Incident command:**
  - Roles (commander, ops, comms, scribe) and a Sev-0 to Sev-3 severity matrix.
  - Security-specific rules: preserve evidence before remediating (snapshot first, then terminate), need-to-know communication, legal/disclosure clocks (GDPR 72 h, NIS2 24 h early warning).
- **Milestone:** run 2 mock incidents and write the IR reports: executive summary, root cause, ATT&CK timeline, containment, hardening, and a blameless post-mortem with tracked actions.

### Week 36: Capstone (buffer week)
- Publish a sanitized end-to-end case study showing detection (Phase 2 pipeline), investigation, timeline and containment (Weeks 22–23 playbooks).
- **Cert:** BTL1 or CCD. Both are Windows- and SOC-heavy, which is why they come after Weeks 25–28.

---

## After Week 36: Real Incidents

IR teams hire on real cases more than certs. In your DevSecOps / Cloud Security job, join the security on-call or incident rotation, volunteer for every incident and write the post-mortems. Apply for IR roles once you have a few real cases to talk about.

---

## Certifications (in order)

1. **CKA**: Week 8. Required before CKS, and it gets you past HR filters for DevSecOps roles.
2. **CKS**: Week 12. Proves cluster hardening, supply chain and runtime security.
3. **AWS Certified Security – Specialty**: Week 24. Cloud is where your investigations will happen.
4. **BTL1 / CCD**: Week 36. Practical investigation skills.
5. **GCFR** (SANS FOR509, cloud forensics) and **GCFA** (forensic analysis): the target IR certs. Expensive, so ideally employer-paid, but they are the ones IR hiring managers look for.
