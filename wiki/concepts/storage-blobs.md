# Blob Storage (Datalake & Hulylake)

> How Huly stores binary files: the **datalake** service (`:4030`) and the S3-compatible **hulylake** adapter (`:8096`), the download-URL convention, form uploads, and S3-style multipart uploads with progress.

## Where in code

| Component | File | Purpose |
|-----------|------|---------|
| Client upload primitives | `foundations/core/packages/storage-client/src/upload.ts` | `uploadXhr` (form/PUT) + `uploadMultipart` (5 MB chunks) |
| `FileStorage` interface | `foundations/core/packages/storage-client/src/types.ts` | `getFileUrl`, `uploadFile`, `getFileMeta`, `deleteFile` |
| Datalake client | `foundations/core/packages/storage-client/src/client/datalake.ts` | Download URL + form/multipart upload dispatch |
| Hulylake client | `foundations/core/packages/storage-client/src/client/hulylake.ts` | Single `PUT` upload to `/api/{ws}/{file}` |
| Storage selector | `foundations/core/packages/storage-client/src/client/index.ts` | `createFileStorage` picks datalake → hulylake → front |
| Datalake server routes | `services/datalake/pod-datalake/src/server.ts` | Express routes for blob/meta/upload |
| Multipart handlers | `services/datalake/pod-datalake/src/handlers/multipart.ts` | start/part/complete/abort |
| `DOMAIN_BLOB` | `foundations/core/packages/core/src/classes.ts` | Storage partition for blob metadata docs |

## Purpose

Huly's transactor handles structured `Doc`/`Tx` data, but **binary files** (attachments, images, drive files, document snapshots, recordings) are too large to live in transactions. They are stored separately in object storage (MinIO) and addressed by a **blob UUID**. Two HTTP front-ends expose that storage:

- **datalake** (`:4030`) — Huly's own blob-management service. Stores file metadata in CockroachDB, blobs in MinIO buckets, and offers form upload, S3-style multipart upload, previews, and per-blob metadata.
- **hulylake** (`:8096`) — an S3-compatible storage adapter exposing a simpler `PUT`/`GET` `/api/{workspace}/{file}` interface.

A client picks **one** of these at runtime (from `config.json`); they are alternative back-ends behind the same `FileStorage` interface, not used together.

## Details

### Selecting a back-end

`createFileStorage` chooses the implementation by which URL is configured (datalake wins if present):

```typescript
export interface FileStorageConfig {
  uploadUrl: string
  datalakeUrl?: string
  hulylakeUrl?: string
}

export function createFileStorage (config: FileStorageConfig): FileStorage {
  const { uploadUrl, datalakeUrl, hulylakeUrl } = config
  if (datalakeUrl !== undefined && datalakeUrl !== '') return new DatalakeStorage(datalakeUrl)
  if (hulylakeUrl !== undefined && hulylakeUrl !== '') return new HulylakeStorage(hulylakeUrl)
  return new FrontStorage(uploadUrl) // legacy fallback through the front service
}
```

All three implement the same contract:

```typescript
export interface FileStorage {
  getFileUrl: (workspace: string, file: string, filename?: string) => string
  getCookiePath: (workspace: string) => string
  getFileMeta: (token: string, workspace: string, file: string) => Promise<Record<string, any>>
  uploadFile: (token: string, workspace: string, uuid: string, file: File, options?: FileStorageUploadOptions) => Promise<void>
  deleteFile: (token: string, workspace: string, file: string) => Promise<void>
}
```

### Download URL convention (datalake)

```typescript
getFileUrl (workspace, file, filename?) {
  const path = filename !== undefined
    ? `/blob/${workspace}/${file}/${filename}`
    : `/blob/${workspace}/${file}`
  return concatLink(this.baseUrl, path)
}
```

So a downloadable file is:

```
{DATALAKE_URL}/blob/{workspace}/{uuid}/{filename}
```

