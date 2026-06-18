# Front Config (`GET /config.json`)

> Runtime service-discovery document served by the **front** service. A client supplies only its instance base URL and fetches this JSON to learn every backend URL — nothing is hardcoded in the client.

## Where in code
- `server/front/src/index.ts` -- the `app.get('/config.json', ...)` handler that assembles the response object
- `server/front/src/starter.ts` -- reads env vars into the `config` object used by the handler
- consumed by the web client in `plugins/workbench-resources/src/connect.ts`

## Endpoints

### `GET /config.json`

No request body, no auth. Returns a flat JSON object of URLs and version markers. Cache headers are `no-store, no-cache, must-revalidate` (the document is never cached).

**Response fields** (each maps directly to a field on the front service `config` object):

| Field | Example | Use |
|-------|---------|-----|
| `ACCOUNTS_URL` | `http://huly.local:3000` | Account JSON-RPC base URL (login + workspace selection). |
| `UPLOAD_URL` | `/files` | Legacy/front upload endpoint. |
| `FILES_URL` | `http://huly.local:4030/blob/:workspace/:blobId/:filename` | File **download** URL pattern (templated). |
| `MODEL_VERSION` | `0.7.0` | Required model version — client compatibility check. |
| `VERSION` | `0.7.0` | Front build version. |
| `REKONI_URL` | `http://huly.local:4004` | Document-intelligence service. |
| `TELEGRAM_URL` | | Telegram integration service. |
| `GMAIL_URL` | | Gmail integration service. |
| `CALENDAR_URL` | | Calendar integration service. |
| `COLLABORATOR` | | Legacy collaborator field. |
| `LINK_PREVIEW_URL` | | Link-preview service. |
| `STREAM_URL` | `http://huly.local:1080/recording` | Video streaming (HLS). |
| `COLLABORATOR_URL` | `ws://huly.local:3078` | Real-time collaborative editing (Y.js CRDT). |
| `BRANDING_URL` | `http://huly.local:8087/branding.json` | Logos/colors override document. |
| `PREVIEW_URL` | `http://huly.local:4040` | Image/document thumbnails. |
| `PUSH_PUBLIC_KEY` | (optional) | Web/native push public key. |
| `DISABLE_SIGNUP` | `false` | Hides sign-up UI when true. |
| `HIDE_LOCAL_LOGIN` | `false` | Hides email/password login when true. |
| `MAIL_URL` | | Mail service. |
| `BILLING_URL` | | Billing service. |
| `PAYMENT_URL` | `http://huly.local:3040` | Payment service. |
| `PULSE_URL` | `ws://huly.local:8099/ws` | HulyPulse push notifications (WebSocket). |
| `HULYLAKE_URL` | `http://huly.local:8096` | S3-compatible storage adapter. |
| `DATALAKE_URL` | `http://huly.local:4030` | Blob storage service (up/download). |

Any keys present in the front service `extraConfig` are spread in on top of the above, so a deployment may expose additional fields.

**Response:**
```json
{
  "ACCOUNTS_URL": "http://huly.local:3000",
  "UPLOAD_URL": "/files",
  "FILES_URL": "http://huly.local:4030/blob/:workspace/:blobId/:filename",
  "MODEL_VERSION": "0.7.0",
  "VERSION": "0.7.0",
  "COLLABORATOR_URL": "ws://huly.local:3078",
  "DATALAKE_URL": "http://huly.local:4030",
  "HULYLAKE_URL": "http://huly.local:8096",
  "PREVIEW_URL": "http://huly.local:4040",
  "STREAM_URL": "http://huly.local:1080/recording",
  "PULSE_URL": "ws://huly.local:8099/ws",
  "BRANDING_URL": "http://huly.local:8087/branding.json",
  "PUSH_PUBLIC_KEY": "..."
}
```

**Error codes:** none meaningful — the handler always returns `200` with whatever config the front service was started with. Missing env vars surface as `undefined`/absent fields, not errors.

## Auth

None. `/config.json` is public and unauthenticated (it lists only URLs, never secrets). The same front service also exposes `GET /api/v1/statistics?token=<jwt>`, which **does** require a valid token and returns `401` on `TokenError`.

## Cross-references

- [account-api](account-api.md) — `ACCOUNTS_URL` points here (login + workspace selection)
- [transactor-rpc](transactor-rpc.md) — the transactor `endpoint` is returned by the account service, not by config.json
- [datalake-api](datalake-api.md) — `DATALAKE_URL` / `FILES_URL` / `HULYLAKE_URL`
- [front service](../services/front.md)
- [storage-blobs concept](../concepts/storage-blobs.md)
- [login-flow](../flows/login-flow.md)

## Gotchas

- `FILES_URL` is a **template** with literal `:workspace`, `:blobId`, `:filename` placeholders — substitute them client-side; it is not a ready-to-fetch URL.
- The transactor WebSocket URL is **not** in `config.json`. It is resolved per-workspace by the account service (`selectWorkspace` → `endpoint`), because routing depends on the workspace UUID and region.
- `COLLABORATOR` and `COLLABORATOR_URL` are distinct fields; use `COLLABORATOR_URL` for the WebSocket.
- Fields are emitted whether or not the env var is set, so expect some values to be `undefined`/absent. Validate before use.
- The document is served with no-cache headers — re-fetch on each app start to pick up deployment changes.
