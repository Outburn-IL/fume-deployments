# FUME Helm Chart

This Helm chart deploys the FUME application stack on Kubernetes, including:
- FUME Enterprise Server (Backend) - Always deployed
- FUME Mapping Designer (Frontend) - Optional deployment

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Secrets and License Setup](#secrets-and-license-setup)
- [Storage Configuration](#storage-configuration)
- [Environment-Specific Deployments](#environment-specific-deployments)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)
- [Uninstalling](#uninstalling)

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- Persistent Volume support (for templates and optional shared caches)
- Valid FUME Enterprise license file

## Quick Start

### 1. Prepare Your Environment

Create the required secrets and ConfigMaps before deploying:

```bash
# Create namespace (optional)
kubectl create namespace fume

# (Optional) Create Docker Hub pull secret. Only needed if your cluster/namespace/service account
# does not already provide credentials to pull private images from Docker Hub.
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=docker.io \
  --docker-username=outburnltd \
  --docker-password=YOUR_DOCKERHUB_API_TOKEN \
  --namespace fume

# License secret (mounts only the .lic file via subPath to avoid overlaying app dirs)
kubectl create secret generic fume-license \
  --from-file=license.key.lic=./path/to/license.key.lic \
  --namespace fume

# Application secrets (customize with your values)
kubectl create secret generic fume-secrets \
  --from-literal=FHIR_SERVER_BASE="https://your-fhir-server.com/fhir" \
  --from-literal=FHIR_SERVER_UN="your-fhir-username" \
  --from-literal=FHIR_SERVER_PW="your-fhir-password" \
  --namespace fume
```

### 2. Deploy with Default Settings

Important: You must provide required configuration values during deployment.

```bash
# Deploy with frontend enabled (development/testing)
helm install fume ./helm/fume \
  --namespace fume \
  --set configMap.CANONICAL_BASE_URL="https://fume.your-company.com" \
  --set configMap.FUME_SERVER_URL="https://your-fume-api.com" \
  --set configMap.FHIR_PACKAGES="<org-specific-packages>"

# Deploy for production (frontend disabled)
helm install fume ./helm/fume \
  -f ./helm/fume/values.prod.yaml \
  --namespace fume \
  --set configMap.CANONICAL_BASE_URL="https://fume.your-company.com" \
  --set configMap.FUME_SERVER_URL="https://your-fume-api.com" \
  --set configMap.FHIR_PACKAGES="<org-specific-packages>"
```

## Configuration

### Image Configuration

Update the image settings in `values.yaml` (or override in `values.prod.yaml`) or via command line:

```yaml
image:
  backend:
    repository: outburnltd/fume-enterprise-server  # Private Docker Hub repository
    tag: "1.8.0"
  frontend:
    repository: outburnltd/fume-designer           # Private Docker Hub repository  
    tag: "2.1.3"
  pullPolicy: IfNotPresent
  pullSecret: "dockerhub-secret"  # Optional: set if your cluster/namespace doesn't already provide pull credentials
```

Important: The FUME images are hosted as private repositories on Docker Hub. Ensure your cluster can pull them by either:
- Preconfiguring image pull credentials at the namespace/service account or cluster level (e.g., imagePullSecrets on the default ServiceAccount), or
- Setting `image.pullSecret` and creating the secret as shown below.

Notes:
- Username is always `outburnltd` (fixed)
- Password is the Docker Hub API token you'll receive from Outburn via secure channel
- Avoid using the `latest` tag; pin a specific version or digest

### TLS and certificate trust (Node.js)

The containers run Node.js clients that must trust your organization's CAs to make outbound HTTPS calls (e.g., to FHIR servers). By default, this chart configures Node.js to trust the Kubernetes ServiceAccount CA by setting `NODE_EXTRA_CA_CERTS=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`.

You can also mount your own corporate CA bundle (PEM) from a Secret and point Node.js to it.

Defaults (in `values.yaml`):

```yaml
tls:
  useServiceAccountCA: true
  customCA:
    enabled: false
    secretName: ""
    key: ca.crt
    mountPath: /etc/ssl/custom-ca
    filename: ca.crt
```

Use a custom CA bundle (preferred for enterprise networks):

1) Create a Secret that contains your PEM bundle (single file, may contain multiple certs):

```cmd
kubectl create secret generic custom-ca ^
  --from-file=ca.crt=corp-root-bundle.pem ^
  --namespace fume
```

2) Enable and reference it in values:

```yaml
tls:
  useServiceAccountCA: false
  customCA:
    enabled: true
    secretName: custom-ca
    key: ca.crt
    mountPath: /etc/ssl/custom-ca
    filename: ca.crt
```

Behavior:
- If `tls.customCA.enabled=true`, the chart mounts the secret and sets `NODE_EXTRA_CA_CERTS` to `<mountPath>/<filename>`.
- Else if `tls.useServiceAccountCA=true` (default), Node.js trusts the SA CA at `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`.
- No insecure overrides are used. Avoid setting `NODE_TLS_REJECT_UNAUTHORIZED=0`.

### Enable/Disable Frontend

```yaml
# Enable frontend (default)
enableFrontend: true

# Disable frontend (production)
enableFrontend: false
```

### Service Configuration

```yaml
service:
  backend:
    type: ClusterIP    # ClusterIP, NodePort, or LoadBalancer
    port: 42420
  frontend:
    type: ClusterIP
    port: 3000
```

### Resource Limits

```yaml
backend:
  replicaCount: 1
  resources:
    limits:
      cpu: 2000m
      memory: 4Gi
    requests:
      cpu: 1000m
      memory: 2Gi

frontend:
  replicaCount: 1
  resources:
    limits:
      cpu: 500m
      memory: 1Gi
    requests:
      cpu: 250m
      memory: 512Mi
```

## Secrets and License Setup

### Secrets and Image Pull Access

The chart expects the following to exist (some created externally):

#### 1. Docker Hub Pull Secret (`dockerhub-secret`) — Optional
Only needed if your cluster/namespace/service account does not already provide credentials to pull the private images.

```bash
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=docker.io \
  --docker-username=outburnltd \
  --docker-password=YOUR_DOCKERHUB_API_TOKEN \
  --namespace fume
```

Notes:
- Username is always `outburnltd` (fixed)
- Password is the Docker Hub API token you'll receive from Outburn via secure channel
- Set the secret name in `image.pullSecret` if you create it

#### 2. License Secret (`fume-license`) — Required
Contains the FUME Enterprise license file (same file for both backend and frontend):

```bash
kubectl create secret generic fume-license \
  --from-file=license.key.lic=./FUME_Enterprise.lic \
  --namespace fume
```

*Note: FUME automatically scans for `*.lic` files in the root directory, so the exact filename doesn't matter as long as it has a `.lic` extension.*

#### 3. Application Secrets (`fume-secrets`) — Required
Contains sensitive FHIR server configuration:

```bash
kubectl create secret generic fume-secrets \
  --from-literal=FHIR_SERVER_BASE="https://your-fhir-server.com/fhir" \
  --from-literal=FHIR_SERVER_UN="your-fhir-username" \
  --from-literal=FHIR_SERVER_PW="your-fhir-password" \
  # Optional: add a private registry auth token if using configMap.FHIR_PACKAGE_REGISTRY_URL
  # --from-literal=FHIR_PACKAGE_REGISTRY_TOKEN="s3cr3t-token" \
  --namespace fume
```

### image.pullSecret

Optional; only required if your cluster doesn’t already have access.

```yaml
secrets:
  fume: "my-custom-fume-secrets"
  license: "my-custom-license-secret"

image:
  pullSecret: "my-custom-dockerhub-secret"
```

## Storage Configuration

### Persistent Volumes

The chart creates PVCs for persistent data:

```yaml
storage:
  templates:
    enabled: true
    # If you manage this PVC externally, set its name here; otherwise the chart will create `<release>-templates`.
    existingClaim: ""
    size: 1Gi
    storageClass: "ssd"
    accessMode: ReadWriteOnce

  # Optional: Persist the FHIR package cache and allow offline/preloaded use
  fhirCache:
    enabled: true
    # If you have an existing PVC you manage externally, set its name here;
    # otherwise the chart will create `<release>-fhir-cache` when enabled.
    # existingClaim: my-prepared-fhir-cache
    size: 5Gi
    storageClass: "ssd"
    accessMode: ReadWriteOnce

  # Optional: Persist the mappings folder for file-backed mappings.
  mappings:
    enabled: false
    existingClaim: ""
    size: 1Gi
    storageClass: "ssd"
    accessMode: ReadWriteMany
```

### Storage Classes

Common storage class examples:
- AWS EKS: `gp2`, `gp3`, `io1`
- Google GKE: `standard`, `ssd`
- Azure AKS: `default`, `managed-premium`
- On-premise: Check with your cluster administrator

### Preloading FHIR package cache (egress blocked networks)

When outbound internet is blocked, enable a persistent cache and preload packages manually:

1) Enable the FHIR cache volume

```yaml
storage:
  fhirCache:
    enabled: true
    size: 5Gi
    storageClass: "ssd"   # or your class
    accessMode: ReadWriteOnce
```

Optionally set `existingClaim` to use a PVC you manage:

```yaml
storage:
  fhirCache:
    enabled: true
    existingClaim: my-prepared-fhir-cache
```

2) Create or locate the PVC (if not using existingClaim). The chart will create `<release>-fhir-cache` when enabled.

