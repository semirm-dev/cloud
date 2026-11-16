## CNI Comparison: Cilium vs. Calico vs. Canal

Every Kubernetes cluster needs a **CNI (Container Network Interface)** to assign Pod IPs (`10.42.0.0/16`), wire pod virtual Ethernet (`veth`) interfaces, and route packets between nodes.

| CNI        | Data Plane Engine                                          | Key Features                                                                                         | When to Choose It                                                                                         |
| :--------- | :--------------------------------------------------------- | :--------------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------- |
| **Cilium** | **Linux eBPF** (bypasses `iptables` & `kube-proxy`)        | L3/L4/L7 NetworkPolicies, Hubble flow UI, built-in BGP/L2 LoadBalancer, built-in Ingress/Gateway API | **Modern default** for both bare-metal and cloud clusters; highest performance and best packet visibility |
| **Calico** | `iptables` / `nftables` / eBPF + **BGP (BIRD)**            | Mature L3 BGP routing, strict NetworkPolicies, very predictable                                      | Traditional enterprise setups or teams already standardized on Calico BGP                                 |
| **Canal**  | **Flannel** (VXLAN overlay) + **Calico** (NetworkPolicies) | Simple VXLAN pod networking + Calico firewall rules                                                  | Lightweight legacy clusters (default in older RKE2/K3s installs); largely superseded by Cilium            |

### Key CNI Notes to Remember

- **Overlay (VXLAN/Geneve) vs. Native Routing (BGP):** Overlay encapsulates pod packets inside UDP packets so any switch works out of the box; Native Routing advertises Pod CIDRs directly into your physical/VPC routers for zero encapsulation overhead.
- **eBPF `kube-proxy` Replacement (Cilium):** Disabling `kube-proxy` lets Cilium handle Kubernetes `Service` ClusterIP/NodePort load balancing directly in kernel eBPF maps—eliminating `iptables` rule bloat on large clusters.

- **How Cilium Ingress/Gateway is configured:**
  - Enable `l2announcements` (or `bgpControlPlane`), `ingressController.enabled=true` (or `gatewayAPI.enabled=true`), and define a `CiliumLoadBalancerIPPool` for your reserved LAN IPs.
- **Minimal Helm Values Hint (`cilium`):**
  ```yaml
  kubeProxyReplacement: true
  l2announcements:
    enabled: true
  ingressController:
    enabled: true
    loadbalancerMode: shared # All Ingresses share one LoadBalancer IP
    default: true
  gatewayAPI:
    enabled: true
  ```

---

node ip -> fixed single ip of the server (physical server)
loadbalancer ip -> routes between physical nodes (lb => n1, n2, n3 || n1 + lb -> n2 + lb -> n3 + lb => kube apiserver)

ingress = traefik, replaces old nginx
cni = cilium (all in one, fast, modern, ebpf) | calico (old standard, bgp) | canal (hybrid, flannel + calico)

cni builds virtual network between nodes (route tables with pod ips) so pod-to-pod can communicate.
node-to-node communicate directly because they are real machines, no cni or k8s invovled.

external-dns automatically updates dns records in your domain provider, listens for new ingress host.

```text
1. USER BROWSER (Internet)
   │  Asks DNS: "Where is app.example.com?"
   ▼
2. DOMAIN REGISTRAR / DNS PROVIDER (e.g., Cloudflare, Namecheap)
   │  IP Source: Public IPv4 leased from your ISP / Cloud Provider (e.g., 203.0.113.50)
   │  Handoff: Returns DNS 'A' record -> 203.0.113.50
   ▼
3. EDGE ROUTER / FIREWALL (Datacenter Gateway)
   │  IP Source: Public WAN IP (203.0.113.50) -> translated to Internal LAN IP (192.168.1.240), network rule set in our router/gateway by network addmin
   │  Handoff: Port-forwards TCP 80/443 (NAT) OR routes directly via BGP to the cluster
   ▼
4. LOADBALANCER SERVICE / NODE IP (Cluster Entry Point)
   │  IP Source:
   │   • MetalLB / Cilium IPPool (e.g., 192.168.1.240 - unused LAN block you reserved)
   │   • OR Node's real IP from Datacenter DHCP/Static config (e.g., 192.168.1.11)
   │  Handoff: ARP/BGP or HostPort delivers packet to Node 1's network card
   ▼
5. INGRESS CONTROLLER POD (NGINX on RKE2 / HAProxy on OpenShift)
   │  IP Source: Virtual CNI Pod IP (10.42.1.8) + bound to Host/LB Port 443
   │  Handoff:
   │   • Decrypts HTTPS using TLS Secret (auto-created by cert-manager via Let's Encrypt)
   │   • Reads "Host: app.example.com" & "/api" -> matches Ingress rule -> finds target Pod IP
   ▼
6. CNI NETWORK LAYER (Cilium / Calico / Canal / OVN-Kubernetes)
   │  IP Source: Cluster CIDR (10.42.0.0/16 - virtual RFC 1918 space invented in cluster config)
   │  Handoff:
   │   • Looks up destination Pod IP (10.42.2.15) -> sees it lives on Node 2 (192.168.1.12)
   │   • Wraps packet in VXLAN/Geneve tunnel (or routes natively via BGP) across physical switch
   │   • Enforces NetworkPolicy firewall rules (via eBPF maps or iptables)
   ▼
7. TARGET APPLICATION POD (Running on Node 2)
      IP Source: Node 2's allocated /24 slice (10.42.2.15), assigned by CNI IPAM binary
      Handoff: Node 2's CNI unwraps packet -> pushes through veth virtual cable into container port 8080
```

```bash
# 1. Create two isolated network stacks
sudo ip netns add pod1
sudo ip netns add pod2

# 2. Create a virtual Ethernet cable with two ends
sudo ip link add veth1 type veth peer name veth2

# 3. Plug one end into pod1 and the other end into pod2
sudo ip link set veth1 netns pod1
sudo ip link set veth2 netns pod2

# 4. Assign IPs and bring the interfaces up inside each namespace
sudo ip netns exec pod1 ip addr add 10.0.0.1/24 dev veth1
sudo ip netns exec pod1 ip link set veth1 up
sudo ip netns exec pod2 ip addr add 10.0.0.2/24 dev veth2
sudo ip netns exec pod2 ip link set veth2 up

# 5. Ping from pod1 to pod2 across the virtual cable
sudo ip netns exec pod1 ping -c 2 10.0.0.2

# 6. Clean up
sudo ip netns del pod1 && sudo ip netns del pod2
```
