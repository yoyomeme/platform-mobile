# Real-time Collaboration (Y.js CRDT)

> How Huly does Google-Docs-style collaborative editing: the **collaborator** service (`:3078`) running Hocuspocus over Y.js CRDTs, the **Markup** rich-text representation, and the `text-*` packages that convert between Y.js docs, Markup, and Markdown.

## Where in code

| Component | File | Purpose |
|-----------|------|---------|
| Collaborator client | `foundations/core/packages/collaborator-client/src/client.ts` | `getMarkup` / `createMarkup` / `updateMarkup` RPC |
| Document id encoding | `foundations/core/packages/collaborator-client/src/utils.ts` | `encodeDocumentId` → `ws|class|id|attr` |
| `CollaborativeDoc` | `foundations/core/packages/core/src/collaboration.ts` | `{ objectClass, objectId, objectAttr }` + blob id helpers |
| `Markup` / `MarkupBlobRef` | `foundations/core/packages/core/src/classes.ts` | `Markup = string`, `MarkupBlobRef = Ref<Blob>` |
| Collaborator server | `server/collaborator/src/server.ts` | Hocuspocus WS + `/rpc/:id` HTTP |
| RPC methods | `server/collaborator/src/rpc/methods/` | `getContent` / `createContent` / `updateContent` |
| Markup transformer | `server/collaborator/src/transformers/markup.ts` | Y.js ↔ Markup conversion |
| Markup ↔ Y.js | `foundations/core/packages/text-ydoc/src/ydoc.ts` | `markupToYDoc` / `yDocToMarkup` |
| Markup ↔ Markdown | `foundations/core/packages/text-markdown/src/index.ts` | `markupToMarkdown` / `markdownToMarkup` |

## Purpose

Document bodies, issue descriptions, and comments are rich text that multiple users may edit at the same time. A naive "last write wins" `TxUpdateDoc` would lose concurrent edits. Huly instead represents collaborative fields as **Y.js CRDT documents** synchronized through a dedicated **collaborator** service, so concurrent edits merge automatically without a central lock.

The rest of the platform doesn't store the live CRDT; it stores a **reference to a blob** (the serialized snapshot) in the regular `Doc`. The collaborator service owns the live editing session and persists snapshots to blob storage.

## Details

### Three text representations

Huly carries rich text in three interchangeable forms, with `text-*` packages bridging them:

```
   Markdown            Markup (ProseMirror JSON)            Y.js Doc (CRDT)
  (chat, import) ◀───▶  (storage / transport) ◀──────────▶ (live editing)
        text-markdown                    text-ydoc
```

- **Markup** (`Markup = string`) — the canonical rich-text form, a serialized ProseMirror/`MarkupNode` JSON tree. This is what flows over the collaborator RPC and what gets stored as a blob.
- **Markdown** — used for chat (see [communication](communication.md)) and import/export. `markupToMarkdown(node)` / `markdownToMarkup(string)` convert.
- **Y.js `Doc`** — the live CRDT used only inside an editing session. `markupToYDoc(markup, field)` / `yDocToMarkup(ydoc, field)` convert.

```typescript
export function markupToYDoc (markup: Markup, field: string): YDoc {
  return jsonToYDoc(markupToJSON(markup), field)
}
export function yDocToMarkup (ydoc: YDoc, field: string): Markup { /* ... */ }
```

### Addressing a collaborative field — `CollaborativeDoc`

A rich-text field is identified not by a blob id but by **which attribute of which document** it is:

```typescript
export interface CollaborativeDoc {
  objectClass: Ref<Class<Doc>>
  objectId: Ref<Doc>
  objectAttr: string   // the attribute holding the rich text, e.g. 'content'
}
```

The collaborator addresses a document by joining these into a single id:

```typescript
export function encodeDocumentId (workspaceId: string, documentId: CollaborativeDoc): string {
  const { objectClass, objectId, objectAttr } = documentId
  return [workspaceId, objectClass, objectId, objectAttr].join('|')
}
```

So a document editing session is keyed by `workspace|class|id|attr`. Each distinct rich-text attribute of each doc is its own CRDT document. The stored snapshot blob id is derived separately via `makeCollabJsonId(doc)` → `MarkupBlobRef` (`Ref<Blob>`).

### Live editing — Hocuspocus over WebSocket

The collaborator runs **Hocuspocus**, a Y.js sync server:

```typescript
const hocuspocus = new Hocuspocus({
  address: '0.0.0.0',
  port,
  timeout: 30000,
  debounce: 10000,       // debounce onStoreDocument
  maxDebounce: 60000,    // but persist at least this often
  yDocOptions: { gc: false, gcFilter: () => false },  // GC off so snapshots work
  unloadImmediately: false,
  extensions: [
    new AuthenticationExtension({ ... }),  // validates the JWT
    new StorageExtension({ adapter: new PlatformStorageAdapter(...), transformer })
  ]
})
```

