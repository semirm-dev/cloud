## Ingress

- **How Traefik is configured:**
  - Deployed via Helm (or RKE2's built-in `rke2-traefik` chart) as a `Deployment` or `DaemonSet`.
  - Its Kubernetes `Service` is set to `type: LoadBalancer` (receiving a cloud LB IP or bare-metal MetalLB/Cilium floating IP).
  - Entrypoints listen on `web` (`:80`, typically configured to redirect to HTTPS) and `websecure` (`:443`).
- **Minimal Helm Values Hint (`traefik`):**
  ```yaml
  deployment:
    kind: DaemonSet # Runs on every node for high availability
  service:
    type: LoadBalancer
  ports:
    web:
      redirectTo:
        port: websecure # Automatic HTTP -> HTTPS redirect
  ```

```yaml
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