3) Load packages into the PVC. The backend mounts the cache at `/usr/fume/fhir-packages`.

You can copy data into the PVC in several ways:

- Temporary helper pod (example uses busybox):

```cmd
kubectl run fhir-cache-loader --rm -it --restart=Never --image=busybox ^
  --namespace fume -- sh

# Inside the pod, mount the PVC (if you need a pod with the mount, create one):
# Alternatively, use 'kubectl cp' against a running backend pod after enabling the PVC.
```

- Using kubectl cp to a backend pod after enabling the PVC:

```cmd
# Copy your prepared cache directory structure (must contain a 'packages' subdir)
# This copies into the mounted PVC at /usr/fume/fhir-packages
kubectl -n fume cp ./cache/. <backend-pod-name>:/usr/fume/fhir-packages
```

Expected on disk inside the pod:

```
/usr/fume/fhir-packages/
  packages/
    <package-name>@<version>/
    <another-package>@<version>/
```

Notes:
- The path `/usr/fume/fhir-packages` is writable in the container and mapped to the PVC when enabled.
- If `fhirCache.enabled=false`, the chart uses an ephemeral emptyDir at the same path (default behavior).
- For teams wanting direct, outside-cluster access to the cache, back the PVC with an RWX storage class (e.g., NFS/EFS/AzureFile) and set `storage.fhirCache.existingClaim` to a claim you also mount elsewhere.

