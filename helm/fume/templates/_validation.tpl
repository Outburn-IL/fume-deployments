{{/*
Validate required configuration values
*/}}
{{- if not .Values.configMap.CANONICAL_BASE_URL }}
{{- fail "CANONICAL_BASE_URL is required. Please set it via --set configMap.CANONICAL_BASE_URL=\"https://fume.your-company.com\"" }}
{{- end }}

{{- if not .Values.configMap.FUME_SERVER_URL }}
{{- fail "FUME_SERVER_URL is required. Please set it via --set configMap.FUME_SERVER_URL=\"https://your-fume-api.com\"" }}
{{- end }}

{{- if not .Values.secrets.fume }}
{{- fail "Application secrets name is required. Please ensure you have created the 'fume-secrets' secret or update values.yaml" }}
{{- end }}

{{- if not .Values.secrets.license }}
{{- fail "License secret name is required. Please ensure you have created the 'fume-license' secret or update values.yaml" }}
{{- end }}
