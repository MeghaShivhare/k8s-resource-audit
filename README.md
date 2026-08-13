# k8s-resource-audit

A lightweight, local, and production-ready CLI script that scans Kubernetes Deployments and audits every container individually to report missing CPU/Memory requests or limits.

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
Deployments scanned: 4
Deployments with issues: 3
```

---

## Why Audit CPU & Memory Settings?

Kubernetes scheduling and cluster stability depend heavily on setting resource **requests** and **limits** properly:

*   **Requests** (used for scheduling): Helps the scheduler place pods on nodes with enough capacity.
*   **Limits** (used for resource control): Prevents containers from consuming excessive resources and causing node instability.

### Consequences of Missing Resources

Without these configurations defined, clusters are prone to:
*   **Inefficient scheduling:** Kubernetes doesn't know how much resources pods require, leading to unbalanced nodes.
*   **Noisy-neighbor problems:** Single misbehaving pods can starve other co-located applications of CPU or memory.
*   **Unexpected resource contention & OOM Kills:** Lack of memory limits can result in critical system daemons or other pods being killed due to Out-Of-Memory (OOM) events.
*   **Unnecessary node scaling:** Cluster autoscalers may scale up nodes prematurely or fail to scale down, driving up cloud costs.

---

## Features

*   **Granular Container Audits:** Does not just check if a deployment has *some* resource definitions; audits **every single container** individually (e.g., helper sidecars, proxies, etc.).
*   **Decoupled & Offline Ready:** Can query a live cluster context or parse an offline JSON file/stdin pipe (perfect for CI/CD pipelines, GitOps checks, or offline runs).
*   **Multiple Formats:** Formats audit reports in `table` (terminal alignment), `csv`, `tsv`, or `json`.
*   **Filterable:** Drill down by specific namespaces or display only problematic containers.

---

## Requirements

*   `jq` (required for JSON querying)
*   `kubectl` (required only if scanning a live cluster)
*   Access to a Kubernetes cluster (with a configured kubeconfig context)

---

## Installation & Setup

Clone the repository and make the script executable:

```bash
git clone git@github.com-personal:MeghaShivhare/k8s-resource-audit.git
cd k8s-resource-audit
chmod +x k8s-resource-audit.sh
```

---

## Usage Guide

### 1. Basic Scan (All Namespaces)
Scan all deployments in the active cluster context and display a clean terminal table:
```bash
./k8s-resource-audit.sh
```

### 2. Namespace Filtering
Audit deployments in a specific namespace (e.g., `backend`):
```bash
./k8s-resource-audit.sh -n backend
```

### 3. Display Only Missing/Problematic Workloads
Hide containers that have all requests and limits defined:
```bash
./k8s-resource-audit.sh --only-missing
```

### 4. Reading from a Saved JSON File or Stdin
Run the audit using pre-exported configuration data (ideal for offline testing or pipelines):
```bash
# Save cluster deployment config to JSON
kubectl get deployments -A -o json > cluster-deployments.json

# Audit offline
./k8s-resource-audit.sh -f cluster-deployments.json

# Or pipe directly
kubectl get deployments -A -o json | ./k8s-resource-audit.sh -f -
```

### 5. Format Configurations
Export results for further processing:
```bash
# Export as CSV for spreadsheet reporting
./k8s-resource-audit.sh --format csv > audit-report.csv

# Export as JSON for downstream scripting
./k8s-resource-audit.sh --format json > audit-report.json
```

---

## Development & Testing

A mock deployment list is provided in `test-resources/mock-deployments.json` representing multiple container configurations (e.g. perfect resource allocations, missing requests, missing limits).

You can run test suites offline:
```bash
./k8s-resource-audit.sh -f test-resources/mock-deployments.json
```

## License

This project is licensed under the [MIT License](LICENSE).
