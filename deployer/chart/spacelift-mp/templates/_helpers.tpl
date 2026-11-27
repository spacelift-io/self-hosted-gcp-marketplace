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
Cloud SQL names the IAM user of a service account after its email without
".gserviceaccount.com", so the suffix is removed if the form has the full email.
*/}}
{{- define "spacelift-mp.databaseURL" -}}
{{- $user := include "spacelift-mp.required" (list .Values.database.user "database.user") | trimSuffix ".gserviceaccount.com" -}}
{{- $name := include "spacelift-mp.required" (list .Values.database.name "database.name") -}}
{{- printf "postgres://%s@127.0.0.1/%s" (urlquery $user) $name -}}
{{- end }}
