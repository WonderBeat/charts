{{/*
Expand the name of the chart.
*/}}
{{- define "hattid.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "hattid.fullname" -}}
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
{{- define "hattid.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "hattid.labels" -}}
helm.sh/chart: {{ include "hattid.chart" . }}
{{ include "hattid.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "hattid.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hattid.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "hattid.web.labels" -}}
helm.sh/chart: {{ include "hattid.chart" . }}-web
{{ include "hattid.web.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "hattid.web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hattid.name" . }}-web
app.kubernetes.io/instance: {{ .Release.Name }}-web
{{- end }}

{{- define "hattid.loader.labels" -}}
helm.sh/chart: {{ include "hattid.chart" . }}-loader
{{ include "hattid.loader.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "hattid.loader.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hattid.name" . }}-loader
app.kubernetes.io/instance: {{ .Release.Name }}-loader
{{- end }}

{{- define "hattid.front.labels" -}}
helm.sh/chart: {{ include "hattid.chart" . }}-front
{{ include "hattid.front.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "hattid.front.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hattid.name" . }}-front
app.kubernetes.io/instance: {{ .Release.Name }}-front
{{- end }}
