{{/* Helper templates for frontend chart */}}
{{- define "frontend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 -}}
{{- end -}}

{{- define "frontend.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if .Release.Name -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 -}}
{{- else -}}
{{- $name | trunc 63 -}}
{{- end -}}
{{- end -}}

{{- define "frontend.labels" -}}
app.kubernetes.io/name: {{ include "frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "frontend.selectorLabels" -}}
app: {{ include "frontend.fullname" . }}
{{- end -}}

{{- /* Helper to compute checksum of config to trigger rolling updates */ -}}
{{- define "frontend.configChecksum" -}}
{{- $cfg := dict "config" .Values.config "env" .Values.env -}}
{{- sha256sum (toJson $cfg) -}}
{{- end -}}
