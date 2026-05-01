{{/*
Per-customer namespace name — same scheme as the per-customer infra
chart (``deploy/k3s/per-customer/templates/_helpers.tpl``). Both
charts MUST agree on this string because they deploy resources into
the same namespace; coordinator pre-creates it before installing
either chart.
*/}}
{{- define "customer.namespace" -}}
org-{{ .Values.customer.slug }}
{{- end -}}

{{/*
Common labels applied to every per-customer resource. Mirrors the
infra chart's ``customer.labels`` so a service-monitor selector
keyed on these labels matches deployments from EITHER chart. Don't
drift these — Prometheus's ServiceMonitor (in the infra chart) uses
``sureops.ai/customer-slug`` to scope scraping; if the OB Service
labels diverge, Prometheus stops finding endpoints.
*/}}
{{- define "customer.labels" -}}
app.kubernetes.io/managed-by: sureops-coordinator
sureops.ai/customer-slug: {{ .Values.customer.slug }}
sureops.ai/customer-org-id: {{ .Values.customer.orgId | quote }}
sureops.ai/env: {{ .Values.env }}
{{- end -}}
