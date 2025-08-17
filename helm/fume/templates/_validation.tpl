{{/*
Validation is consolidated in the helper template.
This file now simply invokes the shared validation to retain compatibility if referenced directly.
*/}}
{{- include "fume.validation" . -}}
