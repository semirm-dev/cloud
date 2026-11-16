## TLS and cert-manager

Never manage TLS certificates manually inside Traefik's local `acme.json` file if you run multiple replicas—use **`cert-manager`** so certificates live as native Kubernetes `Secret`s (`tls.crt` + `tls.key`) accessible across all nodes.

### Core `cert-manager` Resources

1. **`ClusterIssuer`:** Defines _who_ signs your certificates and _how_ domain ownership is proven:
   - **HTTP-01 Solver:** Let's Encrypt connects to `http://app.example.com/.well-known/acme-challenge/...` through your Ingress controller (requires public ports `80`/`443` reachable from the internet; cannot issue wildcard `*.example.com` certs).
   - **DNS-01 Solver:** `cert-manager` uses a Cloudflare/Route53 API token (or IAM Role) to create a temporary `_acme-challenge` `TXT` record—works for **wildcard certs (`*.example.com`)** and **private/internal clusters** behind a firewall.
   - **Self-Signed / Internal CA:** Issues trusted internal certificates without public internet access.
2. **`Certificate` (or Ingress Annotation):** Adding `cert-manager.io/cluster-issuer: letsencrypt-prod` to an `Ingress` or `Gateway` triggers `cert-manager` to automatically request, store, and renew the certificate 30 days before expiry.

### Minimal TLS + Ingress Wiring Hint

```yaml
# 1. ClusterIssuer (HTTP-01 example)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: admin@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik # or "cilium"
---
# 2. Ingress with automatic DNS (external-dns) + TLS (cert-manager)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik # or "cilium"
  tls:
    - hosts: ["app.example.com"]
      secretName: my-app-tls # Created & auto-renewed by cert-manager
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
