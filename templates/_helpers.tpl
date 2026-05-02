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

{{/*
OTel tracing activation block. Included in every microservice
Deployment's env: list. OB's instrumented services (frontend, checkout,
productcatalog, currency, payment, email, recommendation) gate on
``ENABLE_TRACING=1`` AND read the collector address from
``COLLECTOR_SERVICE_ADDR`` (custom OB env names — NOT canonical OTel).
The OTel-canonical OTEL_RESOURCE_ATTRIBUTES + OTEL_SERVICE_NAME ARE
honored by the SDKs' default Resource detector, even when the service
constructs its TracerProvider explicitly.

OTEL_SERVICE_NAME is sourced from the pod's ``app`` label via the
downward API, so the partial is universal — the same include block
works across all 10 microservice Deployments.

NOT included: any sampling env. OB hardcodes AlwaysSample() in every
service's tracing init; ``OTEL_TRACES_SAMPLER`` is ignored. Sampling
happens collector-side (per-customer OTel collector deployed by the
infra chart — probabilistic_sampler processor at
.Values.traceSamplingPercentage, default 10%).

Per-language coverage (audit findings):
  ✅ frontend, checkoutservice, productcatalogservice (Go SDK linked)
  ✅ emailservice, recommendationservice (Python TracerProvider in code)
  ✅ currencyservice, paymentservice (Node sdk-node)
  ❌ shippingservice (Go, no SDK linked) — env vars are no-op
  ❌ adservice (Java, no agent) — env vars are no-op until javaagent is added
  ❌ cartservice (.NET, no SDK) — env vars are no-op until SDK is linked

We include the env block universally for forward-compat; no-op cases do
no harm and the consistent shape makes per-service follow-up PRs simpler.
*/}}
{{- define "customer.otelEnv" -}}
- name: ENABLE_TRACING
  value: "1"
- name: COLLECTOR_SERVICE_ADDR
  value: "otel-collector.{{ include "customer.namespace" . }}.svc.cluster.local:4317"
- name: OTEL_RESOURCE_ATTRIBUTES
  value: "customer.slug={{ .Values.customer.slug }},deployment.environment={{ .Values.env }}"
- name: OTEL_SERVICE_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.labels['app']
{{- end -}}

{{/*
Java agent extras for adservice. The OB chart has no source-side OTel for the
Java service, so we inject the OpenTelemetry javaagent at pod startup via an
initContainer that drops the jar into a shared emptyDir, then point JVM at it
via JAVA_TOOL_OPTIONS. The agent reads the canonical OTLP env vars below — note
COLLECTOR_SERVICE_ADDR (used by the Go/Python/Node services) is NOT honored
by the agent; it needs OTEL_EXPORTER_OTLP_ENDPOINT.

Three partials so each goes in the right slot of the Deployment spec:
  - customer.otelJavaInitContainer → spec.template.spec.initContainers
  - customer.otelJavaVolume        → spec.template.spec.volumes
  - customer.otelJavaVolumeMount   → container.volumeMounts
  - customer.otelJavaEnv           → container.env (additive on top of customer.otelEnv)

Agent version is pinned to v2.10.0 — bump deliberately; auto-instrumentation
behavior changes between minor versions. The download is cached on each pod
start (no image rebuild), so updating the version is a chart-only change.

Metrics + logs exporters are forced to "none" because:
  - OB's adservice doesn't emit metrics worth keeping (gRPC server only)
  - The per-customer collector's logs pipeline isn't wired (logs flow via Promtail)
*/}}
{{- define "customer.otelJavaInitContainer" -}}
- name: install-otel-javaagent
  image: busybox:1.36
  command:
    - /bin/sh
    - -c
    - |
      set -eu
      AGENT_VERSION=v2.10.0
      AGENT_URL="https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/${AGENT_VERSION}/opentelemetry-javaagent.jar"
      echo "Downloading OpenTelemetry javaagent ${AGENT_VERSION}..."
      wget -q -O /otel/opentelemetry-javaagent.jar "${AGENT_URL}"
      ls -la /otel/opentelemetry-javaagent.jar
  volumeMounts:
    - name: otel-agent
      mountPath: /otel
{{- end -}}

{{- define "customer.otelJavaVolume" -}}
- name: otel-agent
  emptyDir: {}
{{- end -}}

{{- define "customer.otelJavaVolumeMount" -}}
- name: otel-agent
  mountPath: /otel
  readOnly: true
{{- end -}}

{{- define "customer.otelJavaEnv" -}}
- name: JAVA_TOOL_OPTIONS
  value: "-javaagent:/otel/opentelemetry-javaagent.jar"
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: "http://otel-collector.{{ include "customer.namespace" . }}.svc.cluster.local:4317"
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: "grpc"
- name: OTEL_METRICS_EXPORTER
  value: "none"
- name: OTEL_LOGS_EXPORTER
  value: "none"
{{- end -}}