`{filename}` is optional and only affects the `Content-Disposition`/display name — the **`uuid` is the real identifier**. Authentication is a bearer token; the datalake route uses `withOptionalAuth(config.Secure)`, so when `Secure` is off a blob may be fetched without a token (handy for public previews). The hulylake URL shape differs: `{HULYLAKE_URL}/api/{workspace}/{file}`.

The server exposes `GET` and `HEAD` on both the 2- and 3-segment forms:

```
GET  /blob/:workspace/:name
GET  /blob/:workspace/:name/:filename
HEAD /blob/:workspace/:name
```

### Upload path selection (datalake)

`DatalakeStorage.uploadFile` chooses between a single form POST and multipart based on a **10 MB** threshold:

```typescript
async uploadFile (token, workspace, uuid, file, options?) {
  if (file.size <= 10 * 1024 * 1024) {
    const formData = new FormData()
    formData.append('file', file, uuid)
    await uploadXhr({
      url: concatLink(this.baseUrl, `/upload/form-data/${encodeURIComponent(workspace)}`),
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: formData
    }, options)
  } else {
    const url = concatLink(this.baseUrl,
      `/upload/multipart/${encodeURIComponent(workspace)}/${encodeURIComponent(uuid)}`)
    await uploadMultipart({ url, headers: { Authorization: `Bearer ${token}` }, body: file }, options)
  }
}
```

Hulylake instead always does **one streaming `PUT`** with `Content-Type` / `Content-Length` headers:

```typescript
await uploadXhr({
  url: this.getFileUrl(workspace, uuid),
  method: 'PUT',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': file.type, 'Content-Length': file.size.toString() },
  body: file
}, options)
```

### S3-style multipart upload (5 MB chunks)

`uploadMultipart` implements the classic S3 init → upload-parts → complete dance. Chunk size is a hard **5 MB**:

```typescript
const CHUNK_SIZE = 5 * 1024 * 1024 // 5MB chunks
const { uploadId } = await multipartUploadCreate(url, { ...headers, 'Content-Type': body.type }, signal)

const parts: Array<{ partNumber: number, etag: string }> = []
const totalParts = Math.ceil(body.size / CHUNK_SIZE)

for (let partNumber = 1; partNumber <= totalParts; partNumber++) {
  const chunk = body.slice(start, end)
  const { etag } = await multipartUploadPart(url, headers, uploadId, partNumber, chunk, partOptions)
  parts.push({ partNumber, etag })
}
await multipartUploadComplete(url, headers, uploadId, parts, signal)
```

The four HTTP operations map onto datalake routes (`services/datalake/pod-datalake/src/server.ts`):

| Step | Method + path | Returns |
|------|---------------|---------|
| init | `POST /upload/multipart/:workspace/:name` | `{ uuid, uploadId }` |
| part | `PUT /upload/multipart/:workspace/:name/part?uploadId=&partNumber=` | `{ etag }` |
| complete | `POST /upload/multipart/:workspace/:name/complete?uploadId=` (body `{ parts }`) | `200` |
| abort | `POST /upload/multipart/:workspace/:name/abort?uploadId=` | `200` |

ETags returned by each part PUT must be collected and replayed in the `complete` body, exactly as S3 requires. If any part fails, the client calls **abort** to release the in-progress upload.

```
client                          datalake (:4030)
  │  POST .../multipart/ws/uuid ──────────────▶  { uuid, uploadId }
  │                                              (S3 CreateMultipartUpload)
  │  PUT  .../part?uploadId&partNumber=1 ──────▶  { etag: "..." }
  │  PUT  .../part?uploadId&partNumber=2 ──────▶  { etag: "..." }
  │      ... (5 MB each) ...
  │  POST .../complete  { parts: [{n,etag}] } ─▶  200  (S3 CompleteMultipartUpload)
  ▼
```

### Progress reporting

Both paths surface progress through `FileStorageUploadOptions`:

