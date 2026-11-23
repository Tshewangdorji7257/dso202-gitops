{{- /*
File:        charts/tasktracker/templates/_helpers.tpl
Assignment:  DSO202 Assignment 4 - GitOps Delivery of the Task Tracker
Descriptor:  3.1.4 (Helm named templates)
Purpose:     Labels shared by every object, and the config checksum that
             rolls the backend and frontend Pods when the ConfigMap changes.
*/ -}}

{{/* Labels on every object. Selectors use only "tier" and never change. */}}
{{- define "tasktracker.labels" -}}
app.kubernetes.io/name: tasktracker
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: dso202
app.kubernetes.io/environment: {{ .Values.environment | quote }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
course: dso202
assignment: "4"
{{- end -}}

{{/* New ConfigMap content -> new annotation value -> Pods roll. Not used on
     the database Pod, so a LOG_LEVEL change does not restart PostgreSQL. */}}
{{- define "tasktracker.configChecksum" -}}
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
{{- end -}}

{{/* The Secret name comes from the platform layer and must be set. */}}
{{- define "tasktracker.secretName" -}}
{{- required "credentials.secretName is required (the Secret created by the SealedSecret)" .Values.credentials.secretName -}}
{{- end -}}
