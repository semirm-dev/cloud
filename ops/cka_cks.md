# CKA → CKS Plan (10 weeks, toward Cloud DFIR)

## 1. Objective

- **Goal:** Pass **CKA**, then **CKS**, in 10 weeks: 1 setup week, 4 CKA weeks, 5 CKS weeks. ~17.5 hours/week.
- **Next role:** Senior DevSecOps / Cloud Security Engineer.
- **Long run:** Cloud DFIR. CKS is already half of it: audit logs, runtime detection and supply chain are where an investigation starts. This plan practises them as **evidence**, not only as exam answers.
- **Philosophy:** Terminal over video. Labs and simulators over lectures. Killer.sh is the finish line.

This is the canonical CKA/CKS plan for [blue.md](blue.md) (Phase 1, Weeks 6–12) and [platform_first.md](platform_first.md) (CKA in Stage 1, CKS in Stage 2). Week numbers below are this plan's own; map them like this:

| This plan | 17.5 h/week | [blue.md](blue.md) (24 h/week) | [platform_first.md](platform_first.md) |
| :-- | :-- | :-- | :-- |
| Week 0: setup | Week 0 | end of Week 5 | end of Week 4 |
| Weeks 1–3: CKA domains | Weeks 1–3 | Weeks 6–7 | Weeks 5–6 |
| Week 4: CKA exam | Week 4 | Week 8 | Week 7 |
| Week 5: CKS setup and hardening | Week 5 | Week 9 | Stage 2, ~month 9 |
| Weeks 6–7: system hardening, supply chain | Weeks 6–7 | Week 10 | Stage 2 |
| Week 8: runtime, audit, DFIR | Week 8 | Week 11 | Stage 2 |
| Week 9: CKS exam | Week 9 | Week 12 | Stage 2 |

On the blue.md pace Week 7 is short: SBOMs, Trivy and Cosign are already done in blue.md Week 5, so only ImagePolicyWebhook and manifest analysis are new.

## 2. Before you start: verify these yourself

The exams change. Confirm these against the source before Week 0 ends. This plan reflects them as best known, not as guaranteed:

- [ ] Current curriculum PDFs: <https://github.com/cncf/curriculum>, the domains and weights below come from there.
- [ ] Kubernetes version the exam runs: candidate handbook. Practise upgrades *to* that version.
- [ ] Exam format: recent exams have you `ssh` to a different host per task. If so, shell aliases and `.vimrc` edits do **not** follow you.
- [ ] Allowed documentation list (CKS allows a few tool docs besides kubernetes.io: Falco, Trivy, AppArmor, etc.).
- [ ] CKS requires a **passed CKA**. Each exam includes one free retake and 2 Killer.sh sessions (36 h each).

## 3. Resources (one per job, no more)

