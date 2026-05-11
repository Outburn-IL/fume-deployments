# FUME - Infrastructure Requirements

This document describes the compute (CPU), memory and storage capacity required to host the FUME application stack on Kubernetes, with separate sizing for a **Development** and a **Production** environment. It is intended to help plan and provision the underlying infrastructure.

The figures are sizing baselines derived from the standard FUME Helm chart configuration. Actual peak resource use depends on the size, rate and complexity of the transformations processed; see [Assumptions](#assumptions) at the end.

Networking and DNS, public TLS certificates, the FUME Enterprise license, container-registry credentials, the organizational HL7 FHIR server, and the optional identity provider for authentication are addressed separately and are not part of this sizing document.

---

## 1. Platform baseline (both environments)

| Item | Requirement |
|---|---|
| Orchestration | Kubernetes **1.19 or newer** (managed - EKS / GKE / AKS - or self-managed) |
| Deployment tooling | Helm **3.2.0 or newer** (used to install and upgrade; not a running component) |
| Worker node OS / architecture | **Linux, x86-64** (the FUME container images are Linux/amd64) |
| Default storage class | A cluster default storage class with dynamic provisioning |
| Production storage class | Additionally a **ReadWriteMany (RWX)**-capable storage class on **SSD-class** disk (e.g. NFS, AWS EFS, Azure Files, GCP Filestore) |

For a **self-managed** Kubernetes cluster, add **3 control-plane nodes** at approximately 2 vCPU / 4 GiB each (for high availability), in addition to the worker-node figures below. Managed Kubernetes services do not require control-plane sizing.

---

## 2. Application components

The FUME stack consists of the following components. Per-pod CPU and memory **requests** (the capacity reserved on a node) and **limits** (the hard cap) are:

| Component | Role | Replicas (Dev) | Replicas (Prod) | CPU request | CPU limit | Memory request | Memory limit |
|---|---|---|---|---|---|---|---|
| FUME Enterprise Server | FHIR mapping engine - required | 1 | 3 (auto-scales 3 → 20) | 1.0 vCPU | 2.0 vCPU | 2 GiB | 4 GiB |
| FUME Designer | Browser UI for authoring mappings - optional | 1 | 0 (disabled in production) | 0.25 vCPU | 0.5 vCPU | 256 MiB | 512 MiB |

The mapping engine performs a slow first start (it downloads and compiles FHIR packages on initial run); this is why a persistent package cache is recommended in production. It does not affect steady-state sizing.

---

## 3. Development environment

A single mapping-engine replica plus the Designer UI. No auto-scaling.

### Compute and memory

| | CPU request | CPU limit | Memory request | Memory limit |
|---|---|---|---|---|
| FUME Enterprise Server × 1 | 1.0 vCPU | 2.0 vCPU | 2.0 GiB | 4.0 GiB |
| FUME Designer × 1 | 0.25 vCPU | 0.5 vCPU | 0.25 GiB | 0.5 GiB |
| **Total** | **1.25 vCPU** | **2.5 vCPU** | **2.25 GiB** | **4.5 GiB** |

### Storage

| Volume | Access mode | Capacity | Storage class | Notes |
|---|---|---|---|---|
| Templates | ReadWriteOnce | 1 GiB | default | Mapping/template files; single-writer is sufficient at one replica |
| FHIR package cache | ReadWriteOnce | 5 GiB (optional) | default | Optional in Dev; without it, packages are re-downloaded after a pod restart |

### Recommended node sizing - Development

| | Minimum | Recommended |
|---|---|---|
| Worker nodes | 1 | 1 |
| Size per node | 4 vCPU / 8 GiB | 4 vCPU / 8 GiB |
| OS disk per node | 30 GiB | 50 GiB |
| Persistent block storage | ~6 GiB | ~6 GiB |

A single 4 vCPU / 8 GiB node comfortably hosts the FUME components (2.5 vCPU / 4.5 GiB at their limits) together with Kubernetes system overhead (roughly 25% of the node).

---

## 4. Production environment

The mapping engine only (the Designer UI is disabled). A baseline of **3 replicas**, with horizontal auto-scaling configured up to **20 replicas** for burst load.

### Compute and memory - baseline (3 replicas)

| | CPU request | CPU limit | Memory request | Memory limit |
|---|---|---|---|---|
| FUME Enterprise Server × 3 | 3.0 vCPU | 6.0 vCPU | 6.0 GiB | 12.0 GiB |
| **Total (baseline)** | **3.0 vCPU** | **6.0 vCPU** | **6.0 GiB** | **12.0 GiB** |

### Burst capacity (informational)

Auto-scaling can grow the engine to **20 replicas** under heavy transformation load - up to **20 vCPU / 40 GiB requested** (40 vCPU / 80 GiB at the limits) for the FUME pods alone. This is intended to be served by a Kubernetes cluster auto-scaler adding nodes on demand rather than by pre-provisioned capacity. If the target cluster cannot auto-scale, use the fixed-fleet sizing below and size it to the expected peak.

### Storage

| Volume | Access mode | Capacity | Storage class | Notes |
|---|---|---|---|---|
| Templates | ReadWriteMany | 5 GiB | SSD | Must be shared (RWX) across all replicas |
| FHIR package cache | ReadWriteMany | 100 GiB | SSD | Shared, persistent cache of FHIR packages, snapshots and terminology; **grows over time** - provision with room to expand |
| **Total persistent storage** | ReadWriteMany | **~105 GiB SSD** | | |

### Recommended node sizing - Production

| | Minimum (with cluster auto-scaler) | Recommended | Fixed fleet (no auto-scaler) |
|---|---|---|---|
| Worker nodes | 3 | 3 | 3 (or more, sized to peak) |
| Size per node | 4 vCPU / 8 GiB | **8 vCPU / 16 GiB** | 8 vCPU / 16 GiB |
| Rationale | One engine pod per node (2 vCPU / 4 GiB at its limit) plus system overhead; the cluster auto-scaler adds nodes for burst | Same high-availability spread, but each node absorbs a few extra engine pods before a new node is needed | Fixed capacity; 3 × (8 vCPU / 16 GiB) hosts roughly 6 engine replicas. For higher sustained peaks, add nodes or use larger nodes. |
| OS disk per node | 50 GiB | 50 GiB | 50 GiB |
| Placement | Spread across 3 nodes / availability zones (anti-affinity) so the loss of one node or zone never removes all replicas | same | same |

For a standard production deployment, the **Recommended** column - 3 worker nodes at 8 vCPU / 16 GiB plus approximately 105 GiB of SSD ReadWriteMany storage - is the figure to plan against. The fixed-fleet column applies only where cluster auto-scaling is unavailable.

---

## 5. Storage requirements summary

| Volume | Dev access mode | Dev size | Prod access mode | Prod size | Performance | Purpose |
|---|---|---|---|---|---|---|
| Templates | ReadWriteOnce | 1 GiB | ReadWriteMany | 5 GiB | Standard | Mapping/template files, shared across replicas in production |
| FHIR package cache | ReadWriteOnce (optional) | 5 GiB | ReadWriteMany | 100 GiB | SSD | Persisted FHIR packages, snapshots and terminology; avoids slow re-download after restarts; grows over time |
| Container / OS scratch | node disk | included in OS disk | node disk | included in OS disk | Standard | Pod scratch space, container layers, logs |

In production both persistent volumes require **ReadWriteMany** access. Confirm that the target cluster provides an RWX-capable storage class (NFS, AWS EFS, Azure Files, GCP Filestore, CephFS, etc.) - managed Kubernetes services do not always include one by default.

---

## 6. Sizing summary

### Development

| Resource | Quantity |
|---|---|
| Kubernetes worker nodes | 1 |
| vCPU per node | 4 |
| RAM per node | 8 GiB |
| Total worker vCPU | 4 |
| Total worker RAM | 8 GiB |
| OS disk per node | 30–50 GiB |
| Persistent block storage (default class) | ~6 GiB |
| ReadWriteMany storage class required? | No |
| SSD storage class required? | No (recommended for the optional cache) |

### Production (baseline; cluster auto-scaler handles burst)

| Resource | Quantity |
|---|---|
| Kubernetes worker nodes | 3 recommended (minimum 3) |
| vCPU per node | 8 recommended (minimum 4) |
| RAM per node | 16 GiB recommended (minimum 8 GiB) |
| Total worker vCPU | 24 recommended / 12 minimum |
| Total worker RAM | 48 GiB recommended / 24 GiB minimum |
| OS disk per node | 50 GiB each |
| Persistent storage - Templates | 5 GiB, ReadWriteMany, SSD |
| Persistent storage - FHIR cache | 100 GiB, ReadWriteMany, SSD (provision for growth) |
| Total persistent storage | ~105 GiB SSD ReadWriteMany |
| Cluster auto-scaling (for burst to 20 replicas) | Recommended; if unavailable, size the fixed fleet to the expected peak |
| Self-managed cluster only - control-plane nodes | 3 × 2 vCPU / 4 GiB (not applicable on managed Kubernetes) |

---

## Assumptions

- CPU, memory and replica figures reflect the standard FUME Helm chart configuration for each environment. If that configuration changes, this document should be updated.
- Node sizing is driven primarily by pod **requests**, with enough margin to absorb bursts up to the **limits**, and leaves roughly 20–25% of each node for the Kubernetes runtime, networking, logging and monitoring agents, and other system components.
- The production auto-scaling ceiling of 20 mapping-engine replicas is a safety limit for spikes, not a continuous operating level. Pre-provisioning for the full ceiling is unnecessary where cluster auto-scaling is available.
- The production FHIR package cache (100 GiB) accumulates FHIR packages, generated snapshots and terminology data over time. Use an expandable storage class and monitor utilization.
- The Designer UI is disabled in production by default. If it is enabled there, add the Designer figures from section 2 per replica.
- CPU and memory use scale with the size, rate and complexity of the transformations. For unusually large payloads, complex mappings or high throughput, validate the sizing - particularly the fixed-fleet option - with a representative load test.
