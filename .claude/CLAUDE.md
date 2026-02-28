# MathTrail Identity Stack

## Overview

Identity and access management for the MathTrail platform. Deploys the Ory
stack (Kratos, Hydra, Keto, Oathkeeper) plus a custom Identity UI SPA.

**Stack:** React + TypeScript + Tailwind + shadcn + zustand (Identity UI)
**Build:** Vite (dev), nginx (production)
**Port:** 3000 (Vite dev), 8080 (nginx prod), 4433/4434 (Kratos), 4444/4445 (Hydra), 4466/4467 (Keto), 4455/4456 (Oathkeeper)
**Cluster:** k3d `mathtrail-dev`, namespace `mathtrail`
**KUBECONFIG:** `/home/vscode/.kube/k3d-mathtrail-dev.yaml`

## Key Files

| File | Purpose |
|------|---------|
| `identity-ui/src/App.tsx` | React Router + session initialization |
| `identity-ui/src/components/ory/Node.tsx` | Ory UiNode to shadcn component mapper |
| `identity-ui/src/lib/kratos.ts` | Ory Kratos client (via `/api/kratos` proxy) |
| `identity-ui/src/store/auth.ts` | Zustand auth store (session, initialize) |
| `identity-ui/nginx.conf` | Production nginx: SPA + Kratos proxy + health |
| `identity-ui/vite.config.ts` | Vite config with Kratos proxy for dev |
| `Dockerfile` | Multi-stage: Node build + nginx serve |
| `helm/identity-ui/Chart.yaml` | Helm chart, depends on `mathtrail-service-lib` |
| `helm/identity-ui/values.yaml` | Identity UI deployment config |
| `values/kratos-values.yaml` | Kratos Helm values |
| `values/hydra-values.yaml` | Hydra Helm values |
| `values/keto-values.yaml` | Keto Helm values |
| `values/oathkeeper-values.yaml` | Oathkeeper Helm values |
| `configs/kratos/identity.schema.json` | User identity JSON schema |
| `configs/keto/namespaces.ts` | Keto ReBAC namespace definitions |
| `configs/oathkeeper/access-rules.yaml` | Oathkeeper access rules |

| `skaffold.yaml` | Skaffold pipeline (Ory infra + Identity UI) |
| `justfile` | Automation recipes |

## Architecture

This is a **hybrid** repository:
- **Infrastructure**: Deploys Ory Kratos, Hydra, Keto, Oathkeeper via official Helm charts (vendored in mathtrail-charts)
- **Custom service**: Identity UI SPA uses `mathtrail-service-lib` library chart

### Key Patterns

- **Dynamic UI**: Forms are built dynamically from Kratos `ui.nodes` via `Node.tsx` — never hardcode form fields
- **Cookie-First Auth**: `withCredentials: true` in Ory SDK, HttpOnly cookies, no localStorage
- **Same-Origin**: Vite proxy (dev) and nginx proxy (prod) keep SPA and Kratos on the same origin

## Service-Lib Contract (Identity UI MUST follow)

- **Health probes required:** `/health/startup`, `/health/liveness`, `/health/ready` (served by nginx)
- **Security:** Container must run as non-root (UID 10001), `readOnlyRootFilesystem: true`
- **Validation:** `image.repository`, `image.tag`, `resources.requests`, `resources.limits` must be defined in values.yaml

## Development Workflow

```bash
cd identity-ui && npm run dev   # Vite dev server on :3000 with Kratos proxy
just dev      # Skaffold dev: hot-reload + port-forward all Ory + UI
just deploy   # One-time build and deploy everything
just delete   # Remove from cluster
just status   # Check all identity component pods
just logs     # View Identity UI pod logs
```

## External Dependencies

| Repo | Purpose |
|------|---------|
| `mathtrail-charts` | Hosts `mathtrail-service-lib` + vendored Ory charts |
| `mathtrail-infra-local` | PostgreSQL (Ory components need databases: kratos, hydra, keto) |
| `mathtrail-infra-local-k3s` | k3d cluster setup |

## Pre-requisites

1. k3d cluster running (`just create` in `mathtrail-infra-local-k3s`)
2. PostgreSQL deployed with `kratos`, `hydra`, `keto` databases (`mathtrail-infra-local`)
