# Datalake

> Blob storage service (port `4030`). A REST front-end over S3-compatible object storage (MinIO): it stores blob bytes in buckets and blob metadata in CockroachDB, supporting form-data, presigned-S3, and multipart uploads plus range/conditional downloads, per-workspace stats, and an in-memory small-blob cache.

## Where in code
- `services/datalake/pod-datalake/src/main.ts` -- process entry.
- `services/datalake/pod-datalake/src/server.ts` -- Express app, full route table, auth middleware, `listen`.
- `services/datalake/pod-datalake/src/config.ts` -- `Config` and `BUCKETS` parsing into `BucketConfig[]`.
- `services/datalake/pod-datalake/src/datalake/datalake.ts`, `db.ts`, `cache.ts`, `queue.ts` -- core datalake logic, metadata DB, small-blob cache.
- `services/datalake/pod-datalake/src/s3/` -- S3 client/bucket abstraction.
- `services/datalake/pod-datalake/src/handlers/` -- `blob.ts`, `meta.ts`, `s3.ts`, `multipart.ts` request handlers.

## Purpose
Datalake is the platform's blob abstraction. Rather than letting every service talk to MinIO directly, datalake centralizes blob writes/reads, keeps authoritative metadata (size, content type, etag, parent, custom meta) in CockroachDB, and offers multiple upload strategies (simple form-data, direct-to-S3 presigned, and resumable multipart) so large media can be uploaded efficiently.

## Responsibilities
- **Blob CRUD**: head/get (with range + conditional headers), delete (single, by-filename, and bulk per workspace), list.
- **Metadata**: get/put/patch arbitrary blob metadata; set a blob's parent.
- **Uploads**: form-data upload; S3 presigned-upload params + commit; multipart start/part/complete/abort.
- **Storage backend**: map workspaces/blobs to S3 buckets per the `BUCKETS` config; store bytes in MinIO, metadata in `DB_URL`.
- **Cache**: in-memory small-blob cache (enabled by default) to avoid round-trips for tiny blobs.
- **Auth**: bearer-token middleware (`withAuthorization`, `withAdminAuthorization`, `withOptionalAuth` when `Secure`); read endpoints can be public when `Secure=false`.
- **Workspace/blob scoping middleware** (`withWorkspace`, `withBlob`) resolves and validates path params.

## Key endpoints/methods

| Method / Path | Handler | Purpose |
|---------------|---------|---------|
| `GET /stats/:workspace` | `workspaceStats` | Per-workspace blob stats (admin). |
| `GET /blob/:workspace` | `listBlobs` | List blobs (admin). |
| `HEAD /blob/:workspace/:name[/:filename]` | `headBlob` | Blob metadata headers. |
| `GET /blob/:workspace/:name[/:filename]` | `getBlob` | Download (range + conditional). |
| `DELETE /blob/:workspace/:name[/:filename]` | `deleteBlob` | Delete a blob. |
| `DELETE /blob/:workspace` | `deleteBlobList` | Bulk delete. |
| `PATCH /blob/:workspace/:name/parent` | `patchParent` | Set blob parent. |
| `GET /meta/:workspace/:name` | `getMeta` | Read metadata. |
| `PUT /meta/:workspace/:name` | `putMeta` | Replace metadata. |
| `PATCH /meta/:workspace/:name` | `patchMeta` | Merge metadata. |
| `POST /upload/form-data/:workspace` | `uploadFormData` | Multipart/form-data upload. |
| `GET /upload/s3/:workspace` | `s3UploadParams` | Presigned S3 upload params. |
| `POST /upload/s3/:workspace/:name` | `s3Upload` | Commit an S3-uploaded blob. |
| `POST /upload/multipart/:workspace/:name` | `multipartUploadStart` | Begin multipart upload. |
| `PUT /upload/multipart/:workspace/:name/part` | `multipartUploadPart` | Upload a part. |
| `POST /upload/multipart/:workspace/:name/complete` | `multipartUploadComplete` | Finish. |
| `POST /upload/multipart/:workspace/:name/abort` | `multipartUploadAbort` | Cancel. |
| `GET /api/v1/statistics` | — | Metrics/health. |

## Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `PORT` | `4030` | HTTP listen port. |
| `SECRET` | `secret` | Bearer-token verification secret. |
| `ACCOUNTS_URL` | `http://huly.local:3000` | Account service. |
| `DB_URL` | (required) | CockroachDB for blob metadata. |
| `BUCKETS` | `blobs,eu\|http://minio:9000?accessKey=...&secretKey=...` | `;`-separated bucket configs: `bucket,location\|endpoint?accessKey&secretKey&region`. |
| `SECURE` | `false` | If `true`, reads require auth (`withOptionalAuth`). |
| `READONLY` | `false` | Reject writes (`withReadonly`). |
| `CLEANUP_INTERVAL` | `30000` | Cleanup interval (ms). |
| `CACHE_ENABLED` | `true` | Enable small-blob cache. |
| `CACHE_BLOB_SIZE` | `64` (KB) | Max cached blob size. |
| `CACHE_BLOB_COUNT` | `1000` | Max cached blobs. |

## Cross-references
- REST contract details: [datalake-api](../api/datalake-api.md)
- Blob model & storage strategy: [storage-blobs](../concepts/storage-blobs.md)
- Front proxies uploads/downloads here: [front](front.md)
- Transactor blob domain uses storage: [transactor](transactor.md)
- Collaborator persists docs to storage: [collaborator](collaborator.md)
- Token issuance: [account](account.md)

## Gotchas
- **Bytes in MinIO, metadata in CockroachDB.** The two can drift if one write half-fails; `stat`/metadata is authoritative for size/etag/content-type.
- `BUCKETS` syntax is strict: `bucket,location|endpoint?accessKey=..&secretKey=..&region=..`, multiple separated by `;`. A malformed entry throws at startup.
- Read endpoints are public unless `SECURE=true` (they use `withOptionalAuth`); write/delete always require a bearer token.
- Three upload paths exist for different sizes/clients — prefer S3-presigned or multipart for large media to avoid streaming through the pod.
- The small-blob cache only holds blobs ≤ `CACHE_BLOB_SIZE` (64KB default); larger blobs always hit S3.
- One known handler is spelled `multipartUploadAvort` (abort) — cosmetic, but greppable.
