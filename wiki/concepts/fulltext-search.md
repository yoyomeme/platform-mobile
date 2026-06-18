# Full-text Search & Indexing

> The indexing pipeline: the **fulltext** service (`:4702`) consumes transaction events off the queue, extracts text (delegating binary documents to **rekoni** `:4004`), writes an **Elasticsearch** index, and answers the transactor's `searchFulltext` RPC.

## Where in code

| Component | File | Purpose |
|-----------|------|---------|
| Service bootstrap | `pods/fulltext/src/index.ts` | wires queue, Elastic, rekoni, model |
| Search HTTP routes | `pods/fulltext/src/server.ts` | `/api/v1/search`, `/full-text-search`, `/reindex` |
| Queue manager | `pods/fulltext/src/manager.ts` | tx/fulltext/workspace consumers |
| Indexer pipeline | `server/indexer/src/indexer/indexer.ts` | `indexDocuments`, blob/message text extraction |
| `searchFulltext` | `server/indexer/src/fulltext.ts` | query + score + map results |
| Rekoni adapter | `server/indexer/src/rekoni.ts` | `createRekoniAdapter` → calls `/toText` |
| Rekoni client | `packages/rekoni/src/index.ts` | `recognizeDocument` → `/recognize` |
| Rekoni service | `services/rekoni/src/server.ts` | `/toText` + `/recognize` HTTP endpoints |

## Purpose

Search must span every document class in a workspace — issues, chat, contacts, documents, attachments — and must look **inside** binary files (PDF, DOCX, etc.), not just their metadata. Doing this on the read path would be far too slow. Huly instead maintains an **asynchronous inverted index in Elasticsearch**, kept up to date by a fulltext service that reacts to the transaction event stream. Searches then hit the prebuilt index in milliseconds.

A second responsibility is **document intelligence**: the rekoni service extracts plain text from binary formats and parses résumés (used by Recruit), which feeds both search and structured data.

## Details

### Pipeline overview

```
transactor ── tx ──▶ Redpanda (cockroach.tx)
                          │
                          ▼  txConsumer (group)
                 ┌──────────────────────┐
                 │  fulltext (:4702)     │
                 │  indexer pipeline     │
                 │  ┌─ for each Doc ─┐   │
                 │  │ collect attrs  │   │
                 │  │ fetch blobs    │───┼──▶ datalake (blob bytes)
                 │  │ extract text   │───┼──▶ rekoni (:4004) /toText
                 │  └────────────────┘   │
                 └──────────┬────────────┘
                            ▼ index
                     Elasticsearch (:9200)
                            ▲
                searchFulltext │ (RPC via transactor)
                            client
```

### Service wiring

`pods/fulltext/src/index.ts` assembles the dependencies: an Elastic adapter, a rekoni content adapter, the model, and the platform queue.

```typescript
const config: FulltextDBConfiguration = {
  fulltextAdapter: { factory: createElasticAdapter, url: fullTextDbURL },   // FULLTEXT_DB_URL = :9200
  contentAdapters: {
    Rekoni: { factory: createRekoniAdapter, contentType: '*', url: rekoniUrl }  // REKONI_URL = :4004
  },
  defaultContentAdapter: 'Rekoni'
}
const queue = getPlatformQueue('fulltext')
startIndexer(ctx, { queue, model, config, externalStorage, elasticIndexName, dbURL, hulylakeUrl, port, ... })
```

### Consuming transactions

The fulltext **manager** (`pods/fulltext/src/manager.ts`) is a queue consumer (see [event-queue](event-queue.md)). It subscribes to the `tx` topic for live changes, the `workspace` topic for lifecycle, and its **private `fulltext` topic** for reindex requests:

```typescript
this.txConsumer = queue.createConsumer<TxCUD<Doc> | TxDomainEvent<QueueSourced<Event>>>(
  ctx, QueueTopic.Tx, queue.getClientId(),
  async (ctx, msg, control) => this.processTransactions(msg, control))
```

The `tx` payload is `TxCUD<Doc> | TxDomainEvent<...Event>` — so the indexer handles both ordinary document CUD **and** communication chat events, indexing messages alongside docs. For each affected document, `indexDocuments` gathers indexable attribute values via the hierarchy and builds an `IndexedDoc`.

### Extracting text from blobs (the rekoni step)

When a document references a blob (an attachment, a file), the indexer fetches the bytes from storage and runs them through the content adapter:

```typescript
if (docInfo.size > 30 * 1024 * 1024) throw new Error('Blob size exceeds limit of 30MB')
const buffer = Buffer.concat(await this.storageAdapter.read(ctx, this.workspace, docInfo._id))
let textContent = await this.contentAdapter.content(ctx, this.workspace.uuid, docInfo._id, contentType, buffer)
```

`createRekoniAdapter` implements `content()` by POSTing the bytes to rekoni's `/toText`:

