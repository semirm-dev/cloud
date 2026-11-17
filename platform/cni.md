# CNI Reference (Cilium / Calico / Canal)

A production-oriented guide to Kubernetes pod networking: what a CNI does, how to choose one, how to install and configure **Cilium** as the default, and how packets reach a Pod from the internet.

Cross-links: [`ingress.md`](ingress.md) (L7 edge) · [`external_dns.md`](external_dns.md) · [`cert_manager.md`](cert_manager.md) · [`platform_overview.md`](platform_overview.md)

---

## 1. What a CNI Is

Every Kubernetes cluster needs a **CNI (Container Network Interface)** plugin. The CNI:

* Assigns each Pod an IP from the cluster Pod CIDR (e.g. `10.42.0.0/16`)
* Creates the virtual Ethernet (`veth`) pair between the Pod network namespace and the host
* Programs routes (or overlays) so Pods on different nodes can communicate
* Optionally enforces `NetworkPolicy` (and L7 policies, depending on the plugin)

**Node-to-node** traffic uses the physical/VPC network. The CNI only owns **pod networking** and (with Cilium/MetalLB-style features) **Service LoadBalancer IPs** advertised into that network.

---

## 2. Where It Is Used

| Layer | Role |
| :--- | :--- |
| Cluster bootstrap | Must be running before CoreDNS, ArgoCD, or any workload Pod can get an IP |
| East-west traffic | Pod → Pod across nodes (overlay or native routing) |
| Security | `NetworkPolicy` / CiliumNetworkPolicy (identity-aware via eBPF) |
| North-south (optional) | Cilium L2 announcements / BGP + built-in Ingress/Gateway API |

Install the CNI **before** GitOps controllers and platform add-ons. See install order in [`platform_overview.md`](platform_overview.md).

---

## 3. CNI Comparison

| CNI | Data plane | Key features | When to choose |
| :--- | :--- | :--- | :--- |
| **Cilium** | Linux **eBPF** (can replace `iptables` / `kube-proxy`) | L3/L4/L7 policies, Hubble, BGP/L2 LB, Ingress/Gateway API | **Modern default** — bare metal and cloud |
| **Calico** | `iptables` / `nftables` / eBPF + **BGP (BIRD)** | Mature L3 BGP, strict NetworkPolicies | Enterprise fleets already on Calico BGP |
| **Canal** | Flannel (VXLAN) + Calico policies | Simple overlay + Calico firewall | Legacy RKE2/K3s defaults; prefer Cilium for new clusters |

### Overlay vs native routing

* **Overlay (VXLAN/Geneve):** Pod packets encapsulated in UDP. Works on any L2/L3 underlay; small encapsulation cost.
* **Native routing (BGP):** Pod CIDRs advertised into the physical/VPC routers. Zero encapsulation; needs router/cloud support.

### eBPF kube-proxy replacement (Cilium)

With `kubeProxyReplacement: true`, Cilium load-balances ClusterIP/NodePort/LoadBalancer in eBPF maps instead of growing `iptables` rule sets—important on large node counts.

---

## 4. How Cilium Is Installed & Configured

**Prerequisites**

* Cluster created with **no conflicting CNI** (e.g. RKE2 `cni: none`, or EKS/GKE with Cilium as the chosen CNI).
* For bare-metal LoadBalancer IPs: reserve an unused LAN pool (e.g. `192.168.1.240–192.168.1.250`) that your network team allows for ARP/BGP.

**Install (Helm — production starting point)**

```bash
helm repo add cilium https://helm.cilium.io
helm repo update

helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --version 1.16.4 \
  --values cilium-values.yaml
```

After bootstrap, prefer managing the same chart via ArgoCD (see [`platform_overview.md`](platform_overview.md) sync waves). Verify with `cilium status --wait`.

**Minimal Helm values (`cilium-values.yaml`) — bare metal with shared Ingress VIP**

```yaml
kubeProxyReplacement: true

l2announcements:
  enabled: true

ingressController:
  enabled: true          # Optional if you use Traefik instead — see ingress.md
  loadbalancerMode: shared
  default: true

gatewayAPI:
  enabled: true          # Prefer Gateway API for new apps when not using Traefik

hubble:
  enabled: true
  relay:
    enabled: true
  ui:
    enabled: true
```

**Required CRDs for floating LoadBalancer IPs (bare metal)**

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: lan-pool
spec:
  blocks:
    - start: "192.168.1.240"
      stop: "192.168.1.250"
---
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata:
  name: default
spec:
  loadBalancerIPs: true
  interfaces:
    - eth0   # Adjust to your node NIC name
  nodeSelector:
    matchLabels: {}
```

Cloud clusters usually skip L2 announcements and use the cloud provider LoadBalancer / NLB instead.

---

## 5. Request Path (Internet → Pod)

```text
1. USER BROWSER
   │  DNS: "Where is app.example.com?"
   ▼
2. DNS PROVIDER (Cloudflare / Route53)     ← external-dns maintains A/CNAME
   │  Returns public IP (e.g. 203.0.113.50) or internal VIP
   ▼
3. EDGE ROUTER / FIREWALL
   │  WAN → LAN DNAT 80/443, or BGP to cluster
   ▼
4. LOADBALANCER SERVICE IP
   │  Cilium IPPool / MetalLB / cloud LB (e.g. 192.168.1.240)
   ▼
5. INGRESS / GATEWAY CONTROLLER            ← Traefik or Cilium Ingress/Gateway
   │  TLS terminate (Secret from cert-manager)
   │  Host/path match → backend Service → Endpoints
   ▼
6. CNI (Cilium)
   │  Route/overlay to Pod IP; enforce NetworkPolicy via eBPF
   ▼
7. APPLICATION POD
      Container port (e.g. 8080)
```

---

## 6. Production NetworkPolicy Hint

Default-deny **ingress and egress** per namespace, then allow only what apps need (often generated by Kyverno — see [`security_pipeline.md`](security_pipeline.md)):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: my-app
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: my-app
spec:
  podSelector: {}
  policyTypes: ["Egress"]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-ingress
  namespace: my-app
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: traefik   # or cilium-ingress / kube-system
      ports:
        - protocol: TCP
          port: 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-metrics-from-monitoring
  namespace: my-app
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - protocol: TCP
          port: 9090          # Metrics on their own port, never behind the public route
```

Add an egress allow for each real dependency (database, external APIs). Serve `/metrics` on a separate port that only `monitoring` can reach; the Ingress/HTTPRoute points at the app port alone.

---

## 7. Verification

```bash
kubectl get nodes -o wide
cilium status --wait
kubectl get ciliumloadbalancerippool,ciliuml2announcementpolicy -A
kubectl get svc -A | grep LoadBalancer    # EXTERNAL-IP from your pool / cloud LB
kubectl -n kube-system get pods -l k8s-app=cilium
```

---

## Appendix — veth mental model (lab only)

```bash
sudo ip netns add pod1 && sudo ip netns add pod2
sudo ip link add veth1 type veth peer name veth2
sudo ip link set veth1 netns pod1 && sudo ip link set veth2 netns pod2
sudo ip netns exec pod1 ip addr add 10.0.0.1/24 dev veth1
sudo ip netns exec pod1 ip link set veth1 up
sudo ip netns exec pod2 ip addr add 10.0.0.2/24 dev veth2
sudo ip netns exec pod2 ip link set veth2 up
sudo ip netns exec pod1 ping -c 2 10.0.0.2
sudo ip netns del pod1 && sudo ip netns del pod2
```

This is what the CNI automates (namespaces, veths, IPs, routes) on every Pod create/delete.
