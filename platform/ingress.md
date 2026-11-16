# Ingress & Edge Routing Reference (Traefik / Cilium Gateway)

A production-oriented guide to Layer-7 HTTP(S) entry into the cluster: what Ingress/Gateway is, when to use **Traefik** vs **Cilium Ingress/Gateway**, how to install and harden the edge, and how apps expose hostnames.

Cross-links: [`cni.md`](cni.md) (VIP / CNI) · [`cert_manager.md`](cert_manager.md) (TLS) · [`external_dns.md`](external_dns.md) (DNS) · [`platform_overview.md`](platform_overview.md)

---

## 1. What Ingress Is

**Ingress** (and the newer **Gateway API**) is the L7 reverse-proxy layer that:

* Terminates TLS (using a Kubernetes `Secret` with `tls.crt` / `tls.key`)
* Routes by `Host` and path to in-cluster `Service`s
* Optionally applies middlewares (redirects, headers, rate limits, auth)

It is **not** the CNI and **not** DNS. The CNI delivers packets to the Ingress controller Pod; External-DNS publishes the hostname; cert-manager fills the TLS Secret.

| API | Resource | Typical controller |
| :--- | :--- | :--- |
| Networking v1 | `Ingress` + `IngressClass` | Traefik, Cilium Ingress, nginx |
| Gateway API | `Gateway` + `HTTPRoute` | Traefik, Cilium Gateway |

Prefer **Gateway API** for new platforms when the controller supports it; keep `Ingress` for existing apps and broad chart compatibility.

---

## 2. Where It Is Used

* **North-south traffic only:** Browser/API clients → public or internal hostname → app Service.
* **One (or few) shared LoadBalancer IPs** front many hostnames (name-based virtual hosting).
* Deployed **after** CNI (and usually after cert-manager CRDs) so the controller can get a VIP and TLS Secrets. See [`platform_overview.md`](platform_overview.md) steps 3 → 6 → 7.

**Default stack in these docs:** Cilium for networking/VIP + **Traefik** for L7. If you enable Cilium Ingress/Gateway instead, skip Traefik (do not run two default IngressClasses).

---

## 3. Traefik vs Cilium Ingress/Gateway

| Option | Pros | Cons / notes |
| :--- | :--- | :--- |
| **Traefik** | Mature middlewares, Dashboard, wide Ingress annotation ecosystem | Extra chart to operate; pair with Cilium for CNI/LB only |
| **Cilium Ingress/Gateway** | One stack (CNI + L7); eBPF datapath; Gateway API first-class | Team must standardize on Cilium CRDs/Gateway; less Traefik middleware ecosystem |

Pick **one** default `IngressClass` / Gateway controller per cluster.

---

## 4. How Traefik Is Installed & Configured

**Install (Helm)**

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --values traefik-values.yaml
```

Manage via ArgoCD after bootstrap. Service `type: LoadBalancer` receives a VIP from Cilium IPPool / cloud LB ([`cni.md`](cni.md)).

**Production Helm values hint (`traefik-values.yaml`)**

```yaml
deployment:
  kind: DaemonSet          # Or Deployment with replicas: 2+ and PDB
  replicas: 2              # Ignored for DaemonSet; set when using Deployment

service:
  type: LoadBalancer
  annotations:
    # Optional: pin a specific VIP from the pool
    # lbipam.cilium.io/ips: "192.168.1.240"

ports:
  web:
    port: 80
    expose:
      default: true
    redirectTo:
      port: websecure      # HTTP → HTTPS
  websecure:
    port: 443
    expose:
      default: true
    tls:
      enabled: true

ingressClass:
  enabled: true
  isDefaultClass: true

logs:
  general:
    level: INFO
  access:
    enabled: true

# Lock down the API/dashboard in production
api:
  dashboard: true
  insecure: false

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    memory: 512Mi

podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

Entrypoints: `web` (`:80`, redirect) and `websecure` (`:443`). Do not expose the Traefik API/dashboard on the public LoadBalancer without auth or an internal-only Service.

---

## 5. Application Ingress (DNS + TLS wired)

Developers only declare host + backend. External-DNS and cert-manager react to the same object:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    # Bare metal behind NAT — publish public WAN IP in DNS (see external-dns.md):
    # external-dns.alpha.kubernetes.io/target: "203.0.113.50"
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - app.example.com
      secretName: my-app-tls          # Created & renewed by cert-manager
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

**Gateway API sketch (Cilium or Traefik as controller)**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: my-app
spec:
  parentRefs:
    - name: shared-gateway
      namespace: traefik                 # or cilium-gateway namespace
  hostnames:
    - app.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-app
          port: 8080
```

TLS on Gateway API is usually attached on the `Gateway` listeners (certificateRefs) with cert-manager’s Gateway API integration—keep issuer details in [`cert_manager.md`](cert_manager.md).

---

## 6. Production Hardening Notes

* **One shared VIP** for many hostnames; reserve it in Cilium’s IP pool and document it for the network team.
* **Redirect HTTP→HTTPS** at the entrypoint (as above); do not rely on apps for that.
* **Middlewares** (Traefik): security headers, rate limits, and auth as needed—attach via Ingress annotations or `IngressRoute`/`Middleware` CRDs; avoid putting business logic only in the proxy.
* **Do not** store ACME state in Traefik’s local `acme.json` when running multiple replicas—use cert-manager Secrets ([`cert_manager.md`](cert_manager.md)).
* **NetworkPolicy:** allow traffic from the Ingress namespace to app namespaces only (see [`cni.md`](cni.md)).

---

## 7. Verification

```bash
kubectl -n traefik get deploy,ds,svc
kubectl get ingressclass
kubectl get ingress -A
kubectl get certificate -A                    # READY=True from cert-manager
dig +short app.example.com                    # Matches LB VIP or public WAN target
curl -I https://app.example.com               # Valid cert, expected status
```
