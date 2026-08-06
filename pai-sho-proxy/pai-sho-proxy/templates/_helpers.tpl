{{/*
Expand the name of the chart.
*/}}
{{- define "pai-sho-proxy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "pai-sho-proxy.fullname" -}}
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
{{- define "pai-sho-proxy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pai-sho-proxy.labels" -}}
helm.sh/chart: {{ include "pai-sho-proxy.chart" . }}
{{ include "pai-sho-proxy.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pai-sho-proxy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pai-sho-proxy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the PVC holding the pai-sho identity key.

Deliberately overridable and defaulted separately from fullname: the release was
renamed from llama-hmnd-client to pai-sho-proxy, and the PVC holds a private key
whose PV has reclaimPolicy Delete. Pointing the new release at the EXISTING claim
name avoids provisioning an empty volume and losing the tunnel identity.
*/}}
{{- define "pai-sho-proxy.stateClaimName" -}}
{{- .Values.persistence.existingClaim | default (printf "%s-state" (include "pai-sho-proxy.fullname" .)) }}
{{- end }}

{{/*
Validate the ports list once, so a bad mode fails at render time rather than
producing an haproxy.cfg that crashloops.
*/}}
{{- define "pai-sho-proxy.validatePorts" -}}
{{- if not .Values.ports }}
{{- fail "ports is empty: pai-sho-proxy needs at least one port to route" }}
{{- end }}
{{- range .Values.ports }}
{{- if not .port }}
{{- fail (printf "ports entry %v is missing 'port'" .name) }}
{{- end }}
{{- if not (has (.mode | default "http") (list "http" "tcp")) }}
{{- fail (printf "ports entry %v has mode %q; must be 'http' or 'tcp'" .port .mode) }}
{{- end }}
{{- end }}
{{- end }}
