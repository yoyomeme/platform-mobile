# Drive (`drive`)

> Cloud file storage: drives (spaces) containing folders and versioned files backed by Blobs.

## Where in code
- `plugins/drive/src/index.ts` -- plugin id (`driveId = 'drive'`), re-exports `types`, `utils`, `analytics`
- `plugins/drive/src/types.ts` -- document interfaces (`Drive`, `Resource`, `Folder`, `File`, `FileVersion`)
- `plugins/drive/src/plugin.ts` -- class/mixin/action/component ids
- `models/drive/src/index.ts` -- model (`T*` classes, viewlets, actions, the `Drive` Application)
- `models/drive/src/permissions.ts` -- per-action permissions
- `plugins/drive-resources/` -- UI (presenters, editors, upload, grid/table views)

## Purpose
Provides a Google-Drive-style file store inside a workspace. Each `Drive` is a `TypedSpace`;
inside it `Folder`s and `File`s form a tree (`parent` + materialized `path`). A `File` keeps an
ordered collection of `FileVersion`s, each pointing at a stored `Blob`. Tier-2 mobile feature
(file browse / download / upload).

## Document classes
| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `Drive` | `core.TypedSpace` | (space members/roles) | A top-level file container space. |
| `Resource` | `core.Doc` (space=`Drive`) | `title`, `parent: Ref<Resource>`, `path: Ref<Resource>[]`, `comments?`, `file?: Ref<FileVersion>` | Abstract base for folders/files; `title` is full-text indexed. |
| `Folder` | `Resource` | `parent: Ref<Folder>`, `path: Ref<Folder>[]`, `file: undefined` | A directory node. |
| `File` | `Resource` | `parent: Ref<Folder>`, `file: Ref<FileVersion>` (current), `versions: CollectionSize<FileVersion>`, `version: number` | A file; `file` points to the active version. |
| `FileVersion` | `core.AttachedDoc<File,'versions',Drive>` | `title`, `file: Ref<Blob>`, `size`, `type`, `lastModified`, `metadata?`, `version` | One immutable version; the `Blob` ref is the actual bytes. |
| `TypeFileVersion` | `core.Type` | -- | Number-typed attribute presenter for version numbers. |

## Key relationships / mixins
- `FileVersion` is a collection on `File` (`collection: 'versions'`); the actual bytes live in a
  `core.Blob` referenced by `FileVersion.file`, fetched from the datalake (see
  [storage-blobs](../concepts/storage-blobs.md)).
- `Folder`/`File` are `Resource`s linked into a tree via `parent` and a denormalized `path` array
  (root → leaf) for breadcrumbs and fast ancestor queries.
- `File` mixes in `activity.ActivityDoc` and registers an `ActivityExtension` so comments
  (`chunter.ChatMessage`) can be attached. `Resource.comments` counts them.
- `Drive` has the `DefaultDriveTypeData` mixin (a `RolesAssignment`) and a `SpaceTypeDescriptor`
  with per-action permissions (`CreateFolder`, `UpdateFile`, …).
- View mixins: `ObjectPresenter`, `ObjectPanel`, `ObjectEditor`, `LinkProvider`, `ObjectTitle`,
  `SpacePresenter`, plus `ObjectSearchCategory` entries for folders/files.

## Notable actions/flows
- Drive: `EditDrive`, `CreateRootFolder`. Folder: `CreateChildFolder`, `RenameFolder`, `Delete`,
  move (`MoveResource` popup). File: `DownloadFile`, `RenameFile`, `Delete`, move,
  restore-version. FileVersion: `RestoreFileVersion`, `Delete`.
- Upload is handled in `drive-resources` (the `UploadFile` action is commented out in the model);
  creating a file = upload bytes → create `Blob` → create `FileVersion` → create/point `File`.
- Viewlets: `DriveTable` (drive list), `FileTable` and `FileGrid` (resource list/grid, with
  `$lookup.file` to pull version size/lastModified).

## Mobile relevance
Tier 2. Browse drives → folders → files; download via the datalake blob URL
(`{DATALAKE_URL}/blob/{workspace}/{blobId}/{filename}`); upload via the datalake upload endpoint
then issue the create transactions above. Version restore is just repointing `File.file`.
Render thumbnails through the preview service. The `path` array gives breadcrumbs without extra
queries.

## Cross-references
- Concepts: [data-model](../concepts/data-model.md), [storage-blobs](../concepts/storage-blobs.md), [transaction-model](../concepts/transaction-model.md)
- Plugins: [attachment](attachment.md) (the other file-attach mechanism), [activity](activity.md), [view](view.md)
- Services: `services/datalake.md`

## Gotchas
- A `File`'s bytes are never on the `File` itself — always go through the current `FileVersion` →
  `Blob`. `File.version`/`File.file` must be kept in sync with the latest `FileVersion`.
- `Folder.file` is typed `undefined` — folders never carry a version even though they share the
  `Resource` base.
- `path` is denormalized; moving a resource must rewrite `path` for the node and all descendants.
- `Drive` is a `Space`, so visibility/permissions follow space membership, not a global ACL.
