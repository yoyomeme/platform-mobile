# Transactor

> Core transaction-processing engine (port `3332`). Holds WebSocket sessions per workspace, runs every mutation through an ordered middleware pipeline (security → triggers → fulltext → persistence → broadcast), publishes events to the queue, and serves `findAll`/`tx` over both WS and HTTP.

## Where in code
- `pods/server/src/__start.ts` -- process entry; builds metrics, the Kafka queue (`getPlatformQueue('transactor')`), storage config, and calls `start()`.
- `pods/server/src/server.ts` -- `start()`: registers DB/tx adapter factories (Postgres/Mongo), builds the `createServerPipeline` factory, starts the session manager and HTTP server.
- `pods/server/src/server_http.ts` -- `startHttpServer`: Express + `ws` WebSocket upgrade, `/api/v1/*` admin/blob routes, broadcast endpoint.
- `pods/server/src/rpc.ts` -- `registerRPC`: stateless HTTP transport for `ping`/`findAll`/`tx`/`domainRequest` keyed by token-derived sessions.
- `server/server-pipeline/src/pipeline.ts` -- `createServerPipeline()` / `createBackupPipeline()`: the ordered list of middlewares and DB adapter config (`getConfig`).
- `server/server-pipeline/src/blobStorage.ts`, `communication.ts` -- blob domain adapter and communication middleware.

## Purpose
Every read and write in a workspace goes through its transactor. It maintains authenticated long-lived sessions, validates each operation against space/permission security, fires triggers and derived-data computation, hands documents to fulltext indexing, persists transactions to the `Tx` domain in CockroachDB, broadcasts changes to all connected sessions, and emits queue events that fulltext/backup/process consume asynchronously.

## Responsibilities
- **Session management**: authenticate WebSocket connections with the workspace-scoped JWT, build/cache a per-workspace `Pipeline`, enforce rate limits, and `broadcast` updates to sessions.
- **Pipeline execution** (ordered middlewares in `createServerPipeline`): lookup, normalize/identity/modified/rank, find security, plugin/private config, **space security & permissions**, guest permissions, configuration, context naming, mark-derived, communication, user status, apply-tx, versioning, identifier, rating, **TxMiddleware** (store into `DOMAIN_TX`), **triggers**, **fulltext** (forwards to fulltext service), low-level, tx-ordering, query-join, live-query, domain find/tx, **queue** (publish events), DB-adapter init/model/DB, **broadcast**.
- **Persistence**: Tx adapter (`Tx` domain) + Main adapter via Postgres/Mongo; transient in-memory; blob domain via `StorageData` (datalake/MinIO).
- **Queue publishing**: `QueueMiddleware` emits document/tx events to Redpanda topics consumed downstream.
- **HTTP RPC**: stateless `findAll`/`tx`/`ping` for clients/services that cannot hold a socket.
- **Maintenance**: admin endpoints to enter maintenance, force-close sessions, profile, reboot.

## Key endpoints/methods

### WebSocket
| Aspect | Detail |
|--------|--------|
| Upgrade | `httpServer.on('upgrade', ...)` in `server_http.ts`; token passed on connect, decoded and verified. |
| Protocol | Binary/JSON RPC frames: `findAll`, `tx`, `searchFulltext`, `loadModel`, `ping`, etc. (see [transactor-rpc](../api/transactor-rpc.md)). |
| Compression | snappy/gzip when `ENABLE_COMPRESSION=true`. |

### HTTP (`rpc.ts`, `server_http.ts`)
| Method / Path | Purpose |
|---------------|---------|
| `GET /api/v1/ping/:workspaceId` | Session keep-alive; returns `lastTx`/`lastHash`. |
| `GET`/`POST /api/v1/find-all/:workspaceId` | `findAll` (query/options as query string or JSON body). |
| `POST /api/v1/tx/:workspaceId` | Submit a transaction; `TxDomainEvent` routed to the communication domain. |
| `POST /api/v1/event/:workspaceId` | (deprecated) communication-domain event. |
| `GET /api/v1/account/:workspaceId` | Session account info. |
| `PUT /api/v1/blob`, `GET /api/v1/blob` | Blob put/get via the storage adapter. |
| `PUT /api/v1/broadcast` | Inject a broadcast. |
| `PUT /api/v1/manage?operation=...` | Admin: `maintenance`, `force-maintenance`, `force-close`, `wipe-statistics`, `profile-start/stop`, `reboot`. |
| `GET /api/v1/version` / `/health` / `/statistics` / `/profiling` | Diagnostics. |

The HTTP transport keys a session by token: `withSession` validates `workspaceId === decodedToken.workspace` (403 on mismatch) and reuses an `addSession` per token, then dispatches via `sessions.handleRPC` (which applies rate limiting → 429 with `Retry-After`).

## Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `SERVER_PORT` | `3332` | WebSocket/HTTP listen port. |
| `DB_URL` | (required) | CockroachDB/Postgres connection. |
| `MONGO_URL` | — | Optional Mongo for legacy domains. |
| `FULLTEXT_URL` | `http://huly.local:4702` | Fulltext service; enables the FullText middleware. |
| `QUEUE_CONFIG` | `cockroach\|http://redpanda:9092` | Kafka/Redpanda config (required). |
| `STORAGE_CONFIG` | — | MinIO/datalake config for the blob domain. |
| `ACCOUNTS_URL` | `http://huly.local:3000` | Account service (token/account lookups). |
| `SERVER_SECRET` | `secret` | JWT verification secret; `Service` metadata set to `transactor`. |
| `MODEL_JSON` | `model.json` | Serialized model (system Tx) loaded at boot. |
| `ENABLE_COMPRESSION` | `true` | WS payload compression. |
| `RATE_LIMIT_MAX` / `RATE_LIMIT_WINDOW` | `250` / `30000` | Requests per window (ms). |
| `LAST_NAME_FIRST` | `true` | Name formatting. |
| `COMMUNICATION_API_ENABLED` | `true` | Enables communication middleware/domain. |
| `AI_BOT_URL`, `CALENDAR_URL` | — | Optional integration endpoints. |
| `DB_PREPARE` | `true` | Postgres prepared statements. |
| `OPERATION_PROFILING` | `false` | Operation-log profiling. |

## Cross-references
- RPC method catalog: [transactor-rpc](../api/transactor-rpc.md)
- Connection/auth model: [client-protocol](../concepts/client-protocol.md)
- Write path end-to-end: [transaction-flow](../flows/transaction-flow.md)
- Async events: [event-queue](../concepts/event-queue.md)
- Token issuance & endpoint routing: [account](account.md)
- Downstream indexing: [fulltext-service](fulltext-service.md)
- Blob domain backing store: [datalake](datalake.md)
- Backup uses `createBackupPipeline`: [backup](backup.md)

## Gotchas
- **Pipeline order is load-bearing.** Triggers run after `TxMiddleware` (so the tx is persisted), fulltext after triggers (so derived docs are indexed), and broadcast last. Reordering changes correctness, not just performance.
- The transactor does not own fulltext or blobs — it forwards: fulltext via the FullText middleware (with a system token) and blobs via the `StorageData` adapter to datalake/MinIO.
- HTTP `tx`/`findAll` reuse a per-token session held in memory (`rpcSessions`); a maintenance/force-close clears them. Workspace in the URL must equal the token's workspace.
- If `FULLTEXT_URL` is unset, the fulltext middleware is omitted entirely (no search indexing for that instance).
- `createBackupPipeline` is a trimmed pipeline (triggers disabled, no security/broadcast) used by the workspace/backup services, not for live client traffic.
