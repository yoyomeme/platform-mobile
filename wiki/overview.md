# Huly Platform Overview

> Huly is a plugin-based, transaction-sourced collaboration platform (project management, chat, CRM, HR, docs, and more) built as a TypeScript monorepo. This wiki documents the whole codebase: the core runtime, the model/transaction system, the server services, and the 190+ feature plugins.

## What it is

Huly is an **all-in-one workspace** — Tracker (issues), Chunter (chat), Documents, Drive, Contacts/CRM, HR, Recruiting, Calendar, and dozens more apps — running on a shared substrate. Unlike a typical REST app, Huly is:

- **Plugin-based**: every feature is a *plugin* registered into a runtime resource/plugin registry (`@hcengineering/platform`). The desktop, web, and (planned) mobile clients are compositions of plugins.
- **Transaction-sourced**: there is **no per-feature REST API**. Everything is a `Doc` stored in a workspace; **all reads go through `findAll`** and **all writes go through `tx`** over a single WebSocket to the **transactor**.
- **Self-describing**: the data schema *is* data. The **model** is a stream of transactions the client loads at startup to build a `Hierarchy` (classes, attributes, mixins). Plugins register their classes into this model.

The practical consequence: a client implements **one protocol** (account login + transactor WebSocket + blob storage), then talks to *every* feature through the same generic `Doc`/`Tx` mechanism.

## Design goals

1. **One generic data protocol** — `findAll`/`findOne`/`tx`/`searchFulltext` cover every feature; no bespoke endpoints.
2. **Runtime-extensible model** — classes, attributes, and mixins are loaded from transactions, so plugins extend the schema without server code changes.
3. **Real-time by default** — connecting to a workspace subscribes you to its transaction stream; the UI reacts to broadcast `Tx[]`.
4. **Plugin isolation** — features are independent packages wired together by string identifiers (`Resource`, `Plugin`, `IntlString`, `Asset`) resolved at runtime.
5. **Horizontal scale** — workspaces are sharded across transactors; storage, search, and events are separate services connected by an event queue.

## Technology stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| Language | TypeScript (strict) | Monorepo managed by **Rush** + PNPM (`rush.json`) |
| UI | Svelte | `packages/ui`, `packages/presentation`; SCSS theme in `packages/theme` |
| Transport | WebSocket (transactor), HTTP JSON-RPC (account), REST (blob/datalake) | optional MessagePack + Snappy compression |
| Data model | Custom `Doc`/`Tx`/`Hierarchy` runtime | `foundations/core/packages/core` |
| Primary DB | CockroachDB (Postgres wire) | also legacy MongoDB adapter |
| Search | Elasticsearch | via `fulltext` service + `rekoni` extraction |
| Object storage | MinIO (S3) via `datalake` / `hulylake` | blobs, previews, video |
| Real-time docs | Y.js CRDT via `collaborator` | rich-text markup |
| Events | Redpanda (Kafka) | async fan-out to fulltext/media/process |
| Auth | JWT bearer tokens | shared `SERVER_SECRET`; `@hcengineering/server-token` |

## Quick start (client perspective)

```typescript
// 1. Discover backend URLs from the front service (nothing is hardcoded)
const config = await fetch(`${BASE_URL}/config.json`).then(r => r.json())

// 2. Log in via the account service (JSON-RPC over HTTP)
const login = await accountClient.login(email, password)        // -> { account, token }
const wsInfo = await accountClient.selectWorkspace(workspaceUrl) // -> { endpoint, token }

// 3. Connect to the transactor WebSocket and load the model
const client = await createClient(wsInfo.endpoint, wsInfo.token) // loadModel -> Hierarchy

// 4. Read & write any feature through the generic API
const issues = await client.findAll(tracker.class.Issue, { space: projectId })
await client.createDoc(tracker.class.Issue, projectId, { title: 'New issue', /* ... */ })
```

## How to read this wiki

- New to Huly? Start with [architecture](architecture.md), then the [concepts](concepts/) pages — especially [plugin-architecture](concepts/plugin-architecture.md), [data-model](concepts/data-model.md), and [transaction-model](concepts/transaction-model.md).
- Building a client? Read [client-protocol](concepts/client-protocol.md), the [flows](flows/), and the [api](api/) pages.
- Looking for a specific app? See [plugins/catalog](plugins/catalog.md) for all 190+ plugins, or the per-app pages.

## Cross-references

- [architecture](architecture.md) — Layer diagram, service topology, data flow
- [configuration](configuration.md) — Startup/connection sequence
- [api-reference](api-reference.md) — Condensed API lookup
- [index](index.md) — Full page index
