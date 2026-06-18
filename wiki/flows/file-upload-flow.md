# File Upload Flow

> How a client uploads a blob to the datalake — a single multipart **form-data POST** for small files, or an **S3-style multipart** upload (init → PUT 5 MB parts → complete with ETags) for large files — reports progress, and then references the resulting blob from a `Doc`.

## Where in code
- `foundations/core/packages/storage-client/src/client/datalake.ts` -- `DatalakeStorage.uploadFile` (form-data vs multipart branch, `getFileUrl`)
- `foundations/core/packages/storage-client/src/upload.ts` -- `uploadXhr` (form/PUT + progress), `uploadMultipart` (init/part/complete/abort, 5 MB chunks)
- `foundations/core/packages/storage-client/src/types.ts` -- `FileStorageUploadOptions { signal, onProgress }`, `UploadProgress`

## Sequence

```
 Client                         Datalake (:4030)                         Doc / Transactor
   |                                 |                                        |
   |  uploadFile(token, ws, uuid, file)                                      |
   |  size <= 10 MB?  ── yes ──▶ form-data path                              |
   |                                 |                                        |
   |  POST /upload/form-data/{ws}    |                                        |
   |  multipart body: file=<uuid>    |                                        |
   |  Authorization: Bearer {token}  |                                        |
   |-------------------------------->|  store blob                            |
   |  200 (onProgress: loaded/total) |                                        |
   |<--------------------------------|                                        |
   |                                                                          |
   |  size > 10 MB ── multipart path (5 MB chunks) ──────────────────────    |
   |  POST /upload/multipart/{ws}/{uuid}        → { uuid, uploadId }          |
   |-------------------------------->|                                        |
   |  PUT  .../part?uploadId&partNumber=1  body=chunk → { etag }              |
   |-------------------------------->|  (repeat per 5 MB chunk, accumulate)   |
   |  POST .../complete?uploadId  body={ parts:[{partNumber,etag}] }          |
   |-------------------------------->|  assemble blob                         |
   |                                 |                                        |
   |  reference blob from a Doc:  updateDoc(..., { attachment: <uuid> })      |
   |------------------------------------------------------------------------->|
```

## Steps

| Step | Action | Error code on failure |
|------|--------|----------------------|
| 1 | Generate a blob `uuid` (the stable blob id) for the file. | |
| 2 | If `file.size <= 10 MB`: build `FormData` with `file=<uuid>` and `POST /upload/form-data/{workspace}` (Bearer token) via `uploadXhr`. | `UPLOAD-FORM-001` |
| 3 | Else (large file): `POST /upload/multipart/{workspace}/{uuid}` → `{ uuid, uploadId }`. | `MULTIPART-INIT-001` |
| 4 | For each 5 MB chunk: `PUT {url}/part?uploadId={id}&partNumber={n}` with the chunk; collect the returned `etag`. | `MULTIPART-PART-001` |
| 5 | `POST {url}/complete?uploadId={id}` with `{ parts: [{ partNumber, etag }] }` to assemble the blob. | `MULTIPART-COMPLETE-001` |
| 6 | On any failure mid-multipart, `POST {url}/abort?uploadId={id}` to discard partial state. | |
| 7 | Reference the blob from a `Doc` (e.g. create an `attachment` / set a blob-ref attribute) via a normal tx — see [transaction-flow](transaction-flow.md). | |
| 8 | Download/preview later via `getFileUrl(workspace, uuid, filename?)` → `{DATALAKE_URL}/blob/{ws}/{uuid}[/{filename}]`. | |

## Code

```typescript
import { DatalakeStorage } from '@hcengineering/storage-client'
import { generateId } from '@hcengineering/core'

const storage = new DatalakeStorage(config.DATALAKE_URL)
const blobId = generateId() // the uuid used as the blob's id

await storage.uploadFile(token, workspace, blobId, file, {
  signal: abortController.signal,
  onProgress: ({ loaded, total, percentage }) => updateBar(percentage)
})
// uploadFile internally picks form-data (<=10 MB) or 5 MB-chunk multipart automatically.

// Now reference it from a Doc — e.g. attach to an issue:
await ops.addCollection(
  attachment.class.Attachment, space,
  parentId, parentClass, 'attachments',
  { file: blobId, name: file.name, size: file.size, type: file.type, lastModified: file.lastModified }
)

// Build a download URL later:
const url = storage.getFileUrl(workspace, blobId, file.name)
```

## Prerequisites

- A valid workspace-scoped `token` and the `DATALAKE_URL` from `config.json` (see [login-flow](login-flow.md)).
- A unique blob `uuid` per file (typically `generateId()`).
- The parent `Doc` and its `space` exist if you intend to attach the blob.

## Error handling

```typescript
const controller = new AbortController()

try {
  await storage.uploadFile(token, workspace, blobId, file, {
    signal: controller.signal,
    onProgress: p => updateBar(p.percentage)
  })
} catch (err) {
  // Multipart uploads auto-call /abort on any error to clean up server-side partial state.
  // form-data path: uploadXhr rejects on non-2xx, network error, timeout, or abort.
  showUploadError(err)
}

// Cancel an in-flight upload:
controller.abort() // → 'Upload aborted'; multipart loop throws at the next throwIfAborted checkpoint
```

## Cross-references

- [transaction-flow](transaction-flow.md) -- referencing the blob from a Doc is a normal tx
- [storage-blobs](../concepts/storage-blobs.md) -- blob model, download URLs, previews
- [collaboration-flow](collaboration-flow.md) -- rich-text snapshots are blobs too
- Service: [datalake](../services/datalake.md), [front](../services/front.md)
- Types: [core-types](../types/core-types.md)

## Gotchas

- **10 MB is the branch point, 5 MB is the chunk size.** `uploadFile` uses form-data for `size <= 10 MB` and S3-style multipart above that; multipart slices the body into `5 * 1024 * 1024`-byte parts.
- **ETags are mandatory for completion.** Each part PUT returns an `etag`; `/complete` must send the full `{ partNumber, etag }` list in order or the assemble fails. The client sorts/accumulates parts as it goes.
- **Always abort on failure.** `uploadMultipart` wraps the whole sequence in try/catch and calls `/abort` if anything throws, so partial uploads don't linger. Don't skip this in a reimplementation.
- **Progress is per-strategy.** form-data progress comes from the XHR `upload.onprogress`; multipart progress is computed as `uploaded + chunkProgress` across parts, normalized to the whole file size.
- **The uuid is the blob id, not a server-assigned one.** You generate it client-side and pass it in; the download URL is built from `{ws}/{uuid}`. Keep it to reference the blob later.
- **Reference is a separate step.** Uploading does not link the blob to anything. You must issue a tx (e.g. an `Attachment` in a collection, or set a blob-ref attribute) to make it visible from a document.
- **`getFileMeta` / `deleteFile`** hit `/meta/{ws}/{uuid}` and `DELETE /blob/...` respectively, both Bearer-authenticated.
```