# Bare-Metal Kubernetes Networking, Ingress, TLS & SRE Lab Reference

A practical architecture and operations guide covering how traffic enters a bare-metal Kubernetes cluster (RKE2), how CNIs connect pods and nodes, how TLS/DNS automation works, and a 4-week hands-on lab plan to build DevOps/SRE/Platform Engineering skills.

---

## 1. End-to-End Traffic Flow on Bare Metal

```text
User Browser (grafana.example.com)
       │
       ▼  1. DNS Lookup (automated by external-dns)
Public WAN IP (203.0.113.50)
       │
       ▼  2. Edge Router Port-Forward (TCP 80 & 443)
Floating LoadBalancer VIP (192.168.1.240)  ◄── Managed by MetalLB or Cilium (L2 ARP / BGP)
       │
       ▼  3. Layer 7 Ingress / Gateway (TLS Termination + Host/Path Routing)
Ingress Controller (Traefik / Envoy / Cilium) ◄── Reads TLS Secrets from cert-manager
       │
       ▼  4. Cluster Internal CNI Fabric (10.42.x.x Pod Network)
Target Application Pod (10.42.2.15)
```

### Core Networking Concepts
* **Static Node IPs vs. Floating LoadBalancer IPs:**
  * **Node IPs (`192.168.1.11`, `.12`, `.13`):** Fixed physical/VM interface IPs assigned by your network admin or DHCP reservations. Nodes use these directly for cluster control-plane traffic (`6443`, `2379-2380`, `9345`) and CNI tunnels/BGP.
  * **Floating LoadBalancer IPs (`192.168.1.240`–`192.168.1.250`):** A reserved pool of unused IPs outside your router's DHCP range. A bare-metal controller (**MetalLB** or **Cilium**) claims an IP and announces it on the LAN via **L2 ARP** or **BGP**. If the active node fails, another node immediately claims the floating IP.
* **What to Request from Your Network Admin:**
  1. Static IPs (or DHCP reservations) for each cluster node.
  2. A small reserved block of unused IPs (e.g., 5–10 IPs) excluded from DHCP for floating `LoadBalancer` services.
  3. Gateway IP, subnet mask, and DNS servers.
  4. Firewall/NAT rule forwarding external TCP `80` and `443` to the first floating IP (or BGP peer IP + ASN if using BGP).

---

## 2. How CNI, Node-to-Node, and DNS Work Together

* **Node-to-Node Communication (Physical Layer):**
  * Nodes talk directly over your physical LAN switch using their static IPs (`192.168.1.x`). No CNI is required for node-to-node connectivity.
* **Pod-to-Pod Communication (CNI Layer — Calico / Cilium / Flannel):**
  * Physical switches do not understand virtual Kubernetes Pod CIDRs (`10.42.0.0/16`).
  * A CNI consists of a **CNI CLI binary** (`/opt/cni/bin/...`) that wires each pod's virtual Ethernet cable (`veth` pair) at creation time, and a **CNI DaemonSet agent** (`cilium-agent`, `calico-node`) running on every node.
  * The CNI agent assigns each node a Pod subnet (`10.42.1.0/24`, `10.42.2.0/24`) and programs every node's **Linux kernel routing table** (`ip route` via Netlink) or **eBPF maps** (`cilium_ipcache`) so pod-to-pod packets seamlessly encapsulate (VXLAN/Geneve) or route (BGP) across your physical node-to-node network.
* **DNS Automation (`external-dns`):**
  * Watches Kubernetes `Ingress`, `HTTPRoute`, or `Service` resources and automatically creates/updates/deletes `A` records at your DNS provider (e.g., Cloudflare, Route53).
  * Every application hostname (`grafana.example.com`, `api.example.com`, `auth.example.com`) points to the **exact same cluster entry IP**, and the Layer 7 Ingress controller splits traffic internally using TLS SNI and the HTTP `Host:` header.

---

## 3. Ingress Controllers & Service Mesh Comparison

