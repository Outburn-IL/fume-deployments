# Migrating to the new major FUME Enterprise Helm deployment

This guide is for platform/DevOps teams upgrading from the previous enterprise Helm deployment to the new major FUME release after the toolchain refactor.

## What changed (high level)

- **Configuration surface changed**: environment variables were added/removed/renamed.
  - See `ENVIRONMENT_VARIABLES.md` in this repo for the supported variables.
- **Backend workload type is changing**: the enterprise backend is moving from a **StatefulSet** model to a **Deployment** model.
- **Shared caches are now supported and recommended**:
  - FHIR package cache
  - Templates cache
  - New optional mappings folder (file-backed mappings store)
  - Snapshot/terminology caches now live under the FHIR package cache volume (no separate snapshots volume)

## Pre-migration checklist

1) Identify your currently deployed release

```bash
helm list -n <namespace>
helm get values <release> -n <namespace>
```

2) Inventory your current storage

```bash
kubectl get pvc -n <namespace>
kubectl get statefulset,deploy -n <namespace>
```

If you are currently using the chart’s per-pod PVCs (StatefulSet `volumeClaimTemplates`), you will likely see PVCs with names like:

- `<release>-fume-backend-templates-0`
- `<release>-fume-backend-fhir-cache-0`

Note: older deployments may also have had a snapshots PVC/mount. In the new major, snapshots are cached under the package cache volume, so there is no dedicated snapshots PVC.

3) Confirm your cluster supports RWX if you plan to run multiple backend replicas

To share a single PVC between multiple pods, your storage backend must support `ReadWriteMany` (RWX) (examples: NFS, EFS, AzureFile).

If you only have `ReadWriteOnce` (RWO), pick one:

- run a single backend replica, or
- keep the StatefulSet pattern, or
- accept per-pod caches using `emptyDir`.

## Configuration migration (env vars)

### Source of truth

Use `ENVIRONMENT_VARIABLES.md` in this repo as the authoritative list of supported environment variables.

### How env vars are provided in Helm

Most enterprise installations should split variables into:

- **ConfigMap values** (non-secret but important): e.g. `CANONICAL_BASE_URL`, `FHIR_PACKAGES`, `FHIR_PACKAGE_REGISTRY_URL`
- **Secret values** (sensitive): e.g. `FHIR_SERVER_BASE`, `FHIR_SERVER_UN`, `FHIR_SERVER_PW`, `FHIR_PACKAGE_REGISTRY_TOKEN`
- **Plain env values**: e.g. `LOG_LEVEL`, `FHIR_SERVER_TIMEOUT`, `PREBUILD_SNAPSHOTS`, `MAPPINGS_*` settings

### Common new/updated settings (examples)

- Request limits and logging:
  - `FUME_REQUEST_BODY_LIMIT`
  - `LOG_LEVEL`
- Evaluation policy thresholds:
  - `FUME_EVAL_THROW_LEVEL`
  - `FUME_EVAL_LOG_LEVEL`
  - `FUME_EVAL_DIAG_COLLECT_LEVEL`
  - `FUME_EVAL_VALIDATION_LEVEL`
- Cache warmup:
  - `PREBUILD_SNAPSHOTS` (enterprise default is usually `true`)
- Mapping provider file store (optional):
  - `MAPPINGS_FOLDER`
  - `MAPPINGS_PRIMARY_WRITABLE_STORE` (`file` / `server` / `none`)

## Storage migration

### Goal

Move from per-pod PVCs (StatefulSet) to shared PVCs (Deployment) for the following safe-to-share folders:

- `/usr/fume/fhir-packages` (FHIR package cache)
- `/usr/fume/templates` (templates cache)
- `/usr/fume/mappings` (optional; file-backed mappings)

Snapshot + terminology caches are stored under the package cache folder (`/usr/fume/fhir-packages`).

### Strategy options

#### Option A — Parallel install + cutover (recommended)

1) Install the new chart under a new release name (same namespace or a new namespace).
2) Validate health checks, API behavior, and (if applicable) designer connectivity.
3) Switch traffic (Ingress host/path, or Service selector changes depending on your setup).
4) Decommission old release.

Pros: lowest risk, easiest rollback.

#### Option B — In-place upgrade with data copy

This option is more manual but keeps the same release name.

1) Scale down old backend

```bash
kubectl scale statefulset/<old-backend> -n <namespace> --replicas=0
```

2) Create the new shared PVCs (RWX)

Create PVCs for the new Deployment-based chart (names depend on the updated chart). Examples:

- `<release>-fhir-cache`
- `<release>-templates`
- `<release>-mappings` (optional)

3) Copy data from old per-pod PVCs into the new shared PVCs

The most reliable pattern is a temporary helper pod per PVC.

Example helper pod (edit `claimName` and mountPath per volume):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pvc-migrator
  namespace: <namespace>
spec:
  containers:
    - name: shell
      image: alpine:3.20
      command: ["/bin/sh","-c","sleep 36000"]
      volumeMounts:
        - name: old
          mountPath: /old
        - name: new
          mountPath: /new
  volumes:
    - name: old
      persistentVolumeClaim:
        claimName: <old-pvc-name>
    - name: new
      persistentVolumeClaim:
        claimName: <new-pvc-name>
```

Then inside the pod:

```bash
kubectl exec -it pvc-migrator -n <namespace> -- sh

# Example copy (preserve timestamps/permissions where possible)
cp -a /old/. /new/
```

4) Upgrade the Helm release

Depending on how the chart is updated (StatefulSet → Deployment), you may need to delete the old StatefulSet object before Helm can create the Deployment.

## StatefulSet → Deployment caveats

- Helm cannot always “mutate” a StatefulSet into a Deployment cleanly.
- Expect at least one disruptive operation (delete/create) for the backend workload.
- Plan a maintenance window.

## Post-migration verification

1) Verify pods

```bash
kubectl get pods -n <namespace>
kubectl logs -n <namespace> deploy/<backend-deploy> --tail=200
```

2) Verify env

```bash
kubectl exec -n <namespace> deploy/<backend-deploy> -- printenv | sort
```

3) Verify mounted caches

```bash
kubectl exec -n <namespace> deploy/<backend-deploy> -- ls -la /usr/fume/fhir-packages | head
kubectl exec -n <namespace> deploy/<backend-deploy> -- ls -la /usr/fume/templates | head
kubectl exec -n <namespace> deploy/<backend-deploy> -- ls -la /usr/fume/mappings | head  # if enabled

```

## License note

License files are safe to share between pods. Prefer mounting the license from a Kubernetes Secret to each pod (no per-pod state required).

## Rollback

- If you used the parallel install approach, rollback is typically just switching traffic back.
- If you upgraded in-place, rollback may require restoring the previous manifests and re-attaching old PVCs.
