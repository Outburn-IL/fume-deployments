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
- Persistent Volume support (for snapshots and templates storage)
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
    tag: "1.7.1"
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
  snapshots:
    enabled: true
    size: 5Gi
    storageClass: "ssd"     # Use your preferred storage class
    accessMode: ReadWriteOnce
  
  templates:
    enabled: true
    size: 1Gi
    storageClass: "ssd"
    accessMode: ReadWriteOnce
```

### Storage Classes

Common storage class examples:
- AWS EKS: `gp2`, `gp3`, `io1`
- Google GKE: `standard`, `ssd`
- Azure AKS: `default`, `managed-premium`
- On-premise: Check with your cluster administrator

## Environment-Specific Deployments

### Development Environment

```bash
# Use default values with frontend enabled
helm install fume-dev ./helm/fume \
  --namespace fume-dev \
  --set image.backend.tag=1.7.1 \
  --set image.frontend.tag=2.1.3 \
  --set storage.snapshots.size=5Gi \
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
  --set image.backend.tag=1.7.1 \
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
  --set image.backend.tag=1.7.1 \
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
- fume.outburn.dev/image: full image reference (repo:tag)
- fume.outburn.dev/tag: container image tag
- app.kubernetes.io/name, app.kubernetes.io/instance, app.kubernetes.io/managed-by

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

#### Proxy Configuration (Optional)

```yaml
env:
  HTTP_PROXY: "http://proxy.company.com:8080"
  HTTPS_PROXY: "http://proxy.company.com:8080"
  NO_PROXY: "localhost,127.0.0.1,.company.com"

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
      path: /              # Adjust if FUME has specific health endpoint
      initialDelaySeconds: 30
      periodSeconds: 10
    readiness:
      enabled: true
      path: /
      initialDelaySeconds: 5
      periodSeconds: 5
```

## Upgrading

### Upgrade the Release

```bash
# Upgrade with new image version
helm upgrade fume ./helm/fume \
  --namespace fume \
  --set image.backend.tag=1.7.2 \
  --set image.frontend.tag=2.1.4

# Upgrade with new values file
helm upgrade fume ./helm/fume \
  -f ./helm/fume/values.prod.yaml \
  --namespace fume
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
kubectl run test-pull --image=outburnltd/fume-enterprise-server:1.7.1 --image-pull-policy=Always --rm -it --restart=Never --namespace fume
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

### Debug Mode

Enable debug logging:

```yaml
env:
  LOG_LEVEL: "debug"
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

## Chart Information

- **Chart Version**: 0.1.1
- **App Version**: 1.7.1
- **Kubernetes Version**: 1.19+
- **Helm Version**: 3.2.0+

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
