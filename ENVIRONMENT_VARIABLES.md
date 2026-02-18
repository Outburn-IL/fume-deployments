# FUME Enterprise environment variables (self-contained)

This document lists the supported environment variables for FUME Enterprise deployments.

It is intentionally self-contained so it can be shipped to customers without requiring access to any private repositories.

## Conventions

- **Runtime required?** means the config schema rejects startup when missing.
  - Many variables are still *operationally required* for production even if they have defaults.
- **Recommended K8s source** is how we suggest injecting the variable when using Helm.
- **Secret?** indicates whether the value should normally be stored in a Kubernetes Secret.

Additional operator notes:

- Several settings support the sentinel value `n/a` to mean “disabled” (notably `FHIR_SERVER_BASE`, `FHIR_PACKAGE_REGISTRY_URL`, and `MAPPINGS_FOLDER`).
- Empty/whitespace values should be treated as “unset”.
- When both `FHIR_SERVER_BASE` and `MAPPINGS_FOLDER` are unset/`n/a`, the `/Mapping/*` endpoints are disabled (return `405`), but ad-hoc `POST /` evaluation remains available.

## Backend (FUME Engine / Server)

| Variable | Runtime required? | Default (if any) | Recommended K8s source | Secret? | Notes |
|---|---:|---|---|---:|---|
| `SERVER_PORT` | No | `42420` | values.env | No | Port the backend listens on. Typically matches Service targetPort. |
| `FUME_REQUEST_BODY_LIMIT` | No | `400mb` | values.env | No | Max request body size accepted by the HTTP server (json/xml/csv/hl7v2). Examples: `10mb`, `100kb`, `1gb`. |
| `LOG_LEVEL` | No | `info` | values.env | No | Global logging verbosity. Accepts `debug`/`info`/`warn`/`error`/`silent` (`silent` also accepts aliases like `off`). |

### Evaluation policy thresholds (fumifier)

Numeric severities (lower = more critical): fatal=0, invalid=10, error=20, warning=30, notice=40, info=50, debug=60.
Threshold comparisons are exclusive: an action triggers when `severity < threshold`.

| Variable | Runtime required? | Default (if any) | Recommended K8s source | Secret? | Notes |
|---|---:|---|---|---:|---|
| `FUME_EVAL_THROW_LEVEL` | No | `30` | values.env | No | When severity is below this, evaluation throws. |
| `FUME_EVAL_LOG_LEVEL` | No | `40` | values.env | No | Controls per-evaluation policy logging threshold. |
| `FUME_EVAL_DIAG_COLLECT_LEVEL` | No | `70` | values.env | No | Diagnostic collection threshold. |
| `FUME_EVAL_VALIDATION_LEVEL` | No | `30` | values.env | No | Validation threshold. |

### FHIR server connection

| Variable | Runtime required? | Default (if any) | Recommended K8s source | Secret? | Notes |
|---|---:|---|---|---:|---|
| `FHIR_SERVER_BASE` | No | `""` | secrets.fume | Usually | FHIR server base URL. Set to `n/a` to disable server source. |
| `FHIR_SERVER_AUTH_TYPE` | No | `NONE` | values.env | No | `NONE` or `BASIC`. |
| `FHIR_SERVER_UN` | No | `""` | secrets.fume | Yes | BASIC username. |
| `FHIR_SERVER_PW` | No | `""` | secrets.fume | Yes | BASIC password. |
| `FHIR_SERVER_TIMEOUT` | No | `30000` | values.env | No | Timeout in ms for FHIR server calls. |

### FHIR packages and registries

| Variable | Runtime required? | Default (if any) | Recommended K8s source | Secret? | Notes |
|---|---:|---|---|---:|---|
| `FHIR_VERSION` | No | `4.0.1` | values.env | No | Default FHIR version. |
| `FHIR_PACKAGES` | No | `""` | values.configMap | No | Comma-separated list of `pkg@version`. Operationally required for most deployments. |
| `FHIR_PACKAGE_REGISTRY_URL` | No | (none) | values.configMap | No | Optional. Supports `n/a`. |
| `FHIR_PACKAGE_REGISTRY_TOKEN` | No | (none) | secrets.fume | Yes | Optional auth token for private registry (base64-encoded, no `Bearer`). |
| `FHIR_PACKAGE_CACHE_DIR` | No | (none) | chart-managed | No | In Helm, prefer the fixed mount `/usr/fume/fhir-packages`. If overriding, mounts must follow. |

### Mappings file store (optional)

| Variable | Runtime required? | Default (if any) | Recommended K8s source | Secret? | Notes |
|---|---:|---|---|---:|---|
| `MAPPINGS_FOLDER` | No | (none) | chart-managed when enabled | No | Set to a folder path to enable file-backed mappings + aliases. Set to `n/a` (or unset) to disable. |
| `MAPPINGS_FILE_EXTENSION` | No | (none) | values.env | No | Default is applied by provider; commonly `.fume`. |
| `MAPPINGS_FILE_POLLING_INTERVAL_MS` | No | (none) | values.env | No | Optional. Set <= 0 to disable interval (provider behavior). |
| `MAPPINGS_SERVER_POLLING_INTERVAL_MS` | No | (none) | values.env | No | Optional. |
| `MAPPINGS_FORCED_RESYNC_INTERVAL_MS` | No | (none) | values.env | No | Optional. |
| `MAPPINGS_PRIMARY_WRITABLE_STORE` | No | (none) | values.env | No | `file` / `server` / `none`. If `file`, `MAPPINGS_FOLDER` must be configured. |

### Cache warmup / performance

| Variable | Runtime required? | Default (if any) | Recommended K8s source | Secret? | Notes |
|---|---:|---|---|---:|---|
| `PREBUILD_SNAPSHOTS` | No | `true` | values.env | No | Warm snapshot + terminology caches in background. Caches are stored under the package cache volume (`FHIR_PACKAGE_CACHE_DIR`). |
| `FUME_COMPILED_EXPR_CACHE_MAX_ENTRIES` | No | `1000` | values.env | No | In-process cache size. Not shareable between pods. |
| `FUME_AST_CACHE_MAX_ENTRIES` | No | `1000` | values.env | No | In-process cache size. Not shareable between pods. |

### Canonical + license

| Variable | Runtime required? | Default (if any) | Recommended K8s source | Secret? | Notes |
|---|---:|---|---|---:|---|
| `CANONICAL_BASE_URL` | No | `http://example.fume.health` | values.configMap | No | Base URL used for generated canonicals. Many deployments treat this as required. |
| `FUME_LICENSE` | No | `""` | (not recommended) | No | Prefer mounting license file(s) from a Secret. License files are safe to share across pods. |

## Frontend (FUME Designer) — when deployed

These values are consumed by the Designer / browser.

| Variable | Required (if frontend enabled)? | Recommended K8s source | Secret? | Notes |
|---|---:|---|---:|---|
| `FUME_SERVER_URL` | Yes | values.configMap | No | URL that the user's browser uses to call the backend API. Must be reachable from the user's network.
| `FUME_DESIGNER_HEADLINE` | No | values.env | No | Cosmetic headline / environment marker.
