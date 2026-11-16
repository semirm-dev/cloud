# CNI, Ingress & TLS Reference (Cilium / Calico / Canal + Traefik + cert-manager)

A concise operational guide covering how **CNIs** connect pods, how **Traefik** or **Cilium** exposes HTTP/HTTPS traffic, and how **`cert-manager`** automates TLS certificates—without needing massive configuration dumps.

---

## 1. How the Three Layers Fit Together

```text
User Browser (https://app.example.com)
       │
       ▼  1. External Entry IP (Cloud LB or Bare-Metal L2/BGP Floating IP)
[Layer 7 Ingress / Gateway: Traefik or Cilium Envoy]
       │  ├── Terminates HTTPS using TLS Secret created by cert-manager
       │  └── Routes by Hostname / Path (Ingress or HTTPRoute)
       ▼
[Cluster Pod Network (CNI): Cilium, Calico, or Canal]
       │  └── Routes packets across nodes to target Pod CIDR (10.42.x.x)
       ▼
Target Application Pod
```

---

## 2. CNI Comparison: Cilium vs. Calico vs. Canal

Every Kubernetes cluster needs a **CNI (Container Network Interface)** to assign Pod IPs (`10.42.0.0/16`), wire pod virtual Ethernet (`veth`) interfaces, and route packets between nodes.

| CNI | Data Plane Engine | Key Features | When to Choose It |
| :--- | :--- | :--- | :--- |
| **Cilium** | **Linux eBPF** (bypasses `iptables` & `kube-proxy`) | L3/L4/L7 NetworkPolicies, Hubble flow UI, built-in BGP/L2 LoadBalancer, built-in Ingress/Gateway API | **Modern default** for both bare-metal and cloud clusters; highest performance and best packet visibility |
| **Calico** | `iptables` / `nftables` / eBPF + **BGP (BIRD)** | Mature L3 BGP routing, strict NetworkPolicies, very predictable | Traditional enterprise setups or teams already standardized on Calico BGP |
| **Canal** | **Flannel** (VXLAN overlay) + **Calico** (NetworkPolicies) | Simple VXLAN pod networking + Calico firewall rules | Lightweight legacy clusters (default in older RKE2/K3s installs); largely superseded by Cilium |

### Key CNI Notes to Remember
* **Overlay (VXLAN/Geneve) vs. Native Routing (BGP):** Overlay encapsulates pod packets inside UDP packets so any switch works out of the box; Native Routing advertises Pod CIDRs directly into your physical/VPC routers for zero encapsulation overhead.
* **eBPF `kube-proxy` Replacement (Cilium):** Disabling `kube-proxy` lets Cilium handle Kubernetes `Service` ClusterIP/NodePort load balancing directly in kernel eBPF maps—eliminating `iptables` rule bloat on large clusters.

---

## 3. Ingress & TLS Architecture Options

You have two clean production patterns for exposing HTTPS services:

### Pattern A: Modular Stack — CNI (Calico/Cilium) + Traefik + `cert-manager`
Best when you want a dedicated, easy-to-debug L7 reverse proxy with rich middlewares (rate limiting, basic auth, forward auth, path stripping).

* **How Traefik is configured:**
  * Deployed via Helm (or RKE2's built-in `rke2-traefik` chart) as a `Deployment` or `DaemonSet`.
  * Its Kubernetes `Service` is set to `type: LoadBalancer` (receiving a cloud LB IP or bare-metal MetalLB/Cilium floating IP).
  * Entrypoints listen on `web` (`:80`, typically configured to redirect to HTTPS) and `websecure` (`:443`).
* **Minimal Helm Values Hint (`traefik`):**
  ```yaml
  deployment:
    kind: DaemonSet            # Runs on every node for high availability
  service:
    type: LoadBalancer
  ports:
    web:
      redirectTo:
        port: websecure        # Automatic HTTP -> HTTPS redirect
  ```

### Pattern B: Unified eBPF Stack — Cilium (CNI + LB + Ingress/Gateway) + `cert-manager`
Best on bare metal or minimalist clusters where you want one tool to handle CNI, floating L2/BGP IPs, and L7 Ingress/Gateway API without installing MetalLB or Traefik separately.

* **How Cilium Ingress/Gateway is configured:**
  * Enable `l2announcements` (or `bgpControlPlane`), `ingressController.enabled=true` (or `gatewayAPI.enabled=true`), and define a `CiliumLoadBalancerIPPool` for your reserved LAN IPs.
* **Minimal Helm Values Hint (`cilium`):**
  ```yaml
  kubeProxyReplacement: true
  l2announcements:
    enabled: true
  ingressController:
    enabled: true
    loadbalancerMode: shared   # All Ingresses share one LoadBalancer IP
    default: true
  gatewayAPI:
    enabled: true
  ```

---

## 4. Automating TLS with `cert-manager`

Never manage TLS certificates manually inside Traefik's local `acme.json` file if you run multiple replicas—use **`cert-manager`** so certificates live as native Kubernetes `Secret`s (`tls.crt` + `tls.key`) accessible across all nodes.

### Core `cert-manager` Resources
1. **`ClusterIssuer`:** Defines *who* signs your certificates and *how* domain ownership is proven:
   * **HTTP-01 Solver:** Let's Encrypt connects to `http://app.example.com/.well-known/acme-challenge/...` through your Ingress controller (requires public ports `80`/`443` reachable from the internet; cannot issue wildcard `*.example.com` certs).
   * **DNS-01 Solver:** `cert-manager` uses a Cloudflare/Route53 API token (or IAM Role) to create a temporary `_acme-challenge` `TXT` record—works for **wildcard certs (`*.example.com`)** and **private/internal clusters** behind a firewall.
   * **Self-Signed / Internal CA:** Issues trusted internal certificates without public internet access.
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
            ingressClassName: traefik   # or "cilium"
---
# 2. Ingress with automatic DNS (external-dns) + TLS (cert-manager)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik             # or "cilium"
  tls:
    - hosts: ["app.example.com"]
      secretName: my-app-tls            # Created & auto-renewed by cert-manager
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

---

## 5. Quick Debugging Checklist

| Symptom | Where to Look | Command |
| :--- | :--- | :--- |
| **Service stuck in `<pending>` External-IP** | No LoadBalancer controller (MetalLB / Cilium IPPool / Cloud CCM) | `kubectl get svc -A` & check Cilium/MetalLB IP pool |
| **Browser shows "Kubernetes Ingress Controller Fake Certificate"** | `cert-manager` hasn't issued the `Secret` yet | `kubectl describe certificate,certificaterequest,order,challenge -A` |
| **`404 Not Found` from Traefik/Cilium** | Mismatched `ingressClassName`, `Host` header, or backend `Service` port | `kubectl get ingress,httproute -A` & check Ingress pod logs |
| **Pods on Node A cannot reach Pods on Node B** | CNI VXLAN/Geneve UDP port (`8472`/`6081`) or BGP blocked by firewall | `cilium status` / `cilium connectivity test` |