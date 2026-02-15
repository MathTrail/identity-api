# Plan: Rewrite identity-ui from Go to React/TypeScript/Tailwind/shadcn/zustand

## Context

The current `identity-ui` is a Go server-rendered HTML template service. The MathTrail web UI stack is React + TypeScript + Tailwind + shadcn + zustand (reference: `skillweaver/` repo patterns). Rewriting identity-ui to match this stack ensures consistency and enables richer client-side Ory Kratos flow integration.

## Key Decisions

- **Vite** for build tooling (not Next.js) — identity-ui is a simple SPA for auth forms, no SSR needed
- **nginx** to serve the static build in production — handles health probe endpoints + Kratos reverse proxy
- **React Router** for client-side routing (`/auth/login`, `/auth/registration`, `/auth/recovery`)
- **@ory/client** SDK for Kratos self-service flow integration
- **zustand** for auth state management (session, user, flow state)
- **Dynamic UI Construction** — use Ory `ui.nodes` to dynamically build forms via `Node.tsx` switcher. Never hardcode form fields — this allows automatic support for new auth methods (Google, WebAuthn, etc.)
- **Cookie-First Auth** — always use `withCredentials: true` in Ory SDK. Auth state is driven by HttpOnly cookies, not localStorage
- **Zero-CORS Development** — use Vite proxy to keep SPA and Kratos on the same effective origin during development
- **Same-Origin Production** — nginx serves both the SPA and proxies requests to Kratos under the same domain to satisfy `SameSite=Lax` cookie requirements

## What Changes

### Remove (Go stack)
- `identity-ui/cmd/main.go`
- `identity-ui/internal/`
- `identity-ui/templates/*.html`
- `identity-ui/go.mod`, `identity-ui/go.sum`

### Replace with (React stack)
```
identity-ui/
├── public/
│   └── favicon.svg
├── src/
│   ├── components/
│   │   ├── ui/                    # shadcn components (Button, Card, Input, Label, etc.)
│   │   ├── ory/
│   │   │   └── Node.tsx           # Ory UiNode → shadcn mapper (dynamic form construction)
│   │   └── auth/
│   │       └── AuthLayout.tsx     # Shared layout wrapper (Card + branding)
│   ├── hooks/
│   │   └── use-mobile.tsx
│   ├── lib/
│   │   ├── utils.ts               # cn() utility
│   │   └── kratos.ts              # Ory Kratos client (via /api/kratos proxy)
│   ├── store/
│   │   └── auth.ts                # Zustand auth store (session, initialize)
│   ├── pages/
│   │   ├── Login.tsx
│   │   ├── Registration.tsx
│   │   ├── Recovery.tsx
│   │   └── Verification.tsx
│   ├── App.tsx                    # React Router + session init
│   ├── main.tsx                   # Entry point
│   └── index.css                  # Tailwind + CSS variables
├── index.html                     # Vite entry HTML
├── nginx.conf                     # Production nginx: SPA + Kratos proxy + health
├── package.json
├── tsconfig.json
├── tsconfig.app.json
├── vite.config.ts
├── tailwind.config.ts
├── postcss.config.mjs
├── components.json                # shadcn config
└── eslint.config.js
```

### Update (existing files)
- **`Dockerfile`** — from Go multi-stage to Node multi-stage + nginx
- **`.devcontainer/devcontainer.json`** — replace Go feature with Node feature, add frontend extensions
- **`.devcontainer/Dockerfile`** — keep Ory CLI tools, remove Go-specific tooling (Go comes via feature)
- **`.devcontainer/post-start.sh`** — replace `go mod download` with `npm ci`
- **`helm/identity-ui/values.yaml`** — remove Go env vars, add Node env vars, update health probe paths
- **`.claude/CLAUDE.md`** — update language reference

### No changes needed
- `skaffold.yaml` — same `identity-ui` image name, same chartPath
- `helm/identity-ui/Chart.yaml` — same
- `helm/identity-ui/templates/main.yaml` — same
- All Ory values files, configs, dapr, justfile — unchanged

---

## Detailed Changes

### 1. `Dockerfile` (repo root)

Layer caching: `package*.json` is copied first so `npm ci` is cached when only source files change. The build context is the repo root but only `identity-ui/` files are referenced.

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /build

# Layer 1: dependencies (cached unless package.json changes)
COPY identity-ui/package.json identity-ui/package-lock.json ./
RUN npm ci

