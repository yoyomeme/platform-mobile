# Document (`document`)

> Collaborative documents organized into teamspaces, with versioned snapshots. Rich text via the collaborator/CRDT layer.

## Where in code
- `plugins/document/src/index.ts` -- re-exports `plugin.ts` + `types.ts`
- `plugins/document/src/types.ts` -- interfaces `Document`, `Teamspace`, `DocumentSnapshot`
- `plugins/document/src/plugin.ts` -- plugin id (`documentPlugin`: classes/strings/actions/spaceType)
- `models/document/src/index.ts` -- model: `@Model` defs, teamspace space type
- `models/document/src/{permissions}.ts` -- permission wiring
- `plugins/document-resources/` -- Svelte UI (editor, `CreateDocument`, history/snapshots, teamspace nav)

## Purpose
The document app is Huly's wiki/notes/knowledge surface. A **`Document`** is a tree-structured rich-text page (parent/child via `parent` + `rank`) living inside a **`Teamspace`** (a typed space). Content is a CRDT-backed markup blob edited live through the collaborator service; `DocumentSnapshot`s capture point-in-time versions.

## Document classes

| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `Teamspace` | `core.class.TypedSpace` + `IconProps` | (typed space + icon/color) | A space grouping related documents (like a notebook/wiki). |
| `Document` | `core.class.Doc` + `IconProps` | `title`, `content: MarkupBlobRef \| null`, `parent: Ref<Document>`, `space: Ref<Teamspace>`, `rank`, `lockedBy?`, `snapshots?`, `attachments?`, `comments?`, `references?`, `embeddings?` | A rich-text page; nests via `parent` + `rank`. |
| `DocumentSnapshot` | `core.class.Doc` | `title`, `content: MarkupBlobRef`, `parent: Ref<Document>` | An immutable saved version of a document's content. |

### Space type
`document.spaceType.DefaultTeamspaceType` + `document.descriptor.TeamspaceType`; `document.mixin.DefaultTeamspaceTypeData` carries teamspace custom attributes.

## Key relationships / mixins
- **Hierarchy**: `Document.parent` builds a page tree within a teamspace; `document.ids.NoParent` is the root sentinel; `rank` orders siblings.
- **Content** is a `MarkupBlobRef` — the live document lives in the collaborator/CRDT layer (Hocuspocus/Yjs), not as inline markup. `snapshots` counts saved `DocumentSnapshot`s.
- `lockedBy?: AccountUuid` — soft lock to prevent concurrent edits.
- Collaboration via the `Collaborators` mixin from [notification](notification.md); comments via [chunter](chunter.md) `ChatMessage`.
- `embeddings`/`references` support search and cross-doc linking.

## Spaces
Documents are scoped by `space: Ref<Teamspace>`. A teamspace is a `TypedSpace` whose type is the default teamspace type. Membership/permissions (e.g. `ForbidCreateTeamspace`) gate who can create teamspaces and docs.

## Notable actions/flows
- `CreateDocument`, `CreateChildDocument`, `EditTeamspace`.
- Snapshot/history viewing (`document.icon.History`).
- Star/lock/unlock (`Star`, `Lock`, `Unlock` icons/actions).
- `ContentNotification` type + `DocumentNotificationGroup` feed [inbox](inbox.md) when content changes.

## Mobile relevance
**Tier-1, read-first.** Per the architecture build order, documents are "read first; collaborative editing later (via Collaborator)." Mobile should: list teamspaces → document tree, and render a document's markup **read-only** by fetching the content blob. Live collaborative editing requires the CRDT/collaborator WebSocket and is a later phase. Snapshots/history are nice-to-have.

## Cross-references
- Content/editing: [collaboration-crdt](../concepts/collaboration-crdt.md), [text-editor](text-editor.md), [storage-blobs](../concepts/storage-blobs.md)
- Pairs with: [chunter](chunter.md) (comments), [activity](activity.md), [notification](notification.md), [attachment](attachment.md)
- Concepts: [data-model](../concepts/data-model.md), [collaboration-crdt](../concepts/collaboration-crdt.md)
- Flows: [collaboration-flow](../flows/collaboration-flow.md)

## Gotchas
- `Document.content` is a `MarkupBlobRef` backed by a CRDT — you cannot read the latest text from the doc record alone; you fetch the blob (snapshot) or connect to the collaborator for live state. Editing safely on mobile means going through the collaborator, not patching the blob directly.
- The doc tree is per-teamspace; `parent` refs only resolve within the same `space`.
- Note the naming collision: [tracker](tracker.md) also defines an internal `Document` interface (`tracker.class` namespace) — they are unrelated. This page is `document.class.Document`.
- `lockedBy` is advisory; respect it in the UI to avoid clobbering another editor.