Editing clients open a **WebSocket** to the collaborator; Hocuspocus relays Y.js updates between all clients editing the same `documentId`, merging via CRDT. The `StorageExtension` loads the initial doc from blob storage and **debounce-persists** the merged result back (every ~10 s, at least every 60 s). Garbage collection is deliberately disabled so historical snapshots remain reconstructable.

### Non-editing access — RPC

Clients that don't need a live cursor (read a description, render a comment, copy content) use a plain HTTP **RPC** instead of joining the WS session:

```typescript
export interface CollaboratorClient {
  getMarkup: (document: CollaborativeDoc, source?: Ref<Blob> | null) => Promise<Markup>
  createMarkup: (document: CollaborativeDoc, markup: Markup) => Promise<MarkupBlobRef>
  updateMarkup: (document: CollaborativeDoc, markup: Markup) => Promise<void>
  copyContent: (source: CollaborativeDoc, target: CollaborativeDoc) => Promise<void>
}
```

Each call POSTs to `/rpc/{documentId}`:

```typescript
const url = concatLink(this.collaboratorUrl, `/rpc/${encodeURIComponent(documentId)}`)
const res = await fetch(url, {
  method: 'POST',
  headers: { Authorization: 'Bearer ' + this.token, 'Content-Type': 'application/json' },
  body: JSON.stringify({ method, payload })   // method: getContent | createContent | updateContent
})
```

The server (`server/collaborator/src/server.ts`) dispatches `request.method` to a handler in `rpc/methods/` (`getContent`, `createContent`, `updateContent`). The client wraps each call in a 3-attempt retry (50 ms backoff). Note the client also **rewrites `ws://`/`wss://` to `http://`/`https://`** for the RPC URL — the same service speaks WS (sync) and HTTP (RPC).

```typescript
const url = collaboratorUrl.replaceAll('wss://', 'https://').replace('ws://', 'http://')
```

### How features use it

| Feature | Pattern |
|---------|---------|
| **Document** body | Live Hocuspocus WS session while open; snapshot blob (`MarkupBlobRef`) stored on the `Document` doc |
| Issue / card **description** | Same `CollaborativeDoc` mechanism on the `description` attribute |
| **Comments** | Short Markup created once via `createMarkup` → `MarkupBlobRef`, rarely co-edited |
| Templates / copy | `copyContent(source, target)` reads source Markup and writes it to a target field |

A typical edit session:

```
editor A ─┐
editor B ─┼─ WS ─▶ collaborator (Hocuspocus, :3078)
editor C ─┘            │  merges Y.js updates (CRDT)
                       │  debounce 10s → StorageExtension
                       ▼
                  datalake blob  (MarkupBlobRef stored on the Doc via transactor)
```

### Key properties

| Property | Value | Description |
|----------|-------|-------------|
| Protocol | WebSocket (Hocuspocus) + HTTP `/rpc` | sync vs one-shot read/write |
| CRDT | Y.js | conflict-free concurrent merge |
| Storage form | Markup blob (`MarkupBlobRef`) | persisted snapshot, not the live CRDT |
| Doc key | `ws|class|id|attr` | one CRDT per rich-text attribute |
| Persist debounce | 10 s / 60 s max | from Hocuspocus config |
| GC | disabled | keeps snapshots reconstructable |

## Cross-references

- [storage-blobs](storage-blobs.md) — Markup snapshots are stored as datalake blobs
- [communication](communication.md) — chat uses Markdown; collaborative docs use Markup
- Service: [collaborator](../services/collaborator.md), [transactor](../services/transactor.md)
- Flow: [collaboration-flow](../flows/collaboration-flow.md)
- Plugins: [document](../plugins/document.md)

## Gotchas

- **The `Doc` stores a blob ref, not the text.** A collaborative field on a `Doc` is a `MarkupBlobRef` pointing at the snapshot; to get the text you must call `getMarkup` (or join the WS session) — you cannot read the body straight off the document.
- **Markup ≠ Markdown.** Convert with `text-markdown` when bridging to chat/import; don't store Markdown where Markup is expected.
- **GC is intentionally off.** Y.js garbage collection is disabled so snapshots work; do not "optimize" it back on.
- **One CRDT per attribute.** `CollaborativeDoc` includes `objectAttr` — a document with two rich-text fields has two independent collaborative documents.
- **WS and RPC are the same service on `:3078`.** The client rewrites the `ws://` URL to `http://` for RPC calls; a mobile client needs both transports against the one endpoint.
- **Snapshot persistence is debounced.** A read immediately after an edit may lag up to the debounce window unless you go through the live session.