### Two DevOps-friendly workflows for preloading

1) Mirror from a warmed backend pod (simple)

- Temporarily allow egress or run in a network that permits downloads once, let FUME populate `/usr/fume/fhir-packages`.
- Then copy that directory out and reuse it:

```cmd
# Copy packages from a warmed pod to your local machine
kubectl -n fume cp <backend-pod-name>:/usr/fume/fhir-packages ./packages

# Later, preload into another environment (with PVC enabled)
kubectl -n fume cp ./packages/. <backend-pod-name>:/usr/fume/fhir-packages
```

2) Use an RWX-backed existing PVC (transparent, multi-writer)

- Provision a ReadWriteMany volume (e.g., NFS, EFS, AzureFile) and create a PVC for it in the target namespace.
- Mount that PVC in the chart by setting:

```yaml
storage:
  fhirCache:
    enabled: true
    existingClaim: my-prepared-fhir-cache
```

- Mount the same PVC on a utility pod or external node to manage files directly. Example helper pod manifest:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: fhir-cache-helper
  namespace: fume
spec:
  containers:
    - name: shell
      image: alpine:3.20
      command: ["/bin/sh","-c","sleep 36000"]
      volumeMounts:
        - name: cache
          mountPath: /cache
  volumes:
    - name: cache
      persistentVolumeClaim:
        claimName: my-prepared-fhir-cache
  restartPolicy: Never