```typescript
export async function createRekoniAdapter (url: string): Promise<ContentTextAdapter> {
  return {
    content: async (ctx, workspace, name, type, doc) => {
      const r = await fetch(`${url}/toText?name=${encodeURIComponent(name)}&type=${encodeURIComponent(type)}`,
        { method: 'POST', body: /* base64 bytes */ ... })
      return r.content
    }
  }
}
```

Content-type gating: plain text and diffs are indexed inline; recognized binary types (`isBlobAllowed`) go to rekoni; disallowed types are skipped. Blobs over **30 MB** are not indexed.

Chat messages are indexed by converting their Markdown body to Markup first (`markdownToMarkup(message.content)`), then extracting indexable text — so chat is searchable through the same index.

### Rekoni — document intelligence (`:4004`)

The rekoni service exposes two endpoints (`services/rekoni/src/server.ts`):

| Endpoint | Purpose | Caller |
|----------|---------|--------|
| `POST /toText` | extract raw plain text from a binary doc (PDF via `pdfjs-dist`, DOCX, RTF, HTML) | fulltext indexer |
| `POST /recognize` | parse a résumé into a structured `ReconiDocument` | `recognizeDocument` (Recruit) |

`/toText` runs the bytes through format-specific extractors and returns `{ matched, content, error }`. `/recognize` returns structured fields:

```typescript
export interface ReconiDocument {
  format: string
  firstName: string
  lastName: string
  title?: string
  email?: string
  phone?: string
  city?: string
  linkedin?: string
  github?: string
  skills: string[]
  // ...
}
```

Rekoni supports HeadHunter, LinkedIn, and generic résumé layouts (`headhunter.ts`, `linkedin.ts`, `generic.ts`).

### Searching — `searchFulltext`

Clients never query Elasticsearch directly. The transactor exposes a **`searchFulltext(query, options)`** RPC over its WebSocket (one of the core RPC methods), which proxies to the fulltext service. The fulltext service's HTTP surface backs it:

```
PUT /api/v1/search             // simple string search
PUT /api/v1/full-text-search   // full searchFulltext with scoring
PUT /api/v1/index-documents    // force-index specific docs
PUT /api/v1/reindex            // clear + full reindex a workspace
```

The server function:

```typescript
export async function searchFulltext (
  ctx, workspaceId, hierarchy, adapter, query: SearchQuery, options: SearchOptions
): Promise<SearchResult> {
  const resultRaw = await adapter.searchString(ctx, workspaceId, query, {
    ...options,
    scoring: getScoringConfig(hierarchy, query.classes ?? [])
  })
  return { ...resultRaw, docs: resultRaw.docs.map((raw) => mapSearchResultDoc(hierarchy, raw)) }
}
```

`query.classes` narrows the search to specific document classes and drives **scoring** (class-aware relevance). Results are mapped back into platform-shaped `SearchResultDoc` via the hierarchy. A **reindex** clears the workspace index and replays it by sending `workspaceEvents.clearIndex()` + `fullReindex()` onto the fulltext topic.

### Key properties

| Property | Value | Description |
|----------|-------|-------------|
| Index store | Elasticsearch | `FULLTEXT_DB_URL` = `:9200`, `ELASTIC_INDEX_NAME` |
| Update trigger | `tx` topic events | async, not on write path |
| Text extraction | rekoni `/toText` | `REKONI_URL` = `:4004` |
| Blob size cap | 30 MB | larger blobs not indexed |
| Search entry | `searchFulltext` RPC | via transactor → fulltext |
| Class scoring | `getScoringConfig(hierarchy, classes)` | relevance per class |

## Cross-references

- [event-queue](event-queue.md) — fulltext consumes the `tx`/`fulltext`/`workspace` topics
- [storage-blobs](storage-blobs.md) — blob bytes are fetched from datalake for extraction
- [communication](communication.md) — chat messages are indexed alongside documents
- Service: [fulltext-service](../services/fulltext-service.md), [transactor](../services/transactor.md)

## Gotchas

- **Indexing is eventually consistent.** A doc is searchable only after its transaction propagates through the queue and the indexer runs — there is a lag after writes.
- **`searchFulltext` goes through the transactor, not Elasticsearch.** Clients call the RPC; they never hit `:9200` or `:4702` directly.
- **Blobs over 30 MB and disallowed content types are skipped.** Their text won't appear in results even though the document is indexed.
- **Rekoni does double duty.** `/toText` (search extraction) and `/recognize` (résumé parsing) are different endpoints with different consumers — don't conflate them.
- **No queue → stale index.** With a `DummyQueue` (dev) the tx consumer never runs, so search results won't reflect recent changes until a manual `/reindex`.
- **Scoring is class-aware.** Passing `query.classes` changes ranking, not just filtering — omit it for a broad search, set it to bias relevance.
