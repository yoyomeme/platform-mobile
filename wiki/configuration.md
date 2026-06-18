# Configuration

> How a client boots and connects to a self-hosted Huly instance: config discovery → account login → workspace selection → transactor connection → model load. There is no global SDK singleton; "configuration" means establishing the connection chain.

## Where in code

- `server/front/src/index.ts` — serves `config.json` (backend URL discovery)
- `foundations/core/packages/account-client/src/{client,types}.ts` — account JSON-RPC client
- `foundations/core/packages/client-resources/src/connection.ts` — transactor WebSocket connection
- `foundations/core/packages/client/src/` — `createClient`, model load
- `plugins/workbench-resources/src/connect.ts` — reference bootstrap flow (web client)
- `plugins/login-resources/src/utils.ts` — login UI flow

## The connection chain

A client needs only the **instance base URL**. Everything else is discovered.

```
        base URL (e.g. https://huly.mycompany.com)
            │
   1. GET /config.json  (front)         → ACCOUNTS_URL, transactor discovery, FILES_URL, …
            │
   2. account.login(email, password)    → { account, token }            (HTTP JSON-RPC :3000)
            │
   3. account.getUserWorkspaces(token)  → WorkspaceInfoWithStatus[]
            │
   4. account.selectWorkspace(wsUrl)    → { endpoint, token, workspace } (workspace-scoped JWT)
            │
   5. createClient(endpoint, token)     → WebSocket connect + loadModel  (transactor :3332)
            │
   6. Hierarchy + ModelDb ready         → findAll / tx / live updates work
```

See [login-flow](flows/login-flow.md) and [model-load-flow](flows/model-load-flow.md) for full sequences.

## Step 1 — config discovery (`config.json`)

Fetched from the **front** service. Lists every backend URL so nothing is hardcoded in the client.

| Field | Example | Use |
|---|---|---|
| `ACCOUNTS_URL` | `http://huly.local:3000` | login + workspace selection |
| `FILES_URL` | `…/blob/:workspace/:blobId/:filename` | file download pattern |
| `UPLOAD_URL` | `/files` | file upload |
| `DATALAKE_URL` | `http://huly.local:4030` | blob storage |
| `COLLABORATOR_URL` | `ws://huly.local:3078` | collaborative editing |
| `PREVIEW_URL` | `http://huly.local:4040` | thumbnails |
| `PULSE_URL` | `ws://huly.local:8099/ws` | push notifications |
| `STREAM_URL` | `http://huly.local:1080/recording` | video (HLS) |
| `BRANDING_URL` | `…/branding.json` | logo/color overrides |
| `MODEL_VERSION` / `VERSION` | `0.7.0` | compatibility check |

## Step 5 — `createClient` / what model load does internally

```
createClient(endpoint, token)
    │
    ├── 1. open WebSocket ws://{endpoint}/{token}?sessionId={uuid}
    ├── 2. HelloRequest { binary?, compression? } → HelloResponse { serverVersion, lastTx, lastHash, useCompression }
    ├── 3. loadModel(lastTx, hash?)  → stream of model Tx
    ├── 4. build Hierarchy (classes, attributes, mixins) + ModelDb
    ├── 5. register TxHandler for live broadcast tx
    └── 6. ready: findAll / findOne / tx / searchFulltext
```

The model is cacheable by `lastHash` so reconnects/startup are fast.

## Identity & secrets

| Value | Set by | Used by |
|-------|--------|---------|
| `SERVER_SECRET` / `SECRET` | deployment env (shared) | all services for service-to-service JWT |
| workspace JWT `token` | account `selectWorkspace` | transactor WS auth, blob auth |
| `sessionId` | client (UUID per connection) | request↔response correlation, reconnect |
| `REGION` | deployment env | workspace→transactor routing |

See [authentication](security/authentication.md) and [token-package](security/token-package.md).

## Cross-references

- [overview](overview.md) — what Huly is
- [architecture](architecture.md) — layer diagram
- [login-flow](flows/login-flow.md) — detailed login sequence
- [client-protocol](concepts/client-protocol.md) — transactor RPC details
- [front-config](api/front-config.md) — `config.json` field reference

## Gotchas

- **`config.json` is the source of truth** — never hardcode service URLs; they vary per deployment and region.
- **Two tokens exist**: the account-level token (from `login`) and the workspace-scoped token (from `selectWorkspace`). The transactor needs the *workspace* token.
- **`endpoint` is chosen server-side** — the account service hashes the workspace UUID to pick a transactor; the client connects to whatever `endpoint` it is handed.
- `kind: 'internal'` vs `'external'` in `selectWorkspace` selects internal-network vs public transactor URL.
