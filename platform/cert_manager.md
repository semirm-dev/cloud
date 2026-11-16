# TLS & cert-manager Reference

A production-oriented guide to automated certificate issuance and renewal in Kubernetes: what **cert-manager** is, how it pairs with Ingress/Gateway and External-DNS, how to install it, and production `ClusterIssuer` / `Certificate` patterns.

Cross-links: [`ingress.md`](ingress.md) · [`external_dns.md`](external_dns.md) · [`cni.md`](cni.md) · [`platform_overview.md`](platform_overview.md)

---

## 1. What cert-manager Is

**cert-manager** is a Kubernetes controller that issues and renews TLS certificates and stores them as native Secrets (`tls.crt` + `tls.key`). Controllers like Traefik or Cilium Gateway mount those Secrets for HTTPS.

It replaces:

* Manual cert uploads
* Traefik/local `acme.json` when you run **multiple replicas** (local ACME state does not share cleanly across Pods)

It does **not** create DNS A/CNAME records (that is External-DNS) and does **not** route HTTP (that is Ingress/Gateway).

---

## 2. Where It Is Used

* Every public (and many internal) hostname that needs HTTPS
* Wildcard certs (`*.example.com`) via DNS-01
* Internal mTLS / private PKI via self-signed or internal CA issuers
* Installed **after** secrets plumbing (OpenBao/ESO) so DNS API tokens are not baked into Git; **before** or with Ingress so TLS Secrets exist when routes go live — see [`platform_overview.md`](platform_overview.md) steps 5–7

Renewal is automatic (typically ~30 days before expiry for Let’s Encrypt).

---

## 3. Core Resources

| Resource | Scope | Role |
| :--- | :--- | :--- |
| **`ClusterIssuer` / `Issuer`** | Cluster / namespace | Who signs certs and how ownership is proven (ACME, CA, self-signed, Vault…) |
| **`Certificate`** | Namespace | Declares DNS names + which issuer + target Secret name |
| **Ingress / Gateway annotation or cert-manager Gateway shim** | App | Shortcut: annotation on Ingress creates a Certificate for you |

### Challenge types (ACME / Let’s Encrypt)

| Solver | How ownership is proven | Wildcard | Needs public :80/:443 |
| :--- | :--- | :--- | :--- |
| **HTTP-01** | LE fetches `http://<host>/.well-known/acme-challenge/...` via Ingress | No | Yes |
| **DNS-01** | Temporary `_acme-challenge` TXT via Cloudflare/Route53/etc. | **Yes** | No — works for private/internal clusters |
| **Self-signed / CA** | Your private CA | Yes (your policy) | No |

---

## 4. How It Is Installed & Configured

**Install (Helm)**

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.2 \
  --set crds.enabled=true \
  --set replicaCount=2 \
  --set webhook.replicaCount=2 \
  --set cainjector.replicaCount=2 \
  --set prometheus.enabled=true
```

Prefer ArgoCD for ongoing sync. Keep `replicaCount≥2` in production (leader election is built in).

**Secrets:** Cloudflare/Route53 credentials should live in OpenBao/Vault and sync via External Secrets Operator into `cert-manager` (or a dedicated namespace)—never commit API tokens.

---

## 5. Production Issuers

### HTTP-01 ClusterIssuer (public apps via Traefik)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: platform@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik   # or cilium
```

Use Let’s Encrypt **staging** (`acme-staging-v02...`) while testing to avoid production rate limits; switch the issuer name when ready.

### DNS-01 ClusterIssuer (wildcards / private clusters — Cloudflare)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
type: Opaque
stringData:
  api-token: "REPLACE_VIA_ESO"        # Zone:DNS:Edit on example.com only
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns
spec:
  acme:
    email: platform@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-dns-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
```

### Explicit Certificate (wildcard example)

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-example-com
  namespace: traefik
spec:
  secretName: wildcard-example-com-tls
  issuerRef:
    name: letsencrypt-dns
    kind: ClusterIssuer
  dnsNames:
    - "example.com"
    - "*.example.com"
```

### Ingress annotation shortcut (per-app cert)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
    - hosts: ["app.example.com"]
      secretName: my-app-tls
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 8080
```

Full routing/HA details live in [`ingress.md`](ingress.md). For HTTP-01, the hostname must resolve and reach the cluster on port 80—External-DNS usually creates that record ([`external_dns.md`](external_dns.md)).

---

## 6. Operational Notes

* **HTTP-01 + External-DNS:** DNS A/CNAME must exist (or propagate) before the challenge succeeds; order platform bring-up so DNS and Ingress are healthy first.
* **DNS-01:** cert-manager writes `_acme-challenge` TXT records itself—do not confuse these with External-DNS ownership TXT records (`txtOwnerId`).
* **Rate limits:** Prefer staging issuers in non-prod; avoid deleting/recreating Certificates in a loop against prod ACME.
* **Never** share Let’s Encrypt account keys or DNS tokens across unrelated environments without intent.

---

## 7. Verification

```bash
kubectl get pods -n cert-manager
kubectl get clusterissuer
kubectl get certificate,certificaterequest,order,challenge -A
kubectl describe certificate -n my-app my-app-tls   # Events show challenge progress
kubectl get secret my-app-tls -n my-app -o yaml     # tls.crt / tls.key present
curl -vI https://app.example.com                    # Trusted chain, matching CN/SAN
```