| Tool | Primary Role | Engine | Replaces MetalLB? | Operational Overhead | Best Fit |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **NGINX Ingress** | Legacy L7 Ingress | NGINX (C) | No | Low | Legacy apps needing custom `nginx.conf` snippets |
| **Traefik** | Modern L7 Ingress / Edge Router | Go | No | **Very Low** | Fast setup, built-in dashboard, clean `IngressRoute` & `Middleware` CRDs |
| **Envoy Gateway** | L4/L7 API Gateway | Envoy (C++) | No | Moderate | Strict upstream Kubernetes Gateway API (`HTTPRoute`), gRPC, canary splits |
| **Cilium** | Full CNI + LB + L7 Ingress/Gateway | Linux eBPF + Envoy | **Yes** (L2 & BGP) | Moderate Day-1 / **Low Day-2** | Cleanest bare-metal stack; replaces `kube-proxy`, MetalLB, and Ingress in one tool |
| **Istio** | Full Service Mesh (East-West + Edge) | Envoy (`ztunnel` / sidecars) | No | **High** | Regulated environments requiring mandatory zero-trust pod-to-pod mTLS & L7 authz policies |

### Real-World Progression
1. Start with **Traefik** (or Envoy Gateway) when you already have a working CNI and want a simple, reliable front door.
2. Adopt **Cilium** on bare metal when you want eBPF performance, Hubble packet observability, and fewer moving parts.
3. Add **Istio** only when compliance or microservice scale demands strict pod-to-pod mTLS and fine-grained internal L7 authorization.

---

## 4. RKE2 Bare-Metal Blueprints

### Option A: RKE2 + Traefik + MetalLB (Simple & Modular)

**1. `/etc/rancher/rke2/config.yaml` (Apply before starting `rke2-server`):**
```yaml
write-kubeconfig-mode: "0644"
tls-san:
  - "192.168.1.11"
  - "rke2.example.com"
cni:
  - "calico"
ingress-controller: "traefik"
```

**2. `/var/lib/rancher/rke2/server/manifests/rke2-traefik-config.yaml`:**
```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-traefik
  namespace: kube-system
spec:
  valuesContent: |-
    service:
      type: LoadBalancer
    deployment:
      kind: DaemonSet
```

**3. `metallb-pool.yaml` (After installing MetalLB):**
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lan-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.240-192.168.1.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lan-l2-adv
  namespace: metallb-system
spec:
  ipAddressPools:
    - lan-pool
```

---

### Option B: RKE2 + Cilium All-in-One (Unified eBPF Stack)

**1. `/etc/rancher/rke2/config.yaml` (Apply before starting `rke2-server`):**
```yaml
write-kubeconfig-mode: "0644"
tls-san:
  - "192.168.1.11"
cni:
  - "cilium"
disable-kube-proxy: true
ingress-controller: "none"
```

**2. `/var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml`:**
```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    kubeProxyReplacement: true
    k8sServiceHost: "192.168.1.11"
    k8sServicePort: "6443"
    l2announcements:
      enabled: true
    externalIPs:
      enabled: true
    ingressController:
      enabled: true
      loadbalancerMode: shared
      default: true
    gatewayAPI:
      enabled: true
    hubble:
      enabled: true
      relay:
        enabled: true
      ui:
        enabled: true
```

**3. `cilium-l2.yaml` (Apply once cluster is ready):**
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
  name: lan-l2-policy
spec:
  interfaces:
    - ^eth0|ens.*
  externalIPs: true
  loadBalancerIPs: true
```

---

## 5. TLS & Certificate Management (`cert-manager` vs. Traefik ACME)

* **Why `cert-manager` is the production standard:**
  * Traefik OSS stores ACME certs in a local `acme.json` file on a PersistentVolume, limiting you to a single replica unless you pay for Traefik Enterprise.
  * `cert-manager` stores certificates as native Kubernetes `Secret`s (`tls.crt` / `tls.key`) in etcd, allowing **multi-node `DaemonSet` Ingress controllers** to read the same cert simultaneously, supporting DNS-01 wildcard certs (`*.example.com`), private internal CAs, and Prometheus renewal metrics.
  * **Rotation:** `cert-manager` automatically renews 90-day Let's Encrypt certs at `2/3` lifetime (30 days before expiry) and overwrites the `Secret` in place; Traefik/Cilium hot-reloads the new cert into memory with zero dropped connections.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: admin@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik
