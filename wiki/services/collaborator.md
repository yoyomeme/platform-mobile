# Collaborator

> Real-time collaborative editing service (port `3078`). Runs a Hocuspocus/Y.js server: clients connect over WebSocket and edit shared documents as CRDTs; the service debounces and persists document content to object storage (datalake/MinIO) and the platform.

## Where in code
- `server/collaborator/src/__start.ts` -- process entry.
- `server/collaborator/src/starter.ts` / `index.ts` -- boot wiring.
- `server/collaborator/src/server.ts` -- `start()`: builds the `Hocuspocus` server, HTTP `/rpc` and statistics routes, WebSocket upgrade handling.
- `server/collaborator/src/config.ts` -- env-driven `Config`.
- `server/collaborator/src/extensions/authentication.ts` -- `AuthenticationExtension`: token check on connect.
- `server/collaborator/src/extensions/storage.ts`, `storage/platform.ts`, `storage/adapter.ts` -- load/store Y.js docs to platform storage.
- `server/collaborator/src/rpc/` -- HTTP RPC methods (`getContent`, `createContent`, `updateContent`).
- `server/collaborator/src/transformers/markup.ts` -- Y.js ↔ platform markup conversion.

## Purpose
Rich-text fields (documents, descriptions) are edited by multiple users at once. Plain transactions cannot merge concurrent edits, so collaborator uses Y.js CRDTs over Hocuspocus to merge edits without conflicts, then periodically snapshots the merged document into the platform's storage and as markup the rest of the system can read. It is the realtime peer of the transactor for collaborative text.

## Responsibilities
- **WebSocket collaboration**: accept Hocuspocus connections, authenticate via the bearer token (`AuthenticationExtension`, verified with `SECRET`), and sync Y.js document updates between clients.
- **Persistence** (`StorageExtension` + `PlatformStorageAdapter`): debounced `onStoreDocument` saves the Y.js doc (`saveCollabYdoc`) and a JSON/markup projection (`saveCollabJson`) to storage, with retry; loads via `loadCollabYdoc`/`loadCollabJson`.
- **GC disabled** for ydoc so snapshots work (`gc: false`).
- **HTTP RPC** for server-side content operations that don't need a live socket: `getContent`, `createContent`, `updateContent`.
- **Activity/markup integration**: convert markup ↔ Y.js, emit collaborative-change activity messages.

## Key endpoints/methods

### WebSocket
| Aspect | Detail |
|--------|--------|
| Server | Hocuspocus on `0.0.0.0:<COLLABORATOR_PORT>`; `server.on('upgrade')` hands the socket to `hocuspocus.handleConnection`. |
| Auth | `AuthenticationExtension` decodes/validates the token; document name encodes workspace + blob id (`decodeDocumentId`). |
| Persistence timing | `debounce: 10000`, `maxDebounce: 60000`, ping `timeout: 30000`. |

### HTTP
| Method / Path | Purpose |
|---------------|---------|
| `POST /rpc/:id` | Dispatches to an RPC method (`getContent` / `createContent` / `updateContent`) for document id `:id`. |
| `GET /api/v1/statistics` | Metrics/health. |

## Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `COLLABORATOR_PORT` | `3078` | WebSocket/HTTP listen port. |
| `SECRET` | `secret` | Token verification secret. |
| `SERVICE_ID` | `collaborator-service` | Service identifier. |
| `ACCOUNTS_URL` | `http://huly.local:3000` | Account service (workspace resolution). |
| `INTERVAL` | `30000` | Internal interval (ms). |
| `STORAGE_RETRY_COUNT` | `5` | Persistence retry attempts. |
| `STORAGE_RETRY_INTERVAL` | `50` | Retry delay (ms). |
| `STORAGE_CONFIG` | — | MinIO/datalake storage for collab docs. |

Required env (service fails fast if missing): `SECRET`, `SERVICE_ID`, `COLLABORATOR_PORT`, `ACCOUNTS_URL`.

## Cross-references
- CRDT model and merge semantics: [collaboration-crdt](../concepts/collaboration-crdt.md)
- Blob/object storage backing: [datalake](datalake.md), [storage-blobs](../concepts/storage-blobs.md)
- Token issuance: [account](account.md)
- Connection auth pattern: [authentication](../security/authentication.md)
- Realtime sibling for structured data: [transactor](transactor.md)

## Gotchas
- **Persistence is debounced, not immediate.** Edits are merged in memory and flushed after `debounce` (10s, up to `maxDebounce` 60s). A hard crash can lose the last few seconds of edits not yet snapshotted.
- Y.js garbage collection is deliberately disabled (`gc: false`) so document snapshots remain valid — do not re-enable it.
- The document name carries the workspace and blob id; content lives in object storage, not the transactor DB. Both a ydoc and a markup/JSON projection are stored.
- The HTTP `/rpc` path is for server-side content access; interactive editing always goes through the WebSocket/Hocuspocus path.
- Storage writes retry (`STORAGE_RETRY_COUNT`/`INTERVAL`); persistent storage outages surface as failed snapshots after exhausting retries.
