{{/*
Expand the name of the chart.
*/}}
{{- define "fume.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "fume.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "fume.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "fume.labels" -}}
helm.sh/chart: {{ include "fume.chart" . }}
{{ include "fume.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "fume.selectorLabels" -}}
app.kubernetes.io/name: {{ include "fume.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "fume.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "fume.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Validate required configuration values
*/}}
{{- define "fume.validation" -}}
{{- if not .Values.configMap.CANONICAL_BASE_URL }}
{{- fail "CANONICAL_BASE_URL is required. Please set it via --set configMap.CANONICAL_BASE_URL=\"https://fume.your-company.com\"" }}
{{- end }}
{{- if not .Values.configMap.FUME_SERVER_URL }}
{{- fail "FUME_SERVER_URL is required. Please set it via --set configMap.FUME_SERVER_URL=\"https://your-fume-api.com\"" }}
{{- end }}
{{- if not .Values.configMap.FHIR_PACKAGES }}
{{- fail "FHIR_PACKAGES is required and must be provided by the deploying organization (context/jurisdiction specific). Example: --set configMap.FHIR_PACKAGES=\"pkg1@x.y.z,pkg2,pkg3@a.b.c\"" }}
{{- end }}
{{- if not .Values.secrets.fume }}
{{- fail "Application secrets name is required. Please ensure you have created the 'fume-secrets' secret or update values.yaml" }}
{{- end }}
{{- if not .Values.secrets.license }}
{{- fail "License secret name is required. Please ensure you have created the 'fume-license' secret or update values.yaml" }}
{{- end }}
{{- end }}

{{/*
Sanitize arbitrary strings into valid Kubernetes label values.
Rules:
 - Lowercase
 - Replace '/', ':', and '@' with '-'
 - Replace any other invalid chars with '-'
 - Trim leading/trailing non-alphanumerics
 - Truncate to 63 chars and ensure it ends with alphanumeric
Usage: {{ include "fume.labelValue" "some/raw:value" }}
*/}}
{{- define "fume.labelValue" -}}
{{- $raw := . -}}
{{- $v := lower $raw -}}
{{- $v = replace "/" "-" $v -}}
{{- $v = replace ":" "-" $v -}}
{{- $v = replace "@" "-" $v -}}
{{- /* Replace any remaining invalid characters */ -}}
{{- $v = regexReplaceAll "[^a-z0-9_.-]" $v "-" -}}
{{- /* Trim invalid start/end characters */ -}}
{{- $v = regexReplaceAll "^[^a-z0-9]+" $v "" -}}
{{- $v = regexReplaceAll "[^a-z0-9]+$" $v "" -}}
{{- /* Truncate and ensure it ends with an alphanumeric */ -}}
{{- $v = trunc 63 $v -}}
{{- $v = regexReplaceAll "[^a-z0-9]+$" $v "" -}}
{{- /* Fallback if empty after sanitization */ -}}
{{- if eq $v "" -}}
unknown
{{- else -}}
{{- $v -}}
{{- end -}}
{{- end }}