```typescript
export interface FileStorageUploadProgress { loaded: number, total: number, percentage: number }
export interface FileStorageUploadOptions {
  onProgress?: (progress: FileStorageUploadProgress) => void
  signal?: AbortSignal
}
```

`uploadXhr` wires `xhr.upload.onprogress`. For multipart, per-part progress is rebased onto the **whole file** (`loaded = uploaded + progress.loaded`) so callers see a single 0–100% across all chunks. An `AbortSignal` cancels the XHR and triggers a multipart abort.

### Per-blob metadata, parent, and stats

Datalake exposes additional routes beyond up/download:

```
GET   /meta/:workspace/:name          getFileMeta → Record<string, any>
PUT   /meta/:workspace/:name          replace metadata
PATCH /meta/:workspace/:name          merge metadata
PATCH /blob/:workspace/:name/parent   associate blob with a parent doc
GET   /stats/:workspace               workspace blob stats (admin)
GET   /blob/:workspace                list blobs (admin)
DELETE /blob/:workspace/:name         delete one blob
```

### DOMAIN_BLOB

Blob **metadata** records live in the `DOMAIN_BLOB` storage partition:

```typescript
export const DOMAIN_BLOB = 'blob' as Domain
```

This separates blob bookkeeping from `DOMAIN_TX`/`DOMAIN_MODEL` so large-file metadata never bloats the transaction log. The binary bytes themselves are in MinIO, not in any domain.

### Previews & streaming

Thumbnails/previews are served by the **preview** service (`PREVIEW_URL`, `:4040`), which reads from datalake. Video is streamed (HLS) by the **stream** service (`STREAM_URL`, `:1080`), whose `STREAM_ENDPOINT_URL` points back at datalake (`datalake://huly.local:4030`). These are read-side derivatives of stored blobs — clients fetch previews/HLS rather than the raw blob for media.

### Key properties

| Property | Value | Description |
|----------|-------|-------------|
| Multipart chunk size | 5 MB | `CHUNK_SIZE = 5 * 1024 * 1024` |
| Form-vs-multipart threshold | 10 MB | datalake client switches above this |
| Blob id | UUID | the `uuid` segment, not the filename |
| Auth | Bearer JWT | `withOptionalAuth` on GET/HEAD when `Secure` off |
| Metadata domain | `DOMAIN_BLOB` | `'blob'` |

## Cross-references

- [communication](communication.md) — message attachments are `BlobAttachment`s referencing blob IDs
- [collaboration-crdt](collaboration-crdt.md) — collaborative doc snapshots are stored as blobs (`MarkupBlobRef`)
- [fulltext-search](fulltext-search.md) — the indexer pulls blobs and sends them to rekoni for text extraction
- Service: [datalake](../services/datalake.md)
- Flow: [file-upload-flow](../flows/file-upload-flow.md)
- Plugins: [drive](../plugins/drive.md), [document](../plugins/document.md)

## Gotchas

- **`uuid` ≠ filename.** The trailing `/{filename}` is cosmetic; the blob is keyed by the UUID segment. Generate the UUID client-side and pass it as `uuid` to `uploadFile`.
- **Datalake and hulylake are alternatives, not a pipeline.** `createFileStorage` returns the first configured one; only one is active per workspace config.
- **ETags are mandatory for completion.** A multipart `complete` with missing/out-of-order ETags fails server-side — collect every part's ETag.
- **Multipart only above 10 MB (datalake client).** Smaller files always go through the single `POST /upload/form-data`. Hulylake never multiparts — it streams one `PUT`.
- **`uploadXhr` uses `XMLHttpRequest`.** A non-browser client (Flutter/native) must reimplement the same init/part/complete HTTP sequence; the TS code is a reference spec, not a portable dependency.
- **Server route typo:** the abort route is registered as `multipartUploadAvort` internally — the HTTP path is still `/abort`.