| Job | CKA | CKS |
| :-- | :-- | :-- |
| Course + labs (optional) | [KodeKloud CKA](https://kodekloud.com/learning-path/cka): only if killer.sh session 1 shows gaps. Labs and mocks, skip the lectures, one month | Kim Wüstkamp's CKS course (Udemy, linked from [killer.sh/cks](https://killer.sh/cks)): the security tooling is new ground, so this one is worth it |
| Quick drills | [Killercoda CKA](https://killercoda.com/killer-shell-cka) | [Killercoda CKS](https://killercoda.com/killer-shell-cks) |
| Final simulator | [Killer.sh CKA](https://killer.sh/cka) | [Killer.sh CKS](https://killer.sh/cks) |
| Docs navigation | kubernetes.io/docs | [Walid Shaari CKS repo](https://github.com/walidshaari/Certified-Kubernetes-Security-Specialist) |
| Break-and-fix (after the exam drills, not instead) | [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way), once | [Kubernetes Goat](https://madhuakula.com/kubernetes-goat/), [Bad Pods](https://github.com/BishopFox/badPods) |

Bundle: [Linux Foundation CKA + CKS](https://training.linuxfoundation.org/certification/certified-kubernetes-security-specialist/).

## 4. The lab: kubeadm for the exam, kind for the stack

`kind` cannot teach kubeadm upgrades, a broken kubelet or an etcd restore on a real node. Both clusters come from [lab.md](lab.md):

- **kubeadm VMs** (exam work): 3 VMs, 1 control plane, 2 workers, kubeadm, containerd. Everything that touches nodes or the API server runs here: upgrades, etcd, break-and-fix, audit policy, encryption at rest, ImagePolicyWebhook, AppArmor, gVisor, checkpointing.
  - Pin it to one minor version **below** the exam's, so Week 1 can upgrade it to the exam version.
  - Snapshot the VMs before every break-and-fix session.
- **kind `lab` cluster** (portfolio stack): disposable, rebuilt from Git. Argo CD, Kyverno, Falco + Falcosidekick and your own operator run here.

## 5. Schedule

```
Week 0: Setup ──► Weeks 1–3: CKA domains ──► Week 4: Killer.sh ×2 + CKA exam
                                                           │
Week 5–8: CKS domains (+ DFIR layer) ◄─────────────────────┘
       └──► Week 9: Killer.sh ×2 + CKS exam
```

Book both exam dates in Week 0: CKA at end of Week 4, CKS at end of Week 9. If Killer.sh session 1 goes badly, move the date one week. That is cheaper than burning the retake.

---

### Week 0: Setup (~10 h)

- [ ] Buy the bundle, confirm everything in Section 2.
- [ ] Build the kubeadm VMs (Section 4). Optional: Kubernetes the Hard Way once, to see what kubeadm automates.
- [ ] Create the public `security-lab/` repo with a README skeleton.
- [ ] Blog: polish 4–5 posts ahead, then drop to **1 post/week** until Week 9. Two a week at full polish does not fit beside 17.5 study hours and a job.

---

### Phase A: CKA (Weeks 1–4)

Domains: Troubleshooting 30% · Cluster Architecture, Installation & Configuration 25% · Services & Networking 20% · Workloads & Scheduling 15% · Storage 10%.

#### Week 1: Cluster architecture and lifecycle

- kubeadm install and upgrade (drain → kubeadm → kubelet/kubectl → uncordon): [Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
- Static pods and the control plane manifests: [Create static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)
- Highly-available control plane: know the topologies, not how to build one from memory.
- **Helm and Kustomize** to install cluster components: [Helm docs](https://helm.sh/docs/), [Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
- Extension interfaces: CNI, CSI, CRI, what each one plugs into.
- **CRDs and operators**: revision only, you write operators daily.
- **RBAC**: Role vs ClusterRole, bindings, `kubectl auth can-i --as`. It is in the CKA Cluster Architecture domain, not only CKS: [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

**Milestones**
- [ ] Upgrade the lab one minor version, control plane and both workers, in under 15 minutes.
- [ ] Install one component with Helm (with custom values) and one with a Kustomize overlay.
- [ ] Create a Role and RoleBinding for a ServiceAccount imperatively, then prove it with `kubectl auth can-i --as`.

#### Week 2: Networking and storage

- Services and CoreDNS: [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- Ingress **and Gateway API** (Gateway, HTTPRoute): [Gateway API](https://gateway-api.sigs.k8s.io/)
- NetworkPolicy: [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- StorageClass, PV, PVC, access modes, reclaim policy, dynamic provisioning: [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

**Milestones**
- [ ] From memory: a NetworkPolicy that isolates a namespace, allows ingress only from a `frontend` label and egress only to DNS (UDP and TCP 53).
- [ ] Route two paths to two Services with an HTTPRoute.

#### Week 3: Workloads, scheduling and troubleshooting

- Deployments: rollout, rollback, strategy. ConfigMaps and Secrets as env and volumes.
- Requests and limits, **HPA**: [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- Taints, tolerations, node affinity: [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- Troubleshooting (30% of the exam, the biggest block): kubelet down, broken API server manifest, wrong certificate path, CrashLoopBackOff, Service with no endpoints, `kubectl top` via metrics-server. [Troubleshooting Clusters](https://kubernetes.io/docs/tasks/debug/debug-cluster/)
- etcd snapshot and restore: **one drill**, so you can do it, not a whole week. [Operating etcd](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)

**Milestones**
- [ ] Break the lab five ways (kubelet config, API server flag, CNI removed, node NotReady, Service selector typo) and fix each in under 10 minutes.
- [ ] One etcd snapshot and restore to a new data directory.

#### Week 4: Simulate and pass

- Mon: Killer.sh session 1, untimed review of every wrong answer.
- Tue–Thu: drill only the weak domains.
- Fri: Killer.sh session 2, timed. Aim for 80%+ (the real pass mark is about 66%, and killer.sh is harder).
- Weekend: **CKA exam.**

---

### Phase B: CKS (Weeks 5–9)

Domains: Supply Chain Security 20% · Minimize Microservice Vulnerabilities 20% · Monitoring, Logging & Runtime Security 20% · Cluster Setup 15% · Cluster Hardening 15% · System Hardening 10%.

Five weeks, not four: three domains carry 20% each, and Week 8 adds the DFIR layer.

#### Week 5: Cluster setup and hardening

- Default-deny NetworkPolicies, and blocking the node metadata endpoint (`169.254.169.254`) with egress rules.
- CIS benchmark with [kube-bench](https://github.com/aquasecurity/kube-bench), and fixing what it reports. [kubescape](https://github.com/kubescape/kubescape) for the same checks against manifests (not on the exam).
- RBAC privilege paths: wildcard verbs, `escalate`/`bind`/`impersonate`, `create pods`, reading Secrets.
- Ingress with TLS.
- Verifying platform binaries against published `sha512` hashes.
- RBAC least privilege, ServiceAccounts, `automountServiceAccountToken: false`: [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/), [Service Accounts](https://kubernetes.io/docs/concepts/security/service-accounts-admin/)
- Restricting API server access (anonymous auth, authorization modes): [Controlling Access](https://kubernetes.io/docs/concepts/security/controlling-access/)
- Upgrades again: they are in CKS too.

**Milestones**
- [ ] kube-bench on the lab control plane: fix every FAIL you can justify, write down the ones you accept.
- [ ] Audit one of your own operators' generated `config/rbac/role.yaml`: is every verb used?

#### Week 6: System hardening and microservice vulnerabilities

- AppArmor and seccomp: [AppArmor](https://kubernetes.io/docs/tutorials/security/apparmor/), [Seccomp](https://kubernetes.io/docs/tutorials/security/seccomp/)
- Host attack surface: unneeded services, packages, users, open ports.
- Pod Security Admission (Privileged, Baseline, Restricted) and `securityContext`: [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
- **Secrets encryption at rest**: [Encrypting Secret Data at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- **Sandboxing with RuntimeClass and gVisor**: [RuntimeClass](https://kubernetes.io/docs/concepts/containers/runtime-class/), [gVisor](https://gvisor.dev/)
- **Pod-to-pod encryption** with Cilium or Istio: know how to enable it and how to verify it.

**Milestones**
- [ ] Enable encryption at rest and prove it: read the Secret straight from etcd with `etcdctl` and see ciphertext.
- [ ] Run one Pod under a gVisor RuntimeClass and one under a custom seccomp profile that blocks a syscall it then fails on.
- [ ] Run the [Bad Pods](https://github.com/BishopFox/badPods) `hostPID` + `privileged` pod, get root on the node, then show a Restricted PSA namespace rejecting it.

#### Week 7: Supply chain security

- Minimal base images, multi-stage builds, non-root users.
- **SBOMs**: generate one for an image (Trivy can).
- Image scanning: [Trivy](https://trivy.dev/)
- **Static analysis of manifests**: [kubesec](https://kubesec.io/), [KubeLinter](https://github.com/stackrox/kube-linter)
- **ImagePolicyWebhook** and allowed registries: [ImagePolicyWebhook](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#imagepolicywebhook)

Scanning finds vulnerable images; **admission is what blocks them**. Trivy alone never stops a deployment.

**Milestones**
- [ ] Configure ImagePolicyWebhook on the lab API server so an image from an unapproved registry is rejected.
- [ ] Scan your operator's image with Trivy and produce its SBOM. Commit both to `security-lab/`.
- Portfolio only, not exam, on the kind `lab` cluster: sign that image with [Cosign](https://docs.sigstore.dev/cosign/overview/) and enforce the signature with Kyverno `verifyImages`. Add Kyverno policies rejecting `hostPID`, `CAP_SYS_ADMIN` and root.

#### Week 8: Runtime security, audit logs, and the DFIR layer

Exam part:
- Audit policy: levels, stages, which resources at which level: [Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)
- Falco rules and outputs: [Falco rules](https://falco.org/docs/rules/)
- Immutable containers: `readOnlyRootFilesystem`, no shell, no package manager: [Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

DFIR part, same tools, investigator's question:
- **Audit logs as evidence:** ship them off the node (an attacker with node access deletes local files), keep them long enough to matter, and answer from them: who created this Pod, with which ServiceAccount, from which IP?
- **Live response without changing the evidence:** `kubectl debug` with an ephemeral container: [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
- **Forensic container checkpointing** through the kubelet checkpoint API, then inspect the archive: [Kubelet Checkpoint API](https://kubernetes.io/docs/reference/node/kubelet-checkpoint-api/). Beta and on by default since 1.30, but it needs containerd 2.x or CRI-O on the node, so check yours first.
- **Order of operations:** capture first, contain second (NetworkPolicy isolating the Pod, cordon the node), delete last. Deleting the Pod is deleting the evidence.

**Milestones**
- [ ] Falco rule that fires when a Pod executes a binary from `/tmp`.
- [ ] Audit policy from memory: `RequestResponse` on Secrets and RBAC objects, `Metadata` on everything else. Know why `RequestResponse` on Secrets logs their values.
- [ ] **Incident drill:** start a reverse shell in a lab Pod, then, as the responder: isolate the Pod, checkpoint it, and write a timeline from Falco alerts and audit log entries: entry point, commands, ServiceAccount used. Publish the write-up in `security-lab/`.

#### Week 9: Simulate and pass

- Mon: Killer.sh CKS session 1 (it is harder than the exam; do not panic at the score).
- Tue–Thu: weak domains only.
- Fri: Killer.sh session 2, timed. Aim for 80%+ (the real pass mark is about 67%).
- Weekend: **CKS exam.**

## 6. Weekly cadence (17.5 h)

Weekdays, 2.5 h:
- 0:00–0:25: curriculum item and its kubernetes.io page. Find it **through the docs search**, the way you will have to in the exam.
- 0:25–1:40: terminal drills (course labs, Killercoda, the lab).
- 1:40–2:20: break something on the lab, then fix it.
- 2:20–2:30: commit configs, rules, notes to `security-lab/`.

Weekend: 5 h on that week's milestones.

## 7. Exam tactics

1. **Read the task's connection line first** (the `ssh` host, or the context in older formats) and run it before anything else. Wrong host means zero points.
2. **Back up before editing a static pod manifest:**
   ```bash
   cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak
   ```
   If the API server does not come back, `crictl ps -a` and the kubelet logs show why.
3. **Imperative first, YAML second:** `kubectl create ... --dry-run=client -o yaml > x.yaml`. If you use shortcuts, keep them to what you can retype in ten seconds on a new host:
   ```bash
   export do="--dry-run=client -o yaml"
   ```
4. **Flag and move on.** Roughly 15–20 tasks in 2 hours. Anything over 8 minutes gets flagged and revisited.
5. **Weights are on the task.** Do the high-value ones first if you are behind.

## 8. After CKS: positioning and the DFIR path

`security-lab/` contents:
1. The lab's architecture: kubeadm VMs, the kind `lab` cluster with Argo CD, Falco, audit log shipping.
2. Falco rules with test output.
3. Admission policies: PSA, ImagePolicyWebhook config, and the Kyverno/Cosign extra.
4. **The Week 8 incident write-up.** This is the piece that separates you from other CKS holders when you apply for DFIR roles.

Positioning:
- Now: **Cloud Security Engineer · DevSecOps (CKA, CKS)**.
- Once the incident write-up is public: **Cloud Security · Kubernetes detection & forensics**.

Toward DFIR (after the next role, not during this sprint):
- Linux forensics fundamentals: filesystem timelines, memory and disk acquisition.
- Cloud audit trails: CloudTrail, EKS/GKE audit logs.
- Certification options to compare when you get there: SANS FOR509 (cloud forensics) or GIAC GCFA.
