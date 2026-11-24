{{/*
Labels for the objects this chart creates itself. app.kubernetes.io/instance
is the install name, so the Application selects these objects.
*/}}
{{- define "spacelift-mp.labels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
A release version (X.Y.Z, or X.Y.Z-gcp.N for a change to the deployer alone)
as a string that sorts like the version: 7.2.0 < 7.2.0-gcp.1 < 7.2.1.
Semver would put 7.2.0-gcp.1 before 7.2.0, so semverCompare can't be used.
Usage: include "spacelift-mp.versionKey" "7.2.0-gcp.1"
*/}}
{{- define "spacelift-mp.versionKey" -}}
{{- if not (regexMatch "^[0-9]+\\.[0-9]+\\.[0-9]+(-gcp\\.[0-9]+)?$" .) -}}
{{- fail (printf "unexpected version %q, want X.Y.Z or X.Y.Z-gcp.N" .) -}}
{{- end -}}
{{- $parts := splitList "." (regexReplaceAll "-gcp\\.[0-9]+$" . "") -}}
{{- $gcp := 0 -}}
{{- if contains "-gcp." . }}{{ $gcp = regexReplaceAll "^.*-gcp\\." . "" | atoi }}{{ end -}}
{{- printf "%06d.%06d.%06d.%06d" (index $parts 0 | atoi) (index $parts 1 | atoi) (index $parts 2 | atoi) $gcp -}}
{{- end }}

{{/*
A form value that a full install can't work without.
Usage: include "spacelift-mp.required" (list .Values.database.name "database.name")
*/}}
{{- define "spacelift-mp.required" -}}
{{- $value := index . 0 -}}
{{- $field := index . 1 -}}
{{- required (printf "the form field %q is empty, but Spacelift needs it" $field) $value -}}
{{- end }}

{{/*
Postgres URL for Cloud SQL through the cloud-sql-proxy sidecar, with IAM login.
*/}}
{{- define "spacelift-mp.databaseURL" -}}
{{- $user := include "spacelift-mp.required" (list .Values.database.user "database.user") -}}
{{- $name := include "spacelift-mp.required" (list .Values.database.name "database.name") -}}
{{- printf "postgres://%s@127.0.0.1/%s" (urlquery $user) $name -}}
{{- end }}