```

---

## 6. Linux Network Namespaces (`ip netns`) Quick Reference

Every container and Kubernetes Pod runs inside a Linux **Network Namespace**—an isolated kernel copy of network interfaces, IP addresses, routing tables, and `iptables`/`nftables` rules.

```bash
# Create two isolated namespaces and connect them with a virtual Ethernet (veth) cable
sudo ip netns add pod1
sudo ip netns add pod2
sudo ip link add veth1 type veth peer name veth2

# Plug each end into its namespace
sudo ip link set veth1 netns pod1
sudo ip link set veth2 netns pod2

# Assign IPs and bring interfaces up
sudo ip netns exec pod1 ip addr add 10.0.0.1/24 dev veth1
sudo ip netns exec pod1 ip link set veth1 up
sudo ip netns exec pod2 ip addr add 10.0.0.2/24 dev veth2
sudo ip netns exec pod2 ip link set veth2 up

# Test connectivity across namespaces
sudo ip netns exec pod1 ping -c 2 10.0.0.2

# Clean up
sudo ip netns del pod1 && sudo ip netns del pod2
```

---

## 7. 4-Week DevOps / SRE / Platform Engineering Lab Plan

### Prerequisites
Ubuntu 24.04 VM (or WSL2 with systemd) with **4 vCPU / 8–16 GB RAM** and `docker`, `containerlab`, `kubectl`, `helm`, `kind` (or Multipass VMs), `terraform` / `opentofu`, and `tcpdump`.

### Phase 1: Linux Networking & Containerlab (Week 1)
* **Lab 1.1 — Hand-Build a Single-Node CNI (`ip netns` + Linux Bridge):**
  * Create a Linux bridge (`br0` with `10.42.1.1/24`), wire `pod1` (`10.42.1.10`) and `pod2` (`10.42.1.11`) via `veth` pairs, enable `net.ipv4.ip_forward=1`, add an `iptables` `MASQUERADE` rule for internet egress, and inspect packets with `sudo tcpdump -i br0 -n`.
* **Lab 1.2 — Multi-Node BGP Routing with Containerlab:**
  * Deploy a `topology.clab.yml` with two **FRRouting (`frr`)** containers and two Linux hosts, configure eBGP peering (`AS 65001` ↔ `AS 65002`), verify routes with `vtysh -c "show bgp summary"`, and simulate a link failure to observe BGP reconvergence.

### Phase 2: Bare-Metal Multi-Node Kubernetes + Cilium (Week 2)
* **Lab 2.1 — Multi-Node Cluster + Cilium eBPF:**
  * Stand up a 3-node RKE2 or `kind` cluster with `disable-kube-proxy: true`, install **Cilium** (`kubeProxyReplacement=true`, Hubble UI, L2 Announcements), configure `CiliumLoadBalancerIPPool`, and inspect eBPF load-balancing maps (`cilium bpf lb list`).
* **Lab 2.2 — Production TLS, GitOps & Chaos Drill:**
  * Deploy **`cert-manager`** with an internal CA `ClusterIssuer`, deploy **ArgoCD** synced to a Git repository, install **`kube-prometheus-stack`**, and run a failover drill by shutting down the node holding your floating LoadBalancer IP during a live `curl` loop.

### Phase 3: Cloud VPC & Managed Kubernetes via Terraform (Weeks 3–4)
* **Lab 3.1 — Provision VPC & EKS/GKE with Terraform:**
  * Write **Terraform / OpenTofu** modules for a multi-AZ VPC (public/private subnets, NAT Gateway) and managed Kubernetes (EKS or GKE), observing how cloud Network Load Balancers replace bare-metal MetalLB/Cilium L2 IPs.
* **Lab 3.2 — Cloud IAM & DevSecOps CI/CD Pipeline:**
  * Configure **IRSA / Pod Identity** (AWS) or **Workload Identity** (GCP) for keyless DNS/TLS automation, and build a **GitHub Actions** pipeline that builds a container, scans CVEs with **Trivy**, pushes to a registry, and updates your GitOps repo for ArgoCD.