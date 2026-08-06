{{/*
Resolve the active GPU profile: .Values.profiles[.Values.gpuProfile] merged over
the shared .Values.server defaults.

Profile-specific numbers live in structured keys (model, contextSize, parallel,
cpuMoeLayers, ...) rather than inside the extraArgs list on purpose. Helm cannot
merge two YAML lists, so a list-based override would have forced every profile
to restate the whole heavily-annotated sampling block, and the two copies would
have drifted the first time one of them was tuned.
*/}}
{{- define "llama-hmnd-server.server" -}}
{{- $profile := dict -}}
{{- if .Values.gpuProfile -}}
  {{- $profile = index .Values.profiles .Values.gpuProfile -}}
  {{- if not $profile -}}
    {{- fail (printf "gpuProfile %q has no entry under .Values.profiles (have: %s)" .Values.gpuProfile (join ", " (keys .Values.profiles))) -}}
  {{- end -}}
  {{- $profile = $profile.server | default dict -}}
{{- end -}}
{{- toYaml (mergeOverwrite (deepCopy .Values.server) (deepCopy $profile)) -}}
{{- end }}

{{/*
Resources for the active profile, merged the same way.
*/}}
{{- define "llama-hmnd-server.resources" -}}
{{- $profile := dict -}}
{{- if .Values.gpuProfile -}}
  {{- $profile = (index .Values.profiles .Values.gpuProfile).resources | default dict -}}
{{- end -}}
{{- toYaml (mergeOverwrite (deepCopy .Values.resources) (deepCopy $profile)) -}}
{{- end }}

{{/*
Pod affinity for the active profile.

The 2gpu profile pins all replicas of this release onto a single node. Nodes here
carry 8 GPUs, so a 2-GPU deployment is one pod holding both GPUs, and that pod is
trivially "on one node". This affinity matters for the case where replicaCount is
raised later: without it the scheduler is free to scatter replicas across nodes,
and two half-loaded nodes cannot serve a model that needs both GPUs' VRAM.
*/}}
{{- define "llama-hmnd-server.affinity" -}}
{{- $profile := dict -}}
{{- if .Values.gpuProfile -}}
  {{- $profile = (index .Values.profiles .Values.gpuProfile).affinity | default dict -}}
{{- end -}}
{{- $affinity := mergeOverwrite (deepCopy .Values.affinity) (deepCopy $profile) -}}
{{- if $affinity -}}
{{- toYaml $affinity -}}
{{- end -}}
{{- end }}
