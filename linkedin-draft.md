🚀 Ever had a Kubernetes node unexpectedly run out of memory, or a pod crash loop due to OOM kills, while your cluster autoscaler needlessly spins up new nodes?

Nine times out of ten, the culprit is missing CPU and memory requests or limits.

Kubernetes scheduler relies on requests to place pods efficiently, and the node kernel relies on limits to prevent noisy neighbors from starving other applications. Leaving these unconfigured is a recipe for high cloud bills and cluster instability.

I wanted a quick, lightweight way to audit my deployments, so I built **k8s-resource-audit** — a local, dependency-light CLI script powered by `kubectl` and `jq`.

### 💡 The Core Design Decision
Many basic checks only answer: *"Does the deployment have resources set?"* 
If your main `api` container is set up correctly, but a sidecar proxy or log shipper is empty, a naive script marks the deployment as "healthy." 

This script audits **every single container individually** to catch configurations that slip through the cracks:

```
Kubernetes Resource Audit
────────────────────────────────────────────────────────────────────────────────

NAMESPACE     DEPLOYMENT       CONTAINER    ISSUE
backend       api              api          OK
backend       api              sidecar      Requests & limits missing
backend       worker           worker       Memory limit missing
payments      checkout         checkout     Requests missing
monitoring    exporter         exporter     Limits missing

────────────────────────────────────────────────────────────────────────────────
Deployments scanned: 42
Deployments with issues: 7
```

### ✨ Key Features
* 🔍 **Granular Container Auditing**: Inspects helper containers, sidecars, and main apps separately.
* ☁️ **Offline Ready**: Can query live cluster contexts, or parse an offline JSON file/stdin pipe (perfect for CI/CD or GitOps static analysis).
* 📊 **Multi-Format Output**: Outputs as terminal-aligned tables, CSV (for spreadsheet reporting), TSV, or raw JSON (for downstream automation).
* 🎯 **Namespace Filtering**: Audit the entire cluster or drill down into specific namespaces.

Check out the code here: [github.com/MeghaShivhare/k8s-resource-audit](https://github.com/MeghaShivhare/k8s-resource-audit)

How do you enforce resource requests and limits in your clusters? Let me know in the comments! 👇

#kubernetes #devops #finops #sre #cloudnative #gitops #platformengineering