```

Then, from your workstation:

```cmd
# Copy your prepared content into the shared PVC via the helper pod
kubectl -n fume cp .\packages\. fhir-cache-helper:/cache/packages
```

All backend pods will see the files at `/usr/fume/fhir-packages` (mounted from the same PVC), with no further changes needed.

## Environment-Specific Deployments

### Development Environment

```bash
# Use default values with frontend enabled
helm install fume-dev ./helm/fume \
  --namespace fume-dev \
  --set image.backend.tag=1.8.0 \
  --set image.frontend.tag=2.1.3 \
  --set env.FUME_DESIGNER_HEADLINE="FUME Designer - DEV" \
  --set configMap.FUME_SERVER_URL="http://localhost:42420" \
  --set configMap.CANONICAL_BASE_URL="https://fume.your-company.com" \
  --set configMap.FHIR_PACKAGES="<org-specific-packages>"
```

### Test Environment

```bash
# Custom values for testing
helm install fume-test ./helm/fume \
  --namespace fume-test \
  --set image.backend.tag=1.8.0 \
  --set image.frontend.tag=2.1.3 \
  --set backend.replicaCount=2 \
  --set enableFrontend=true \
  --set env.FUME_DESIGNER_HEADLINE="FUME Designer - TEST" \
  --set configMap.FUME_SERVER_URL="https://fume-api-test.company.com" \
  --set configMap.CANONICAL_BASE_URL="https://fume.your-company.com" \
  --set configMap.FHIR_PACKAGES="<org-specific-packages>" \
  --set env.FHIR_SERVER_AUTH_TYPE="BASIC"
```

### Production Environment

```bash
# Use production values file
helm install fume-prod ./helm/fume \
  -f ./helm/fume/values.prod.yaml \
  --namespace fume-prod \
  --set image.backend.tag=1.8.0 \
  --set image.frontend.tag=2.1.3 \
  --set configMap.FUME_SERVER_URL="https://fume-api.company.com" \
  --set configMap.CANONICAL_BASE_URL="https://fume.your-company.com" \
  --set configMap.FHIR_PACKAGES="<org-specific-packages>"
```

### FHIR Server Integration Examples

#### With Basic Authentication
```yaml
env:
  FHIR_SERVER_AUTH_TYPE: "BASIC"

# In secrets:
# FHIR_SERVER_BASE: "https://your-fhir-server.com/fhir"
# FHIR_SERVER_UN: "fhir-username"
# FHIR_SERVER_PW: "fhir-password"
```

#### Without Authentication
```yaml
env:
  FHIR_SERVER_AUTH_TYPE: "NONE"

# In secrets:
# FHIR_SERVER_BASE: "https://public-fhir-server.com/fhir"
```

### Custom Environment Variables

#### Backend (FUME Engine) Configuration

Non-secret environment variables (in `values.yaml`; override in `values.prod.yaml`):
```yaml
env:
  SERVER_PORT: "42420"           # Port the engine exposes (default: 42420)
  FHIR_VERSION: "4.0.1"          # FHIR version (default: 4.0.1)
  FHIR_SERVER_AUTH_TYPE: "NONE"  # BASIC or NONE (default: NONE)
```

**Required ConfigMap values** (must be provided during deployment):
```bash
# These values MUST be set when installing the chart
--set configMap.CANONICAL_BASE_URL="https://fume.your-company.com" \
--set configMap.FHIR_PACKAGES="<org-specific-packages>"
```

Secret environment variables (in `fume-secrets`):
```bash
kubectl create secret generic fume-secrets \
  --from-literal=FHIR_SERVER_BASE="https://your-fhir-server.com/fhir" \
  --from-literal=FHIR_SERVER_UN="username" \      # Required if FHIR_SERVER_AUTH_TYPE=BASIC
  --from-literal=FHIR_SERVER_PW="password" \      # Required if FHIR_SERVER_AUTH_TYPE=BASIC
  --namespace fume
