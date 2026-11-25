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

{{/*
Parse an HAProxy duration ("30s", "10m", "1h", "500ms", bare = ms) to seconds.

Needed because the timeout ORDERING is the thing that matters, and comparing
the raw strings would rank "30s" above "10m" lexically. HAProxy accepts a bare
number as milliseconds, so that case is handled explicitly rather than guessed.
*/}}
{{- define "pai-sho-proxy.toSeconds" -}}
{{- $v := . | toString | trim -}}
{{- if hasSuffix "ms" $v -}}
{{- divf (trimSuffix "ms" $v | float64) 1000.0 -}}
{{- else if hasSuffix "s" $v -}}
{{- trimSuffix "s" $v | float64 -}}
{{- else if hasSuffix "m" $v -}}
{{- mulf (trimSuffix "m" $v | float64) 60.0 -}}
{{- else if hasSuffix "h" $v -}}
{{- mulf (trimSuffix "h" $v | float64) 3600.0 -}}
{{- else if hasSuffix "d" $v -}}
{{- mulf (trimSuffix "d" $v | float64) 86400.0 -}}
{{- else if regexMatch "^[0-9.]+$" $v -}}
{{- divf ($v | float64) 1000.0 -}}
{{- else -}}
{{- fail (printf "cannot parse duration %q; use HAProxy units (ms, s, m, h, d)" $v) -}}
{{- end -}}
{{- end }}

{{/*
Validate the timeout relationships that caused real outages.

These are ORDERING invariants, not value preferences, and each one failed in
production before it was written down. A plain values.yaml comment did not
prevent that, so the render fails instead.
*/}}
{{- define "pai-sho-proxy.validateTimeouts" -}}
{{- $t := .Values.proxy.timeouts -}}
{{- $ka := include "pai-sho-proxy.toSeconds" (required "proxy.timeouts.httpKeepAlive is required: unset, HAProxy silently falls back to timeout http-request and closes idle client connections early" $t.httpKeepAlive) | float64 -}}
{{- $req := include "pai-sho-proxy.toSeconds" $t.httpRequest | float64 -}}
{{- if le $ka $req -}}
{{- fail (printf "proxy.timeouts.httpKeepAlive (%v) must be GREATER than httpRequest (%v): HAProxy would close idle client connections sooner than clients expect, and a client reusing a pooled connection then fails with \"use of closed network connection\"" $t.httpKeepAlive $t.httpRequest) -}}
{{- end -}}
{{- /* 90s is Go's default http.Transport.IdleConnTimeout, i.e. the floor for
       any Go client (gomodel) reusing pooled connections through this proxy. */ -}}
{{- if lt $ka 90.0 -}}
{{- fail (printf "proxy.timeouts.httpKeepAlive (%v) is below 90s, the default idle-pool timeout of Go's http.Transport: a Go client would keep a connection HAProxy already closed and fail non-replayable POSTs" $t.httpKeepAlive) -}}
{{- end -}}
{{- $tun := include "pai-sho-proxy.toSeconds" (required "proxy.timeouts.tunnel is required" $t.tunnel) | float64 -}}
{{- $srv := include "pai-sho-proxy.toSeconds" $t.server | float64 -}}
{{- if gt $tun $srv -}}
{{- fail (printf "proxy.timeouts.tunnel (%v) exceeds server (%v): a wedged stream would outlive the request timeout meant to bound it" $t.tunnel $t.server) -}}
{{- end -}}
{{- /* With backendMaxconn set, requests really do queue in HAProxy, so the
       queue timeout stops being decorative: too low and a request 503s while
       waiting behind a healthy generation. Measured generations reach ~137s. */ -}}
{{- $bm := .Values.proxy.backendMaxconn | default 0 | int -}}
{{- if gt $bm 0 -}}
{{- $q := include "pai-sho-proxy.toSeconds" $t.queue | float64 -}}
{{- if lt $q 100.0 -}}
{{- fail (printf "proxy.timeouts.queue (%v) is under 5m while proxy.backendMaxconn=%v serialises requests: a queued request would 503 waiting behind a healthy generation (measured up to ~137s each)" $t.queue $bm) -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
pai-sho release tarball URL.

Derived from paiSho.version + paiSho.arch rather than written out, because the
version appears TWICE in a GitHub release URL (once as the tag directory, once
in the filename). Bumping only the filename yields a 404 that surfaces as a
crashlooping sidecar rather than a render error. paiSho.downloadUrl still
overrides for a fork or local mirror.
*/}}
{{- define "pai-sho-proxy.paiShoUrl" -}}
{{- with .Values.paiSho.downloadUrl -}}
{{- . -}}
{{- else -}}
{{- $v := required "paiSho.version is required unless paiSho.downloadUrl is set" .Values.paiSho.version -}}
{{- $arch := required "paiSho.arch is required unless paiSho.downloadUrl is set" .Values.paiSho.arch -}}
{{- if not (hasPrefix "v" $v) -}}
{{- fail (printf "paiSho.version must start with 'v' (got %q); the release tag and filename both use the v-prefixed form" $v) -}}
{{- end -}}
{{- printf "https://github.com/cablehead/pai-sho/releases/download/%s/pai-sho-%s-%s.tar.gz" $v $v $arch -}}
{{- end -}}
{{- end }}
