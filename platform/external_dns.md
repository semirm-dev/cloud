# External-DNS Concepts & Configuration Reference

A concise architectural and operational guide covering how **External-DNS** automates DNS records from Kubernetes resources, key safety settings, authentication patterns, and common deployment notes.

## 1. What External-DNS Does

**External-DNS** is a Kubernetes controller that synchronizes exposed Kubernetes Services, Ingresses, and Gateway API routes with external DNS providers (Cloudflare, AWS Route53, Google Cloud DNS, Azure DNS, Pi-hole, RFC2136/Bind9, etc.).

```
[Ingress / HTTPRoute / LoadBalancer Service]
       │  (Declares hostname + receives external IP/LB target)
       ▼
[External-DNS Controller Pod]
       │  (Authenticates via OIDC/IAM Role or API Token)
       ▼
[DNS Provider Zone (Route53 / Cloudflare / etc.)]
       ├── Creates/Updates A, AAAA, or CNAME record
       └── Creates companion TXT ownership record
```

* **What it replaces:** Manual clicking in DNS dashboards or custom Terraform DNS modules every time a developer deploys or deletes a microservice.
* **What it does NOT do:** It does **not** act as a DNS server itself—it is purely a control-plane reconciler that calls your DNS provider's API.

## 2. Core Concepts & Safety Guardrails

Because automated DNS changes can cause immediate production outages if misconfigured, always configure these four core settings:

| Setting | Purpose | Production Note |
| :--- | :--- | :--- |
| **`sources`** | Which Kubernetes resources External-DNS watches (`service`, `ingress`, `gateway-httproute`, `crd`). | Only enable the resource types you actually use to reduce API load and unintended records. |
| **`domainFilters`** | Restricts which DNS zones External-DNS is allowed to touch (e.g., `["example.com"]`). | **Critical guardrail:** Prevents the controller from accidentally modifying unrelated domains under the same account. |
| **`policy`** | Controls record lifecycle: `sync` (creates, updates, and **deletes**) vs. `upsert-only` (creates and updates, **never deletes**). | Start with `upsert-only` during initial rollouts or migrations so existing records cannot be wiped; switch to `sync` once verified. |
| **`registry` & `txtOwnerId`** | Uses companion `TXT` records stamped with a unique cluster ID (e.g., `eks-prod-01`) to track ownership. | **Never share a `txtOwnerId` across two clusters.** Ownership tracking ensures External-DNS never overwrites manually created DNS records or records owned by another cluster. |

## 3. Authentication Patterns (Bare Metal vs. Cloud)

* **Cloud Providers (AWS EKS / GCP GKE / Azure AKS):**
  * Use workload identity federation (**AWS IRSA / Pod Identity**, **GCP Workload Identity**, **Azure Workload Identity**) attached to the `external-dns` `ServiceAccount`.
  * Scope IAM permissions strictly to the specific Hosted Zone ID (`route53:ChangeResourceRecordSets` on `hostedzone/Z123...`). Avoid static access keys.
* **Bare Metal / External Providers (Cloudflare, DigitalOcean, RFC2136):**
  * Create a least-privilege API token scoped to `Zone:DNS:Edit` for the target domain only.
  * Store the token in an external vault (**OpenBao / HashiCorp Vault**) and sync it into Kubernetes via **External Secrets Operator (ESO)** rather than committing secrets to Git.

## 4. How Workloads Trigger DNS Creation

Once External-DNS is running, developers do not need to touch DNS configurations directly:

1. **Via `Ingress` or `HTTPRoute` (Automatic):**
   * Declaring a `host` / `hostnames` field automatically creates an `A` or `CNAME` record pointing to the external IP or hostname assigned to your Ingress/Gateway controller.
2. **Via `Service` of `type: LoadBalancer` (Annotation-Driven):**
   * Add `external-dns.alpha.kubernetes.io/hostname: app.example.com` (and optionally `external-dns.alpha.kubernetes.io/ttl: "60"`) to the Service metadata.
3. **Bare-Metal / Split-Horizon Note:**
   * If your cluster sits behind a home or corporate NAT router, your Ingress `LoadBalancer` service may hold a private LAN IP (`192.168.1.240`).
   * For **internal-only** access, External-DNS can publish that private IP directly (or update an internal DNS server like Pi-hole/Bind9).
   * For **public internet** access behind NAT, override the target IP using the annotation `external-dns.alpha.kubernetes.io/target: 203.0.113.50` (your public WAN IP) so public DNS resolves to your edge router rather than a private LAN IP.

## 5. Minimal Configuration Skeleton (Helm Values)

```yaml
provider:
  name: cloudflare # or aws, google, azure, rfc2136

sources:
  - service
  - ingress
  - gateway-httproute

domainFilters:
  - example.com

policy: upsert-only      # Switch to "sync" once tested
registry: txt
txtOwnerId: k8s-prod-01  # Must be unique per Kubernetes cluster
interval: 1m             # Reconciliation loop frequency
```

## 6. Operational & Troubleshooting Notes

* **Check Logs First:** External-DNS logs exact API operations (`Desired change: CREATE ...`, `UPDATE ...`, `DELETE ...`) and permission/rate-limit errors (`kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns`).
* **Watch Provider Rate Limits:** Avoid setting `interval` too low (e.g., `5s`) on large clusters—`1m` is standard and prevents throttling from Cloudflare or Route53 APIs.
* **How It Pairs with `cert-manager`:** External-DNS creates the `A`/`CNAME` record for `app.example.com` so HTTP-01 challenges can reach your cluster, while `cert-manager` independently handles TLS certificate issuance (and creates its own temporary `_acme-challenge` `TXT` records when using DNS-01).