```

#### Frontend (FUME Designer) Configuration

Non-secret environment variables (in `values.yaml`; override in `values.prod.yaml`):
```yaml
env:
  FUME_DESIGNER_HEADLINE: "FUME Designer - DEV"  # Page title/environment indicator
```

**Required ConfigMap values** (must be provided during deployment):
```bash
# This value MUST be set when installing the chart
--set configMap.FUME_SERVER_URL="https://fume-api.company.com"
```

**Important Note on FUME_SERVER_URL**: This URL is used by the user's browser (not the Designer container) to communicate with the FUME Engine. It should be:
- The external/public URL if using Ingress
- `http://localhost:42420` for local development with port-forwarding  
- The appropriate LoadBalancer or NodePort URL for your setup

#### FHIR Packages Configuration

FUME installs specific FHIR packages on startup. You must supply the package list for your context (organization/jurisdiction specific). Examples:

```yaml
configMap:
  FHIR_PACKAGES: "us.core.r4@6.1.0,fhir.tx.support.r4,hl7.fhir.us.mcode@2.1.0"
# or
configMap:
  FHIR_PACKAGES: "il.core.fhir.r4@0.17.5,fhir.tx.support.r4,fume.outburn.r4@0.1.0"
```

Notes:
- Provide a comma-separated list. Versions are optional but recommended (pkg@version).
- Leave it unset to fail fast with a clear validation error.


### Version tracking labels

The chart adds labels that allow tracking what is deployed:
- helm.sh/chart: <chart>-<version>
- app.kubernetes.io/version: Chart appVersion (backend release)
- app.kubernetes.io/component: backend | frontend
- app.kubernetes.io/component-version: container image tag for the component
- fume.outburn.dev/image: image identifier derived from repo:tag (normalized for label constraints: lowercased; '/' ':' '@' replaced with '-'; may be truncated to 63 chars)
- fume.outburn.dev/tag: container image tag (normalized for label constraints)
- app.kubernetes.io/name, app.kubernetes.io/instance, app.kubernetes.io/managed-by

Note: If you need the exact, unsanitized image reference, query the container spec:

