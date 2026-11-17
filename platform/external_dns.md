# External-DNS Reference

A production-oriented guide covering how **External-DNS** automates DNS records from Kubernetes resources, safety settings, authentication, Helm configuration, and how it pairs with Ingress and cert-manager.

Cross-links: [`ingress.md`](ingress.md) · [`cert_manager.md`](cert_manager.md) · [`cni.md`](cni.md) · [`platform_overview.md`](platform_overview.md)

---

## 1. What External-DNS Does

**External-DNS** is a Kubernetes controller that synchronizes hostnames from Services, Ingresses, and Gateway API routes with external DNS providers (Cloudflare, AWS Route53, Google Cloud DNS, Azure DNS, Pi-hole, RFC2136/Bind9, etc.).

```text
[Ingress / HTTPRoute / LoadBalancer Service]
       │  Declares hostname + receives external IP / LB target
       ▼
[External-DNS Controller Pod]
       │  Authenticates via OIDC/IAM or API token
       ▼
[DNS Provider Zone]
       ├── Creates/updates A, AAAA, or CNAME
       └── Creates companion TXT ownership record
```

* **Replaces:** Manual DNS console clicks or one-off Terraform DNS changes per microservice deploy.
* **Does not:** Act as a DNS server—it only calls your provider’s API.
* **Does not:** Issue TLS certificates (cert-manager) or route HTTP (Ingress/Gateway).

---

## 2. Where It Is Used

* Any workload that should be reachable by a stable DNS name without a human updating the zone
* Shared platform layer: one (or few) External-DNS deployments per cluster/zone boundary
* Install **after** OpenBao/ESO (for API tokens) and alongside/after Ingress so targets have addresses — [`platform_overview.md`](platform_overview.md) steps 5–8

---

## 3. Core Concepts & Safety Guardrails

Automated DNS mistakes cause immediate outages. Always set these:

| Setting | Purpose | Production note |
| :--- | :--- | :--- |
| **`sources`** | Resources watched (`service`, `ingress`, `gateway-httproute`, …) | Enable only what you use |
| **`domainFilters`** | Zones External-DNS may touch (e.g. `example.com`) | **Critical** — blocks edits to unrelated zones in the same account |
| **`policy`** | `sync` (create/update/**delete**) vs `upsert-only` (no deletes) | Start `upsert-only`; switch to `sync` after validation |
| **`registry` + `txtOwnerId`** | TXT ownership stamped with a cluster ID | **Never** reuse `txtOwnerId` across clusters |

---

## 4. Authentication Patterns

* **Cloud (EKS / GKE / AKS):** Workload identity (**IRSA / Pod Identity**, GCP WI, Azure WI) on the External-DNS ServiceAccount. Scope IAM to the specific hosted zone ID. Prefer no static keys.
* **Bare metal / Cloudflare / RFC2136:** Least-privilege API token (e.g. Cloudflare `Zone:DNS:Edit` on one zone). Store in OpenBao/Vault → sync with **External Secrets Operator** into the `external-dns` namespace.

---

## 5. How Workloads Trigger DNS

1. **Ingress / HTTPRoute:** `host` / `hostnames` → A/CNAME to the Ingress/Gateway LoadBalancer address.
2. **Service `type: LoadBalancer`:** Annotation `external-dns.alpha.kubernetes.io/hostname: app.example.com` (optional `.../ttl: "60"`).
3. **NAT / split-horizon:** If the LB EXTERNAL-IP is a private LAN address (`192.168.1.240`) but public clients must hit the WAN IP, set:
   `external-dns.alpha.kubernetes.io/target: "203.0.113.50"`.
   For internal-only DNS, publish the private VIP to Pi-hole/Bind9 instead.

---

## 6. How It Is Installed & Configured

**Install (Helm — Cloudflare example)**

```bash
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update

helm upgrade --install external-dns external-dns/external-dns \
  --namespace external-dns \
  --create-namespace \
  --values external-dns-values.yaml
```

**Secret via ESO (pattern)**

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: cloudflare-api-token
  namespace: external-dns
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: openbao-backend
    kind: ClusterSecretStore
  target:
    name: cloudflare-api-token
  data:
    - secretKey: apiToken
      remoteRef:
        key: platform/cloudflare
        property: apiToken
```

**Helm values (`external-dns-values.yaml`)**

```yaml
provider:
  name: cloudflare

env:
  - name: CF_API_TOKEN
    valueFrom:
      secretKeyRef:
        name: cloudflare-api-token
        key: apiToken

sources:
  - service
  - ingress
  - gateway-httproute

domainFilters:
  - example.com

policy: upsert-only       # Flip to sync after soak
registry: txt
txtOwnerId: k8s-prod-01   # Unique per cluster
txtPrefix: external-dns-  # Optional clarity in the zone
interval: 1m

serviceAccount:
  create: true
  name: external-dns

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    memory: 128Mi
```

For AWS Route53, drop the Cloudflare env block and use IRSA annotations on `serviceAccount` plus `provider.name: aws` and zone filters—same safety flags apply.

---

## 7. Pairing with cert-manager

| Concern | Owner |
| :--- | :--- |
| `app.example.com` A/CNAME | External-DNS |
| HTTPS certificate for that name | cert-manager |
| `_acme-challenge` TXT (DNS-01) | cert-manager (not External-DNS) |
| Ownership TXT (`txtOwnerId`) | External-DNS |

HTTP-01 needs the A/CNAME reachable on :80; create DNS before or with the Ingress that triggers the Certificate ([`cert_manager.md`](cert_manager.md)).

---

## 8. Operational & Troubleshooting Notes

* Logs show exact plan: `CREATE` / `UPDATE` / `DELETE` and auth/rate-limit errors:
  `kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns`
* Keep `interval` around `1m`; sub-10s loops burn Cloudflare/Route53 quotas.
* If records do not appear: check `domainFilters`, Ingress `host`, LB EXTERNAL-IP/`target` annotation, and token scope.

---

## 9. Verification

```bash
kubectl -n external-dns get deploy,pods,secrets
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=100
dig +short app.example.com @1.1.1.1
dig TXT app.example.com @1.1.1.1          # Ownership TXT present for sync registry
```
