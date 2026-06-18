# Fulltext

> Search-indexing service (port `4702`, internal default `4700`). Consumes transaction and workspace events from the queue, extracts document content (Rekoni for binaries), maintains an Elasticsearch index per workspace, and serves search queries over HTTP.

## Where in code
- `pods/fulltext/src/index.ts` -- entry; builds the `FulltextDBConfiguration` (Elastic adapter + Rekoni content adapter), the queue, storage, and calls `startIndexer`.
- `pods/fulltext/src/server.ts` -- `startIndexer`: HTTP server with the search/reindex routes; constructs the manager.
- `pods/fulltext/src/manager.ts` -- queue consumers (`Workspace`, `Fulltext`, `Tx` topics) and per-workspace indexer lifecycle/eviction.
- `server/indexer/src/fulltext.ts`, `indexer/`, `rekoni.ts`, `mapper.ts` -- the indexing engine: `searchFulltext`, Rekoni content adapter, doc→index mapping.
- `@hcengineering/elastic` -- `createElasticAdapter`.

## Purpose
Keeps a searchable index in sync with workspace data without putting that load on the transactor. The transactor forwards documents and publishes Tx events; fulltext consumes them asynchronously, pulls textual content (including extracting text from PDFs/DOCs via Rekoni), and writes to Elasticsearch. Clients search either directly via this service's HTTP API or through the transactor's `searchFulltext` which proxies here.

## Responsibilities
- **Consume queue topics** (`manager.ts`): `QueueTopic.Tx` (document CUDs and domain events → index), `QueueTopic.Workspace` (workspace lifecycle → open/close/reindex), `QueueTopic.Fulltext` (control). Failed Tx messages go to the dead-letter topic.
- **Content extraction**: `Rekoni` content adapter (`contentType: '*'`, default) extracts text from binary attachments via the rekoni service.
- **Indexing**: maintain a per-workspace Elasticsearch index (`ELASTIC_INDEX_NAME` prefix); create/update/delete index entries as documents change.
- **Search**: serve `search` and `full-text-search` queries; per-workspace indexers are lazily created and evicted after an idle timeout.
- **Reindex**: full rebuild on demand (and after workspace restore).
- Uses a system token (`service: 'fulltext'`) per workspace to read documents from the transactor/DB.

## Key endpoints/methods

| Method / Path | Purpose |
|---------------|---------|
| `PUT /api/v1/search` | Raw Elasticsearch query against a workspace index (`fulltextAdapter.search`). |
| `PUT /api/v1/full-text-search` | Higher-level platform search (`searchFulltext` from `server-indexer`). |
| `PUT /api/v1/index-documents` | Index a provided set of documents. |
| `PUT /api/v1/reindex` | Trigger a full reindex of the token's workspace. |
| `PUT /api/v1/close` | Close/evict the workspace indexer. |
| `GET /api/v1/statistics` | Metrics/health. |

All routes derive the workspace from the bearer token (`decodeToken`).

### Queue consumers (`manager.ts`)
| Topic | Handler | Effect |
|-------|---------|--------|
| `QueueTopic.Workspace` | `processWorkspaceEvent` | Create/close/reindex workspace indexers. |
| `QueueTopic.Fulltext` | `processFulltextEvent` | Fulltext control messages. |
| `QueueTopic.Tx` | `processTransactions` | Apply doc changes to the index; dead-letter on failure. |

## Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `PORT` | `4700` (exposed `4702`) | HTTP listen port. |
| `DB_URL` | (required) | CockroachDB/Postgres connection (read documents). |
| `FULLTEXT_DB_URL` | `http://huly.local:9200` | Elasticsearch URL. |
| `ELASTIC_INDEX_NAME` | (required) | Index name/prefix. |
| `REKONI_URL` | `http://huly.local:4004` | Content-extraction service. |
| `QUEUE_CONFIG` | `cockroach\|http://redpanda:9092` | Kafka/Redpanda config. |
| `STORAGE_CONFIG` | — | MinIO/datalake (fetch blobs to extract text). |
| `HULYLAKE_URL` | `''` | Optional storage adapter. |
| `ACCOUNTS_URL` | `http://huly.local:3000` | Account service. |
| `SERVER_SECRET` | `secret` | Token signing/verification (`service: 'fulltext'`). |
| `MODEL_JSON` | `model.json` | Model loaded at boot. |

## Cross-references
- Producer of the Tx events: [transactor](transactor.md)
- Event topics and dead-letter behavior: [event-queue](../concepts/event-queue.md)
- Search concept: [fulltext-search](../concepts/fulltext-search.md)
- Restore triggers reindex: [workspace](workspace.md)
- Binary content extraction: rekoni (see [ARCHITECTURE_OVERVIEW](../../ARCHITECTURE_OVERVIEW.md))
- Blob source for extraction: [datalake](datalake.md)

## Gotchas
- Indexing is **asynchronous**. A document written via the transactor is searchable only after its Tx event is consumed here — search can lag writes, especially under backlog.
- Per-workspace indexers are lazily created and evicted on idle (default ~5 min). First search after eviction re-opens the index.
- Tx processing failures are routed to a dead-letter topic (`getDeadletterTopic(QueueTopic.Tx)`) rather than blocking the consumer — silently failing docs end up there.
- Content extraction depends on rekoni being reachable; if `REKONI_URL` is down, binary attachments index without extracted text.
- The exposed port (`4702`) differs from the in-process default (`PORT=4700`); the platform maps `FULLTEXT_URL` to `4702`.