```bash
kubectl -n <ns> get deploy <name> -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Label namespace note: The `fume.outburn.dev/*` prefix is a custom label namespace based on the Outburn domain. The `.dev` here is part of the domain name, not an indicator of a development environment. These labels are used across all environments (dev/test/prod).

Examples to query deployed versions:

```bash
# Backend image and tag (Deployment labels)
kubectl -n fume get deploy fume-backend \
  -o jsonpath='{.metadata.labels.fume\.outburn\.dev/image}{"\n"}{.metadata.labels.app\.kubernetes\.io/component-version}{"\n"}'

# Frontend image and tag (Deployment labels)
kubectl -n fume get deploy fume-frontend \
  -o jsonpath='{.metadata.labels.fume\.outburn\.dev/image}{"\n"}{.metadata.labels.app\.kubernetes\.io/component-version}{"\n"}'

# List pods with component and image labels
kubectl -n fume get pods -l app.kubernetes.io/name=fume \
  -o custom-columns=NAME:.metadata.name,COMPONENT:.metadata.labels.app\.kubernetes\.io/component,IMAGE:.metadata.labels.fume\.outburn\.dev/image,TAG:.metadata.labels.app\.kubernetes\.io/component-version
```

#### License File Handling

FUME automatically scans for `*.lic` files in its root directory (`/usr/fume/` for backend, `/usr/fume-designer/` for frontend). The chart mounts the license file with a `.lic` extension, and FUME will:
- Automatically detect and use valid license files
- Ignore expired license files if multiple are present
- Not require the `FUME_LICENSE` environment variable when files are mounted
## Ingress Configuration

### Enable Ingress

```yaml
ingress:
  enabled: true
  className: "nginx"  # or "traefik", "alb", etc.
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/rate-limit: "100"
  hosts:
    - host: fume.company.com
      paths:
        - path: /api
          pathType: Prefix
          service: backend
        - path: /
          pathType: Prefix
          service: frontend  # Only if frontend enabled
  tls:
    - secretName: fume-tls
      hosts:
        - fume.company.com
```

## Auto-scaling Configuration

### Enable HPA (Horizontal Pod Autoscaler)

```yaml
autoscaling:
  backend:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 75
  
  frontend:
    enabled: true
    minReplicas: 1
    maxReplicas: 5
    targetCPUUtilizationPercentage: 80
```

## Monitoring and Health Checks

### Health Check Configuration

```yaml
probes:
  backend:
    liveness:
      enabled: true
      path: /health
      initialDelaySeconds: 30
      periodSeconds: 10
    readiness:
      enabled: true
      path: /health
      initialDelaySeconds: 5
      periodSeconds: 5
```

## Upgrading

Important upgrade note (major versions): the backend workload type changed from `StatefulSet` to `Deployment`. This is not always an in-place Helm upgrade.

- Migration guide: `fume-deployments/MIGRATING_TO_FUME_MAJOR.md`
- Env var matrix (self-contained): `fume-deployments/ENVIRONMENT_VARIABLES.md`

### Upgrade the Release

```bash
# Upgrade with new image version
helm upgrade fume ./helm/fume \
  --namespace fume \
  --set image.backend.tag=1.8.0 \
  --set image.frontend.tag=2.1.4

# Upgrade with new values file
helm upgrade fume ./helm/fume \
  -f ./helm/fume/values.prod.yaml \
  --namespace fume

### FHIR Package Cache & Registry (New in Chart 0.3.0 / App 1.8.0)

The backend now uses a fixed cache path: `/usr/fume/fhir-packages` exposed via the env var `FHIR_PACKAGE_CACHE_DIR` which the chart sets automatically. Do NOT override this variable.

Behavior:
- Persistent PVC mounted when `storage.fhirCache.enabled=true` (or `existingClaim` specified) providing `/usr/fume/fhir-packages` contents
- Ephemeral `emptyDir` mounted when `storage.fhirCache.enabled=false`

Optional private registry support:
- `configMap.FHIR_PACKAGE_REGISTRY_URL` (non-secret) 	Base URL of internal registry
- `FHIR_PACKAGE_REGISTRY_TOKEN` (secret) 	Add key to the `secrets.fume` Secret if auth required

Example (Windows cmd):
```cmd
kubectl create secret generic fume-secrets ^
  --from-literal=FHIR_SERVER_BASE="https://your-fhir-server.com/fhir" ^
  --from-literal=FHIR_PACKAGE_REGISTRY_TOKEN="s3cr3t-token" ^
  --namespace fume

helm upgrade --install fume ./helm/fume ^
  --namespace fume ^
  --set image.backend.tag=1.8.0 ^
  --set configMap.CANONICAL_BASE_URL="https://fume.your-company.com" ^
  --set configMap.FHIR_PACKAGES="<org-specific-packages>" ^
  --set configMap.FHIR_PACKAGE_REGISTRY_URL="https://packages.your-company.com"
```

Verification:
```cmd
kubectl -n fume exec deploy/fume-backend -- printenv FHIR_PACKAGE_CACHE_DIR
kubectl -n fume exec deploy/fume-backend -- printenv FHIR_PACKAGE_REGISTRY_URL
kubectl -n fume exec deploy/fume-backend -- ls -la /usr/fume/fhir-packages | head
```
```

### Check Upgrade Status

```bash
# Check release status
helm status fume --namespace fume

# Check rollout status
kubectl rollout status deployment/fume-backend --namespace fume
kubectl rollout status deployment/fume-frontend --namespace fume  # if enabled
```

## Troubleshooting

### Common Issues

#### 1. License File Issues
```bash
# Check if license secret exists
kubectl get secret fume-license --namespace fume

# Check license file content
kubectl get secret fume-license -o yaml --namespace fume

# Verify license is mounted correctly
kubectl exec -it deployment/fume-backend --namespace fume -- ls -la /usr/fume/
```

#### 2. Storage Issues
```bash
# Check PVC status
kubectl get pvc --namespace fume

# Check storage class availability
kubectl get storageclass

# Check volume mounts
kubectl describe pod -l app.kubernetes.io/component=backend --namespace fume
```

#### 3. Service Discovery Issues
```bash
# Check services
kubectl get svc --namespace fume

# Test backend connectivity
kubectl port-forward svc/fume-backend 42420:42420 --namespace fume
# Then visit http://localhost:42420

# Test frontend connectivity (if enabled)
kubectl port-forward svc/fume-frontend 3000:3000 --namespace fume
# Then visit http://localhost:3000
```

#### 4. Image Pull Issues
```bash
# Check if Docker Hub secret is configured and valid (if you created one)
kubectl get secret dockerhub-secret --namespace fume
kubectl describe secret dockerhub-secret --namespace fume

# Verify secret is properly referenced in deployment (if using image.pullSecret)
kubectl describe deployment fume-backend --namespace fume | grep -A5 "Image Pull Secrets"

# If relying on namespace/service account level credentials, check imagePullSecrets there
kubectl get serviceaccount default -n fume -o yaml | grep -A3 imagePullSecrets

# Check pod events for image pull errors
kubectl describe pod -l app.kubernetes.io/name=fume --namespace fume

# Test Docker Hub connectivity (replace with actual image)
kubectl run test-pull --image=outburnltd/fume-enterprise-server:1.8.0 --image-pull-policy=Always --rm -it --restart=Never --namespace fume
```

#### 5. x509 / certificate trust errors

Symptoms: Errors like `x509: certificate signed by unknown authority` when the backend tries to access HTTPS endpoints.

What to check:
- If your organization uses a custom/corporate CA, create a CA bundle Secret and enable `tls.customCA.enabled=true` (see section above).
- If using the cluster's ServiceAccount CA, ensure defaults are in effect (`tls.useServiceAccountCA=true`).
- Verify the PEM file contains only certificates (no private keys).
- Confirm the environment variable is set in the pod:

```cmd
kubectl -n fume exec deploy/fume-backend -- printenv NODE_EXTRA_CA_CERTS
```

### Logs

```bash
# Backend logs
kubectl logs -l app.kubernetes.io/component=backend --namespace fume -f

# Frontend logs (if enabled)
kubectl logs -l app.kubernetes.io/component=frontend --namespace fume -f

# Previous container logs (if pod crashed)
kubectl logs -l app.kubernetes.io/component=backend --namespace fume --previous
```


## Uninstalling

### Remove the Release

```bash
# Uninstall the Helm release
helm uninstall fume --namespace fume

# Remove PVCs (data will be lost!)
kubectl delete pvc --all --namespace fume

# Remove secrets (if no longer needed)
kubectl delete secret fume-license fume-secrets --namespace fume
# If you created a Docker Hub pull secret for this namespace, remove it as well
kubectl delete secret dockerhub-secret --namespace fume

# Remove namespace (optional)
kubectl delete namespace fume
```

## Support

For issues related to:
- **Helm Chart**: Contact your DevOps team or chart maintainer
- **FUME Application**: Refer to FUME Enterprise documentation
- **Kubernetes**: Check your cluster administrator

## Values Reference

For a complete list of configurable values, see:
- `values.yaml` - Default configuration
- `values.prod.yaml` - Production overrides

Key configuration sections:
- `image.*` - Container image settings
- `backend.*` - Backend deployment configuration
- `frontend.*` - Frontend deployment configuration
- `service.*` - Service configuration
- `storage.*` - Persistent storage settings
- `env.*` - Environment variables
- `configMap.*` - Non-secret configuration
- `secrets.*` - Secret references
- `ingress.*` - Ingress configuration
- `autoscaling.*` - Auto-scaling settings
