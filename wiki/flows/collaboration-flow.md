# Collaboration Flow

> How a collaborative rich-text field is edited: open the doc, join a Y.js sync session over the **collaborator** WebSocket (`:3078`), exchange CRDT updates, autosave a **Markup** snapshot to the datalake (debounced), with the `Doc` storing only a blob reference. Non-editing reads go through a one-shot HTTP RPC instead.

## Where in code
- `foundations/core/packages/collaborator-client/src/client.ts` -- `CollaboratorClient.getMarkup/createMarkup/updateMarkup/copyContent` (HTTP RPC, 3-attempt retry)
- `foundations/core/packages/collaborator-client/src/utils.ts` -- `encodeDocumentId` → `ws|class|id|attr`
- `foundations/core/packages/core/src/collaboration.ts` -- `CollaborativeDoc { objectClass, objectId, objectAttr }`, `MarkupBlobRef`
- `server/collaborator/src/server.ts` -- Hocuspocus WS sync + `StorageExtension` debounced persistence; `/rpc/:id` HTTP

## Sequence

```
 Editors A/B/C        Collaborator (:3078, Hocuspocus)        Datalake          Doc / Transactor
     |                        |                                   |                   |
     | open doc → encodeDocumentId(ws|class|id|attr)              |                   |
     |                        |                                   |                   |
     | WS connect (Bearer token in handshake)                     |                   |
     |----------------------->|  StorageExtension.load:           |                   |
     |                        |  read snapshot blob (MarkupBlobRef)|-----------------> |
     |                        |  Y.js doc seeded <----------------|                   |
     |  Y.js sync updates  <->|  merge CRDT (gc disabled)         |                   |
     |  (relayed to all editors of the same documentId)           |                   |
     |                        |                                   |                   |
     |                        |  onStoreDocument (debounce 10s,   |                   |
     |                        |   max 60s): yDocToMarkup →         |                   |
     |                        |  persist snapshot blob ---------->| store blob        |
     |                        |                                   |                   |
     | (Doc keeps MarkupBlobRef; updated via a normal tx) ----------------------------> |

 Non-editing read (no live cursor):
     | POST /rpc/{documentId} { method:'getContent' }  → { content:{ attr: Markup } }   |
```

## Steps

| Step | Action | Error code on failure |
|------|--------|----------------------|
| 1 | Build the `CollaborativeDoc { objectClass, objectId, objectAttr }` for the field being edited. | |
| 2 | `encodeDocumentId(workspace, doc)` → `ws|class|id|attr` (the session/document key). | |
| 3 | **Editing:** open the collaborator WebSocket (Hocuspocus); the JWT is validated by the `AuthenticationExtension`. | `Unauthorized` |
| 4 | `StorageExtension` loads the initial snapshot blob (`MarkupBlobRef`) and seeds the Y.js doc. | `LOAD-001` |
| 5 | Local edits become Y.js updates; Hocuspocus relays them to all editors of the same `documentId`, merging via CRDT. | |
| 6 | `onStoreDocument` (debounced ~10 s, at most every 60 s) converts the merged Y.js doc to **Markup** and persists a snapshot blob. | `STORE-001` |
| 7 | The owning `Doc` keeps the `MarkupBlobRef`; when it changes it is written with a normal tx (see [transaction-flow](transaction-flow.md)). | |
| 8 | **Non-editing read:** `POST /rpc/{documentId}` with `{ method:'getContent' }` → `{ content: { attr: Markup } }`. (`createContent`/`updateContent` for one-shot writes.) | `HTTP {status}` |

## Code

```typescript
import { getClient as getCollaboratorClient } from '@hcengineering/collaborator-client'
import document from '@hcengineering/document'

// One-shot read (render a description/comment without joining the live session):
const collab = getCollaboratorClient(workspace, token, config.COLLABORATOR_URL)
const markup = await collab.getMarkup({
  objectClass: document.class.Document,
  objectId: docId,
  objectAttr: 'content'
})

// One-shot create (e.g. a comment body) → returns the blob ref to store on the Doc:
const blobRef = await collab.createMarkup(
  { objectClass: chunter.class.ChatMessage, objectId: msgId, objectAttr: 'message' },
  '<p>Hello</p>' // Markup (serialized ProseMirror JSON / HTML-ish)
)

// Live editing instead uses a Y.js WebSocket session to the same COLLABORATOR_URL
// (Hocuspocus). The editor binds markupToYDoc / yDocToMarkup around that session.
```

## Prerequisites

- A workspace-scoped `token` and `COLLABORATOR_URL` from `config.json` (see [login-flow](login-flow.md)).
- The owning `Doc` exists and its rich-text attribute holds (or will hold) a `MarkupBlobRef`.
- For live editing: a Y.js / Hocuspocus client transport; for reads: just HTTP.

## Error handling

```typescript
// RPC: getMarkup/createMarkup/updateMarkup retry 3x with 50 ms backoff, then throw.
try {
  const markup = await collab.getMarkup(collabDoc)
} catch (err) {
  // 'HTTP error {status}' on non-2xx, or the server's { error } payload.
}

// The client rewrites ws:// → http:// (and wss:// → https://) for RPC, so the same
// COLLABORATOR_URL serves both the live WS session and one-shot RPC.
```

## Cross-references

- [collaboration-crdt](../concepts/collaboration-crdt.md) -- Markup vs Markdown vs Y.js, Hocuspocus config, persistence
- [file-upload-flow](file-upload-flow.md) -- snapshots are datalake blobs
- [transaction-flow](transaction-flow.md) -- the Doc's blob ref is updated via a tx
- [communication](../concepts/communication.md) -- chat uses Markdown; docs use Markup
- Service: [collaborator](../services/collaborator.md), [datalake](../services/datalake.md), [transactor](../services/transactor.md)
- Types: [core-types](../types/core-types.md)

## Gotchas

- **The Doc stores a blob ref, not the text.** A collaborative field is a `MarkupBlobRef` pointing at the snapshot. To get the text you must call `getMarkup` or join the WS session — you cannot read the body off the document.
- **One CRDT per attribute.** The session key includes `objectAttr`; a doc with two rich-text fields has two independent collaborative documents.
- **Persistence is debounced.** Snapshots are written ~10 s after edits (at most every 60 s). A read immediately after typing may lag the live session unless you read through the session.
- **GC is intentionally off.** Y.js garbage collection is disabled so snapshots stay reconstructable — don't re-enable it.
- **WS and RPC are one service on `:3078`.** Live sync is WebSocket; non-editing read/write is HTTP `/rpc/{documentId}`. A mobile client needs both transports against the one endpoint.
- **Markup ≠ Markdown.** Convert with `text-markdown` when bridging to chat/import; don't store Markdown where Markup is expected.
```