# Layer 2: source code + build
COPY identity-ui/ ./
RUN npm run build

FROM nginx:alpine
RUN addgroup -g 10001 -S appgroup && \
    adduser -u 10001 -S appuser -G appgroup
COPY --from=builder /build/dist /usr/share/nginx/html
COPY identity-ui/nginx.conf /etc/nginx/conf.d/default.conf
# nginx needs writable dirs for pid/cache — create them owned by appuser
RUN mkdir -p /var/cache/nginx /var/run && \
    chown -R 10001:10001 /var/cache/nginx /var/run /usr/share/nginx/html
USER 10001
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
```

Add `.dockerignore` to exclude unnecessary files from build context:
```
node_modules
.devcontainer
.claude
helm
configs
dapr
values
*.md
.git
```

### 2. `identity-ui/nginx.conf`

Same-origin production config: nginx serves both the SPA static files and proxies `/api/kratos` to the Kratos service, so `SameSite=Lax` cookies work without CORS.

```nginx
server {
    listen 8080;
    root /usr/share/nginx/html;
    index index.html;

    # Health endpoints required by mathtrail-service-lib
    location /health/startup  { return 200 '{"status":"started"}'; add_header Content-Type application/json; }
    location /health/liveness { return 200 '{"status":"ok"}';      add_header Content-Type application/json; }
    location /health/ready    { return 200 '{"status":"ready"}';   add_header Content-Type application/json; }

    # Reverse proxy to Kratos — same-origin for cookies
    location /api/kratos/ {
        proxy_pass http://kratos-public:4433/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # SPA fallback — all /auth/* routes handled by React Router
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

### 3. `identity-ui/package.json`

Key dependencies:
- `react`, `react-dom`, `react-router-dom`
- `@ory/client` (Kratos SDK — provides `UiNode`, `FrontendApi`, flow types)
- `zustand`
- `tailwindcss`, `tailwind-merge`, `tailwindcss-animate`
- `class-variance-authority`, `clsx`
- `@radix-ui/react-*` (via shadcn)
- `lucide-react`

Dev dependencies:
- `vite`, `@vitejs/plugin-react`
- `typescript`, `@types/react`, `@types/react-dom`
- `postcss`, `autoprefixer`
- `eslint`, `@eslint/js`, `typescript-eslint`

### 4. `identity-ui/vite.config.ts`

Vite proxy ensures the SPA and Kratos share the same origin during development, so `SameSite=Lax` cookies work without CORS.

```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') }
  },
  server: {
    port: 3000,
    proxy: {
      '/api/kratos': {
        target: 'http://localhost:4433',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api\/kratos/, ''),
      }
    }
  }
})
```

### 5. `identity-ui/src/store/auth.ts` (zustand)

Includes `initialize` action that checks Kratos session on app startup — prevents login form flash for already-authenticated users.

```typescript
import { create } from 'zustand'
import { Session, Identity } from '@ory/client'
import { kratos } from '@/lib/kratos'

interface AuthState {
  session: Session | null
  identity: Identity | null
  loading: boolean
  initialized: boolean
  setSession: (session: Session | null) => void
  setLoading: (loading: boolean) => void
  initialize: () => Promise<void>
  logout: () => void
}

export const useAuthStore = create<AuthState>((set, get) => ({
  session: null,
  identity: null,
  loading: true,
  initialized: false,

  setSession: (session) => set({
    session,
    identity: session?.identity ?? null,
  }),

  setLoading: (loading) => set({ loading }),

  initialize: async () => {
    if (get().initialized) return
    try {
      const { data } = await kratos.toSession()
      set({
        session: data,
        identity: data.identity,
        loading: false,
        initialized: true,
      })
    } catch {
      // No active session — user needs to authenticate
      set({ session: null, identity: null, loading: false, initialized: true })
    }
  },

  logout: () => set({ session: null, identity: null }),
}))
```

Called in `App.tsx` via `useEffect`:
```typescript
import { useEffect } from 'react'
import { useAuthStore } from '@/store/auth'

export function App() {
  const initialize = useAuthStore((s) => s.initialize)
  useEffect(() => { initialize() }, [initialize])
  // ... routes
}
```

### 6. `identity-ui/src/lib/kratos.ts`

Uses `/api/kratos` proxy path (not direct port 4433) so cookies flow on the same origin. `withCredentials: true` ensures HttpOnly session cookies are sent with every request.

```typescript
import { FrontendApi, Configuration } from '@ory/client'

export const kratos = new FrontendApi(
  new Configuration({
    basePath: '/api/kratos',
    baseOptions: { withCredentials: true },
  })
)
```

In production, nginx proxies `/api/kratos` to the Kratos service (see nginx.conf section).

### 7. `identity-ui/src/components/ory/Node.tsx` — Ory Node Mapper

Core component that maps Kratos `UiNode` objects to shadcn UI components. Never hardcode form fields — this allows automatic support for new auth methods (Google, WebAuthn, TOTP, etc.) without changing UI code.

```typescript
import { UiNode, UiNodeInputAttributes } from '@ory/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

interface NodeProps {
  node: UiNode
  disabled?: boolean
}

export function Node({ node, disabled }: NodeProps) {
  const attrs = node.attributes

  if (attrs.node_type === 'input') {
    const input = attrs as UiNodeInputAttributes

    // Submit buttons
    if (input.type === 'submit') {
      return (
        <Button type="submit" name={input.name} value={input.value} disabled={disabled}>
          {node.meta.label?.text ?? 'Submit'}
        </Button>
      )
    }

    // Hidden inputs (csrf_token, etc.)
    if (input.type === 'hidden') {
      return <input type="hidden" name={input.name} value={input.value} />
    }

    // Regular text/email/password inputs
    return (
      <div className="space-y-2">
        {node.meta.label && <Label htmlFor={input.name}>{node.meta.label.text}</Label>}
        <Input
          id={input.name}
          name={input.name}
          type={input.type}
          defaultValue={input.value}
          disabled={input.disabled || disabled}
          required={input.required}
        />
        {node.messages?.map((msg) => (
          <p key={msg.id} className="text-sm text-destructive">{msg.text}</p>
        ))}
      </div>
    )
  }

  // Extend here for: anchor, image, script, text node types
  return null
}
```

Usage in page components — render all nodes from a flow:
```tsx
{flow.ui.nodes.map((node, i) => <Node key={i} node={node} />)}
```

### 8. `identity-ui/src/App.tsx`

Calls `initialize()` on mount to check for existing Kratos session before rendering routes.

```typescript
import { useEffect } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useAuthStore } from '@/store/auth'
import { Login } from '@/pages/Login'
import { Registration } from '@/pages/Registration'
import { Recovery } from '@/pages/Recovery'
import { Verification } from '@/pages/Verification'

export function App() {
  const initialize = useAuthStore((s) => s.initialize)
  const loading = useAuthStore((s) => s.loading)

  useEffect(() => { initialize() }, [initialize])

  if (loading) return null // or a spinner

  return (
    <BrowserRouter>
      <Routes>
        <Route path="/auth/login" element={<Login />} />
        <Route path="/auth/registration" element={<Registration />} />
        <Route path="/auth/recovery" element={<Recovery />} />
        <Route path="/auth/verification" element={<Verification />} />
        <Route path="*" element={<Navigate to="/auth/login" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
```

### 9. Pages (Login, Registration, Recovery, Verification)

Each page follows the Ory self-service flow pattern:
1. Check for `flow` query parameter via `useSearchParams()`
2. If missing, redirect browser to Kratos to create a new flow (`window.location.href = ...`)
3. If present, fetch the flow from Kratos via `@ory/client` SDK
4. Render the form using `<Node />` mapper — **never hardcode form fields**
5. Submit via `<form action={flow.ui.action} method={flow.ui.method}>` — Kratos handles submission natively

Example Login page pattern:
```tsx
import { useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { LoginFlow } from '@ory/client'
import { kratos } from '@/lib/kratos'
import { Node } from '@/components/ory/Node'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { AuthLayout } from '@/components/auth/AuthLayout'

export function Login() {
  const [searchParams] = useSearchParams()
  const [flow, setFlow] = useState<LoginFlow | null>(null)

  useEffect(() => {
    const flowId = searchParams.get('flow')
    if (!flowId) {
      window.location.href = '/api/kratos/self-service/login/browser'
      return
    }
    kratos.getLoginFlow({ id: flowId }).then(({ data }) => setFlow(data))
  }, [searchParams])

  if (!flow) return null

  return (
    <AuthLayout>
      <Card>
        <CardHeader><CardTitle>Sign In</CardTitle></CardHeader>
        <CardContent>
          <form action={flow.ui.action} method={flow.ui.method} className="space-y-4">
            {flow.ui.nodes.map((node, i) => <Node key={i} node={node} />)}
          </form>
        </CardContent>
      </Card>
    </AuthLayout>
  )
}
```

Registration, Recovery, and Verification follow the same pattern with their respective flow types and Kratos endpoints.

### 10. DevContainer updates

**`.devcontainer/devcontainer.json`** — change features:
```json
{
  "features": {
    "ghcr.io/devcontainers/features/node:1": { "version": "20" },  // was Go
    // keep: docker-in-docker, kubectl-helm, just, dapr-cli
  },
  // add extensions: dbaeumer.vscode-eslint, esbenp.prettier-vscode, bradlc.vscode-tailwindcss
  // keep: vscode-docker, kubernetes, helm, yaml, gitlens, justfile, claude-code
}
```

**`.devcontainer/post-start.sh`** — replace Go download with:
```bash
cd /workspaces/mathtrail-identity/identity-ui && npm ci 2>/dev/null || true
```

### 11. `helm/identity-ui/values.yaml`

```yaml
image:
  repository: identity-ui
  tag: latest

dapr:
  enabled: false
```

No env vars needed — `kratos.ts` uses relative `/api/kratos` path, nginx proxies to `kratos-public:4433`. No `SERVER_PORT` needed — nginx listens on 8080 (matching service-lib default).

---

## Files Summary

| Action | File |
|--------|------|
| **Delete** | `identity-ui/cmd/main.go` |
| **Delete** | `identity-ui/go.mod` |
| **Delete** | `identity-ui/templates/login.html` |
| **Delete** | `identity-ui/templates/registration.html` |
| **Delete** | `identity-ui/templates/recovery.html` |
| **Rewrite** | `Dockerfile` |
| **Rewrite** | `.devcontainer/devcontainer.json` |
| **Rewrite** | `.devcontainer/post-start.sh` |
| **Update** | `.devcontainer/Dockerfile` (remove Go, keep Ory CLIs) |
| **Update** | `helm/identity-ui/values.yaml` |
| **Update** | `.claude/CLAUDE.md` |
| **Create** | `identity-ui/package.json` |
| **Create** | `identity-ui/tsconfig.json` |
| **Create** | `identity-ui/tsconfig.app.json` |
| **Create** | `identity-ui/vite.config.ts` |
| **Create** | `identity-ui/tailwind.config.ts` |
| **Create** | `identity-ui/postcss.config.mjs` |
| **Create** | `identity-ui/components.json` |
| **Create** | `identity-ui/index.html` |
| **Create** | `identity-ui/nginx.conf` |
| **Create** | `identity-ui/eslint.config.js` |
| **Create** | `identity-ui/src/main.tsx` |
| **Create** | `identity-ui/src/App.tsx` |
| **Create** | `identity-ui/src/index.css` |
| **Create** | `identity-ui/src/lib/utils.ts` |
| **Create** | `identity-ui/src/lib/kratos.ts` |
| **Create** | `identity-ui/src/store/auth.ts` |
| **Create** | `identity-ui/src/pages/Login.tsx` |
| **Create** | `identity-ui/src/pages/Registration.tsx` |
| **Create** | `identity-ui/src/pages/Recovery.tsx` |
| **Create** | `identity-ui/src/pages/Verification.tsx` |
| **Create** | `identity-ui/src/components/ory/Node.tsx` |
| **Create** | `identity-ui/src/components/auth/AuthLayout.tsx` |
| **Create** | shadcn UI components (Button, Card, Input, Label, etc.) |
| **Create** | `.dockerignore` |

---

## Verification

1. `cd identity-ui && npm ci && npm run build` — should produce `dist/` with static files
2. `cd identity-ui && npm run dev` — Vite dev server on :3000 with Kratos proxy
3. Docker build: `docker build -t identity-ui:test .` — nginx image serves on :8080
4. Health probes: `curl http://localhost:8080/health/ready` returns `{"status":"ready"}`
5. SPA routing: `curl http://localhost:8080/auth/login` returns index.html (React Router handles)
6. `skaffold run` — deploys to k3d cluster, same Helm chart works
7. Kratos flow: Navigate to `/auth/login` — should redirect to Kratos to create flow, then render form
