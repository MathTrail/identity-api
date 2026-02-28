# mathtrail-identity
Identity and access management built on the Ory stack — handles authentication, authorization, sessions, and OAuth2 flows.

## Mission & Responsibilities
- User registration and login (Ory Kratos)
- OAuth2 / OIDC provider (Ory Hydra)
- Fine-grained authorization (Ory Keto — relation tuples)
- API gateway authorization (Ory Oathkeeper)
- Self-service UI for login/registration/settings (Identity UI — React/Vite)

## Tech Stack
- **Auth**: Ory Kratos (identity), Ory Hydra (OAuth2), Ory Keto (permissions), Ory Oathkeeper (API gateway)
- **UI**: React 19, TypeScript, Vite 6, Tailwind CSS 4, shadcn/ui, Zustand
- **Build**: Multi-stage Docker (Node 20 builder → nginx alpine)

## Architecture
Identity is split into infrastructure (Ory services deployed from remote charts) and UI (local React app):
- Ory components communicate internally via K8s services
- Identity UI is a SPA that talks to Kratos via nginx reverse proxy
- Oathkeeper sits in front of all APIs for token validation

## API & Communication
- **Inbound**: Browser → Identity UI → Kratos APIs
- **Outbound**: Kratos webhook → mathtrail-profile (registration event)
- **Publishes**: `identity.registration.completed` (via webhook → Kafka)

## Data Persistence
- **PostgreSQL**: Kratos identities, Hydra clients, Keto relations (each has own DB)

## Secrets
- `KRATOS_DSN` — Kratos database connection string
- `HYDRA_DSN` — Hydra database connection string
- Vault path: `secret/data/{env}/mathtrail-identity/`

## Infrastructure
Hybrid Helm deployment: remote Ory charts + local identity-ui chart
- `infra/helm/identity-ui/` — Custom Identity UI chart
- `values/` — Ory component Helm values (kratos, hydra, keto, oathkeeper)

## Development
- `just dev` — Skaffold dev loop (deploys all Ory + Identity UI)
- Identity UI: `cd identity-ui && npm run dev` (Vite dev server, port 3000)
