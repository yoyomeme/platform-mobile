# Front

> Web application server (ports `8087`/`8088`). Serves the static Huly UI (gzip-precompressed), proxies file upload/download/preview to storage, serves branding, and — most importantly for every client — generates the runtime `config.json` that tells the client where all other services live.

## Where in code
- `pods/front/src/__start.ts` -- process entry; reads env into the `config` object and calls `start()`.
- `server/front/src/index.ts` -- `start()`: Express app, `GET /config.json`, static asset serving, `/files` upload/download with on-the-fly image resize, `/import` proxy, SPA fallback.
- `server/front/src/utils.ts` -- HTTP precondition helpers (`IfNoneMatch`, `IfModifiedSince`, etc.).

## Purpose
Front is the entry point for browsers and the desktop app. It ships the compiled SPA and, because the SPA is environment-agnostic, hands it a `config.json` at runtime listing the URLs of account, collaborator, datalake, preview, stream, pulse, etc. It also brokers file traffic: uploads to storage, range/conditional downloads, and cached image previews (via `sharp`).

## Responsibilities
- **`config.json` generation**: assemble service URLs and feature flags into a JSON document the client fetches on load (the bootstrapping contract for all clients, including mobile).
- **Static hosting**: serve `dist/` via `express-static-gzip` with long-lived caching, except `index.html`/branding (no-cache); SPA fallback to `index.html`.
- **File download** (`GET/HEAD /files`, `/files/*`): resolve the workspace from the token (`getWorkspaceInfo` against account), `stat`/`get`/`partial` from the storage adapter, with HTTP range and conditional (etag/last-modified) support.
- **Image preview**: when an `image/*` blob is requested with `?size=` and an `Accept` for a supported format, resize/transcode via `sharp` (avif/webp/heif/jpeg/png) and cache the result as a derived blob.
- **File upload** (`POST /files`): store the uploaded file under the token's workspace; **delete** (`DELETE /files`).
- **Import** (`GET/POST /import`): fetch a remote URL server-side and store it as a blob.
- **Branding** and statistics endpoints.

## Key endpoints/methods

| Method / Path | Purpose |
|---------------|---------|
| `GET /config.json` | Runtime client config (see fields below); `Cache-Control: no-cache`. |
| `GET/HEAD /files`, `/files/*` | Download/head a blob (range + conditional + image resize). |
| `POST /files`, `/files/*` | Upload a blob (bearer token → workspace). |
| `DELETE /files`, `/files/*` | Delete a blob. |
| `GET/POST /import` | Server-side fetch a URL into storage. |
| `GET /api/v1/statistics` | Metrics/health. |
| `GET *` (SPA fallback) | Serve `index.html` for client-side routes. |

### `config.json` fields (from `server/front/src/index.ts`)
`ACCOUNTS_URL`, `UPLOAD_URL`, `FILES_URL`, `MODEL_VERSION`, `VERSION`, `REKONI_URL`, `TELEGRAM_URL`, `GMAIL_URL`, `CALENDAR_URL`, `COLLABORATOR`, `COLLABORATOR_URL`, `LINK_PREVIEW_URL`, `STREAM_URL`, `BRANDING_URL`, `PREVIEW_URL`, `PUSH_PUBLIC_KEY`, `DISABLE_SIGNUP`, `HIDE_LOCAL_LOGIN`, `MAIL_URL`, `BILLING_URL`, `PAYMENT_URL`, `PULSE_URL`, `HULYLAKE_URL`, `DATALAKE_URL`, plus any `extraConfig` entries.

## Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `FRONT_URL` | `http://huly.local:8087` | Public base URL. |
| `SERVER_PORT` / port arg | `8087` (`8088`) | Listen port. |
| `PUBLIC_DIR` | `cwd()` | Directory containing `dist/`. |
| `ACCOUNTS_URL` | `http://huly.local:3000` | → `config.json` `ACCOUNTS_URL`. |
| `UPLOAD_URL` | `/files` | Upload endpoint advertised to clients. |
| `FILES_URL` | `.../blob/:workspace/:blobId/:filename` | Download URL pattern. |
| `COLLABORATOR_URL` | `ws://huly.local:3078` | Collaborator WS URL. |
| `DATALAKE_URL` | `http://huly.local:4030` | Datalake URL. |
| `HULYLAKE_URL` | `http://huly.local:8096` | Hulylake URL. |
| `PREVIEW_URL` | `http://huly.local:4040` | Preview URL. |
| `STREAM_URL` | `http://huly.local:1080/recording` | Stream URL. |
| `PULSE_URL` | `ws://huly.local:8099/ws` | Pulse WS URL. |
| `BRANDING_URL` | `http://huly.local:8087/branding.json` | Branding doc. |
| `REKONI_URL`, `MAIL_URL`, `PAYMENT_URL`, `CALENDAR_URL`, `GMAIL_URL`, `TELEGRAM_URL` | — | Advertised integration URLs. |
| `DISABLE_SIGNUP` / `HIDE_LOCAL_LOGIN` | — | UI auth flags. |
| `STORAGE_CONFIG` | — | MinIO/datalake for `/files`. |

## Cross-references
- The config contract clients consume: [front-config](../api/front-config.md)
- Storage that `/files` proxies: [datalake](datalake.md), [storage-blobs](../concepts/storage-blobs.md)
- Where clients go after reading config: [account](account.md), [transactor](transactor.md), [collaborator](collaborator.md)
- Client bootstrap concept: [client-protocol](../concepts/client-protocol.md)

## Gotchas
- **`config.json` is the client bootstrap.** Clients (including mobile) read it first to discover every other service URL; a wrong value here breaks the app even if backends are healthy. It is served `no-cache` so changes take effect immediately.
- `/files` resolves the workspace from the token via account's `getWorkspaceInfo`, and validates the URL's workspace UUID against the token (403 on mismatch).
- Image resize is cached as a derived blob keyed `…%preview%<size><format>`; size is clamped to ≤2048 and only `avif/webp/heif/jpeg/png` are produced (gif is passed through unresized).
- The SPA fallback (`GET *`) refuses known asset extensions (returns 404) and rejects paths escaping `dist` (403); everything else returns `index.html`.
- `FILES_URL` in config points at datalake's blob URL pattern, not necessarily front's `/files` — downloads can go directly to datalake.
