# Architecture

> How the Huly platform fits together: clients compose plugins; the plugin runtime resolves resources; all data flows through the transactor as transactions; supporting services handle storage, search, collaboration, and events.

## Where in code

- `foundations/core/packages/platform/src/` — plugin/resource runtime (the wiring layer)
- `foundations/core/packages/core/src/` — `Doc`/`Tx`/`Hierarchy`/`ModelDb` runtime
- `foundations/core/packages/client*/`, `rpc/` — client connection + RPC framing
- `models/` — the model: classes/attributes registered per plugin (builder DSL)
- `plugins/` — 190+ feature plugins (definitions + Svelte resources + assets)
- `server/`, `services/`, `pods/` — backend services (transactor pipeline, account, fulltext, datalake, collaborator, …)
- `ARCHITECTURE_OVERVIEW.md` — full server topology (30+ services, ports, env)
- `MOBILE_APP_ARCHITECTURE.md` — client/protocol deep-dive

## The three big ideas

1. **Plugin runtime** — features are registered as plugins; cross-plugin references are *string ids* (`Resource`, `Plugin`, `IntlString`, `Asset`) resolved at runtime by `@hcengineering/platform`. See [plugin-architecture](concepts/plugin-architecture.md).
2. **Self-describing model** — the schema is a stream of transactions loaded at startup into a `Hierarchy`. Plugins add classes/attributes/mixins. See [data-model](concepts/data-model.md) and [model-layer](concepts/model-layer.md).
3. **Transaction sourcing** — every write is a `Tx`; every read is `findAll`. Connecting to a workspace subscribes you to its tx broadcast stream. See [transaction-model](concepts/transaction-model.md) and [client-protocol](concepts/client-protocol.md).

## Layer diagram (client)

```
┌────────────────────────────────────────────────────────────────────────┐
│                          CLIENT (web / desktop / mobile)                │
│                                                                        │
│   Workbench shell  ──  Feature plugins (tracker, chunter, contact …)   │
│        │                    │  render/edit Doc classes                  │
│        ▼                    ▼                                           │
│   @hcengineering/presentation  (getClient(), LiveQuery, createQuery)    │
│        │                                                                │
│   @hcengineering/platform  (Resource/Plugin/IntlString/Asset registry)  │
└────────┬───────────────────────────────────────────────────────────────┘
         │  Client API:  findAll / findOne / tx / searchFulltext / loadModel
         ▼
┌────────────────────────────────────────────────────────────────────────┐
│   @hcengineering/core   →   client-resources/connection.ts (WS + RPC)   │
│   Hierarchy · ModelDb · TxOperations · LiveQuery cache                   │
└────────┬───────────────────────────────────────────────────────────────┘
         │  WebSocket  ws://{endpoint}/{token}?sessionId=…   (JSON | MessagePack | Snappy)
         ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      TRANSACTOR  (server-pipeline)                       │
│   session → pipeline (triggers, fulltext, derived data, broadcast)       │
└───┬───────────────┬───────────────┬───────────────┬────────────────────┘
    │               │               │               │
    ▼               ▼               ▼               ▼
┌─────────┐   ┌───────────┐   ┌───────────┐   ┌──────────────┐
│Cockroach│   │ Redpanda  │   │ Fulltext  │   │  Datalake    │
│  (DB)   │   │ (events)  │   │ (ES+rekoni)│  │ (MinIO blobs)│
└─────────┘   └─────┬─────┘   └───────────┘   └──────────────┘
                    │ async consumers: media, process, github, mail, …
                    ▼
              services/*  +  pods/*
```

## Service topology (server)

The platform runs **30+ services**. The client only needs a handful to be publicly reachable; the rest are reached *through* the transactor.

| Group | Services | Role |
|-------|----------|------|
| Core | **account** (:3000), **transactor** (:3332), **workspace**, **stats** (:4900) | auth, live data, workspace lifecycle, metrics |
| Storage | **datalake** (:4030), **hulylake** (:8096), **hulykvs** (:8094) | blobs, S3 adapter, key-value |
| Search | **fulltext** (:4702), **rekoni** (:4004) | indexing, document text extraction |
| Real-time | **collaborator** (:3078), **hulypulse** (:8099), **hulygun** | CRDT docs, push, event processor |
| Media | **stream** (:1080), **media**, **preview** (:4040) | video HLS, transcoding, thumbnails |
| Feature | print, sign, payment, export, analytics, process, rating | per-feature backends |
| Backup | backup, backup-api (:4039) | archival |
| Frontend | **front** (:8087) | static assets + `config.json` discovery |
| Infra | CockroachDB, Elasticsearch, MinIO, Redpanda, Redis | datastores + event bus |

Full table with ports, containers, dependencies, and env vars: see [ARCHITECTURE_OVERVIEW.md](../ARCHITECTURE_OVERVIEW.md) and the per-service pages under [services/](services/).

## Data flow: creating a document

```
Feature plugin (e.g. Tracker "create issue")
  │
  │ client.createDoc(tracker.class.Issue, space, attrs)
  ▼
TxOperations  ──builds──▶  TxCreateDoc (a Doc itself)
  │
  │ 1. apply optimistically to local ModelDb/cache  (UI updates immediately)
  │ 2. send tx() over WebSocket
  ▼
Transactor pipeline
  │ 3. persist to CockroachDB (DOMAIN_TX + object domain)
  │ 4. run triggers / derived data / fulltext index / queue event
  │ 5. broadcast the Tx[] to all sessions on the workspace
  ▼
All clients (incl. originator)
  │ 6. TxHandler applies broadcast tx → LiveQuery re-emits → UI reconciles
```

See [transaction-flow](flows/transaction-flow.md) and [live-query-flow](flows/live-query-flow.md) for the detailed sequences.

## Key design decisions

### Why transaction sourcing instead of REST?
A single generic protocol (`findAll`/`tx`) means new features need **no new server endpoints** — they just register document classes into the model. Real-time sync falls out for free because every write is a broadcastable transaction. The cost is that clients must implement the model/hierarchy/tx runtime rather than calling typed endpoints.

### Why a plugin/resource registry instead of imports?
Cross-feature references use string ids resolved at runtime, so plugins can be loaded, replaced, or omitted per deployment (e.g. a mobile build can drop desktop-only plugins) without compile-time coupling. See [plugin-architecture](concepts/plugin-architecture.md).

### Why no client singleton?
Unlike a typical SDK, Huly has **no global singleton**. The platform exposes a *resource registry* (`getResource`, `getPlugin`, `addLocation`) and a *client accessor* (`getClient()` from `@hcengineering/presentation`) scoped to the connected workspace. State lives in the `Hierarchy`/`ModelDb`/`LiveQuery` instances, not a global object.

## Cross-references

- [overview](overview.md) — High-level description
- [configuration](configuration.md) — Startup/connection sequence
- [concepts/](concepts/) — Cross-cutting architecture (plugins, model, transactions, queries)
- [services/](services/) — Per-service detail
- [flows/](flows/) — Step-by-step sequences

## Gotchas

- **`@hcengineering/core` must stay platform-agnostic** — no DOM, IndexedDB, or WebSocket imports. Transport lives in `client-resources`. This is what makes the core portable to a native/Dart client.
- **The model is loaded, not compiled in** — you cannot know all classes statically; query the `Hierarchy` at runtime.
- **There is no "subscribe" call** — connecting to a workspace *is* the subscription; live updates arrive as id-less `Response<Tx[]>` broadcasts.
