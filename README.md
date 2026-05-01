# sample-app-chart

Helm chart for the sample app sureops deploys into per-customer namespaces during private beta.

The workload itself is [Google's Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) (11-service microservices reference). This chart wires it up with the labels, namespace conventions, and resource sizing the sureops coordinator + observability stack expect.

## Why this is a public repo

The customer-facing ArgoCD instance pulls Application manifests from this repo. ArgoCD doesn't need credentials for public repos, which keeps the customer trust boundary clean — no PAT to rotate, no deploy key to leak, no private-repo URL appearing in the customer's ArgoCD project.

## What's in here

- `Chart.yaml` — Helm chart metadata
- `values.yaml` — defaults the coordinator overrides at provision time via `Application.spec.source.helm.parameters`
- `templates/online-boutique.yaml` — Deployments + Services for the 11 Online Boutique microservices
- `templates/_helpers.tpl` — namespace + label conventions shared with the coordinator's per-customer infra chart

## What's NOT in here

- Customer credentials, tokens, secrets — none of these touch this repo
- The infra chart (per-namespace Prometheus, Loki, MCP servers, etc.) — that stays helm-installed by the coordinator from inside its container image
- Anything sureops-internal — this chart is deliberately a thin wrapper around upstream Online Boutique

## How it gets deployed

1. Customer signs up for the sureops private beta and clicks "Deploy sample environment"
2. Coordinator creates a per-customer namespace and a per-customer ArgoCD AppProject
3. Coordinator creates an ArgoCD Application pointing at this repo's `main` branch with chart path `.`
4. ArgoCD reconciles → workloads land in `org-{customer-slug}` namespace
