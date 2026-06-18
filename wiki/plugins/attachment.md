# Attachment (`attachment`)

> Files attached to any document via a collection: `Attachment`/`Photo`/`Embedding`, plus per-user saved files.

## Where in code
- `plugins/attachment/src/index.ts` -- plugin id (`attachmentId = 'attachment'`), interfaces, class ids, upload/delete helpers
- `models/attachment/src/index.ts` -- model (`TAttachment`, `TPhoto`, `TEmbedding`, `TSavedAttachments`, `TDrawing`, presenters)
- `plugins/attachment-resources/` -- UI (`Attachments`/`Photos` collection editors, `FileBrowser`, `PDFViewer`)

## Purpose
The generic "attach a file to a doc" mechanism. Any document can host an `attachments` collection of
`Attachment`s; each `Attachment` points at a `core.Blob` in storage. Distinct from [drive](drive.md)
(which is a standalone file *space*) — attachments are **children of another doc** (an issue, a
message, a candidate, …). Also provides `Photo` (image attachment), `Embedding` (inline), and a
per-user `SavedAttachments` bookmark.

## Document classes
| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `Attachment` | `core.AttachedDoc` | `name`, `file: Ref<Blob>`, `size`, `type`, `lastModified`, `description?`, `pinned?`, `readonly?`, `metadata?` | A file attached to a parent doc's collection. |
| `Photo` | `Attachment` | (same) | An image attachment (rendered as a thumbnail). |
| `Embedding` | `Attachment` | (same) | A file embedded inline (e.g. in markup). |
| `SavedAttachments` | `preference.Preference` | `attachedTo: Ref<Attachment>` | Per-user bookmark of an attachment. |
| `Drawing` | `core.Doc` | `parent: Ref<Doc>`, `parentClass`, `content?` | A freehand drawing tied to a doc. |
| `AttachmentMetadata` (type) | = `BlobMetadata` | -- | Width/height/duration/etc. from the blob. |

## Key relationships / mixins
- `Attachment` is an `AttachedDoc`: it lives in the parent doc's `attachments` collection
  (`attachedTo`/`attachedToClass`/`collection`). The parent declares
  `@Prop(Collection(attachment.class.Attachment), ...) attachments?: number`.
- The bytes are a `core.Blob` referenced by `Attachment.file`, stored in/served from the datalake
  (see [storage-blobs](../concepts/storage-blobs.md)); `metadata` mirrors the blob metadata.
- `SavedAttachments` is a `Preference` (per-user, in the preference space).
- Presenter components (`AttachmentsPresenter`, `Photos`) and a `PreviewWidget` are registered for UI.

## Notable actions/flows
- Upload helper `attachment.helper.UploadFile(file)` → `{ uuid: Ref<Blob>, metadata }`; then
  `addCollection(Attachment, space, parentId, parentClass, 'attachments', { name, file: uuid, size,
  type, ... })`. `DeleteFile` removes the blob.
- `FileBrowser` aggregates a space's/doc's attachments with date/type filters.

## Mobile relevance
Core building block — nearly every detail screen shows an attachments strip. Flow: pick file → upload
to datalake → get `Blob` ref → `addCollection` onto the doc. Download via the datalake blob URL;
images use the preview service for thumbnails; `Photo` vs generic `Attachment` chooses the renderer.
`pinned` floats an attachment to the top; `readonly` disables edit/remove.

## Cross-references
- Plugins: [drive](drive.md) (standalone file spaces — contrast), [activity](activity.md), [chunter](chunter.md) (message attachments), [preference](preference.md) (SavedAttachments), [view](view.md)
- Concepts: [storage-blobs](../concepts/storage-blobs.md), [data-model](../concepts/data-model.md) (AttachedDoc/collections), [transaction-model](../concepts/transaction-model.md)
- Services: `services/datalake.md`

## Gotchas
- `Attachment.file` is a `Ref<Blob>`, not a URL — build the download URL from `DATALAKE_URL` + workspace
  + blob id + name.
- Attachment vs Drive: attachments are **collection children** of an arbitrary doc; Drive files live in
  a Drive space. Don't conflate them.
- `Photo`/`Embedding` are subclasses of `Attachment` (same storage), differing only by presenter/role —
  query `Attachment` to get them all, or the subclass for the specific kind.
- `readonly`/`pinned` are optional flags the UI honors; enforce `readonly` client-side before issuing
  remove transactions.
