# Datalake API (Blob Storage)

> The **datalake** service is a plain HTTP/REST blob store backed by S3-compatible object storage. It exposes blob download, form-data upload, S3-style multipart upload, and per-blob metadata. Every authenticated route is scoped to a workspace via the JWT, and the token's `workspace` claim must match the workspace in the URL.

## Where in code
- `services/datalake/pod-datalake/src/server.ts` -- Express route table (all endpoints + their auth middleware)
- `services/datalake/pod-datalake/src/middleware.ts` -- `withAuthorization`, `withBlob`, `withWorkspace`, `withAdminAuthorization`, `withOptionalAuth`, `withReadonly`
- `services/datalake/pod-datalake/src/handlers/blob.ts` -- get/head/delete/list, form-data upload
- `services/datalake/pod-datalake/src/handlers/multipart.ts` -- multipart start/part/complete/abort
- `services/datalake/pod-datalake/src/handlers/s3.ts` -- direct-to-S3 upload params + create
- `services/datalake/pod-datalake/src/handlers/meta.ts` -- blob metadata get/put/patch

Base URL = `DATALAKE_URL` from [config.json](front-config.md). `{ws}` is the workspace **UUID**, `{name}` the blob id, `{filename}` an optional display name.

## Endpoints

### `GET /blob/{ws}/{name}` and `GET /blob/{ws}/{name}/{filename}`

Download a blob. Supports HTTP `Range` (returns `206` with `Content-Range` for partial fetches). Sets `Content-Type`, `Content-Length`, `ETag`, `Last-Modified`, and a `Content-Disposition` of `inline` for safe types (`application/pdf`, `image/png|jpeg|gif|webp`) or `attachment` otherwise.

**Auth:** `withOptionalAuth(config.Secure)` — required only if the service runs in `Secure` mode; otherwise public read.

| Code | Meaning |
|------|---------|
| 200 | Full blob |
| 206 | Partial (range) |
| 404 | Blob not found |

### `HEAD /blob/{ws}/{name}[/{filename}]`

Metadata-only (size, content-type, etag) without the body. Same auth as GET. `404` if absent.

### `DELETE /blob/{ws}/{name}[/{filename}]`

Delete one blob. **Auth required** (`withAuthorization` + `withBlob`). `204` on success.

### `DELETE /blob/{ws}`

Delete many. Body `{ "names": ["..."] }`. **Auth required.** `204` on success.

### `GET /blob/{ws}` (list)

List blobs. Query: `cursor`, `limit`, `derived=true`. **Admin/system token only** (`withAdminAuthorization`).

### `GET /stats/{ws}`

Workspace blob statistics. **Admin/system token only**.

### `POST /upload/form-data/{ws}` (simple upload)

`multipart/form-data` upload of one or more files (via `express-fileupload`). Server computes the SHA-256, stores each file, and returns per-file results. Optional `Cache-Control` request header is propagated to the stored blob.

**Auth required** (`withAuthorization` + `withWorkspace`).

**Response:**
```json
[
  { "key": "file", "id": "report.pdf", "metadata": { "etag": "...", "size": 12345, "contentType": "application/pdf" } }
]
```
On a per-file failure the entry is `{ "key": "...", "error": "..." }` instead.

### S3-style multipart upload (large files)

All **auth required** (`withAuthorization` + `withBlob`).

1. **Start** — `POST /upload/multipart/{ws}/{name}`
   Headers `Content-Type`, optional `Last-Modified`. Returns:
   ```json
   { "uuid": "<blob-uuid>", "uploadId": "<uuid>/<s3UploadId>" }
   ```
2. **Upload part** — `PUT /upload/multipart/{ws}/{name}/part?uploadId={uploadId}&partNumber={n}`
   Raw body = the chunk; `Content-Length` header sets the part size. Returns the part descriptor `{ partNumber, etag }`.
3. **Complete** — `POST /upload/multipart/{ws}/{name}/complete?uploadId={uploadId}`
   Body `{ "parts": [{ "partNumber": 1, "etag": "..." }, ...] }`. Finalizes and registers blob metadata. Returns the blob metadata.
4. **Abort** — `POST /upload/multipart/{ws}/{name}/abort?uploadId={uploadId}` → `204`.

`uploadId` is the opaque `"<uuid>/<s3UploadId>"` string returned by start; pass it verbatim.

### Direct-to-S3 upload (presign-style)

- `GET /upload/s3/{ws}` → `{ "location": "...", "bucket": "..." }` (where to PUT). **Auth required.**
- `POST /upload/s3/{ws}/{name}` with body `{ "filename": "..." }` → registers a blob whose bytes were already uploaded directly to S3 under `filename`. **Auth required.**

### Blob metadata

- `GET /meta/{ws}/{name}` → metadata object (`404` if absent). Auth optional (`withOptionalAuth`).
- `PUT /meta/{ws}/{name}` — replace metadata (JSON object body). **Auth required.** `404` if blob absent.
- `PATCH /meta/{ws}/{name}` — merge metadata. **Auth required.**
- `PATCH /blob/{ws}/{name}/parent` — set/clear a blob's `parent` (body `{ "parent": "<name>" | null }`). **Auth required.**

### Statistics

`GET /api/v1/statistics?token={jwt}` — service metrics; `401` on `TokenError`.

## Auth

Token is read by `extractToken` from the `Authorization: Bearer <jwt>` header (or a `token` cookie). The JWT is decoded by `@hcengineering/server-token`. Middleware rules:

| Middleware | Rule |
|-----------|------|
| `withAuthorization` | Token required; **rejects** tokens with `extra.guest === 'true'` or `extra.readonly === 'true'` → `401`. |
| `withWorkspace` / `withBlob` | Token's `workspace` claim must equal the URL `{ws}`, **or** the account is the system account, **or** `extra.admin === 'true'`. Mismatch → `401`. |
| `withAdminAuthorization` | Only system account or `extra.admin === 'true'`. |
| `withOptionalAuth(secure)` | Enforces `withAuthorization` only when the service is in `Secure` mode; otherwise skips auth (public read). |
| `withReadonly` | When the service is read-only, blocks all non-GET/HEAD methods → `403`. |

`{ws}` must be a valid UUID or the request fails `400` ("Missing workspace"); `{name}` must be present or `400`.

## Cross-references

- [front-config](front-config.md) — `DATALAKE_URL`, `FILES_URL` (download template)
- [storage-blobs concept](../concepts/storage-blobs.md)
- [datalake service](../services/datalake.md)
- [token-package](../security/token-package.md)
- [authentication](../security/authentication.md)
- [file-upload-flow](../flows/file-upload-flow.md)

## Gotchas

- The workspace path segment is the workspace **UUID** and is validated as a UUID; the URL slug used by the account API will not work here.
- The token `workspace` claim is checked against the URL — a token for workspace A cannot read/write workspace B (unless admin/system).
- Reads can be public (`withOptionalAuth`) when the deployment is not in `Secure` mode; do not assume blob URLs are protected by default.
- `withAuthorization` deliberately **rejects guest and read-only tokens** for writes/deletes even though they are otherwise valid.
- `Content-Disposition` is `inline` only for the small safe-type allowlist; everything else downloads as an attachment.
- The multipart `uploadId` encodes both the blob uuid and the S3 upload id joined by `/`; treat it as opaque and pass it unchanged.
