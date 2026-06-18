# Live Queries

> `@hcengineering/query`'s `LiveQuery`: a reactive layer over `findAll` that keeps query results up to date by applying the transactor's live transaction broadcast to cached results, with refcounting and an LRU result cache.

## Where in code

- `foundations/core/packages/query/src/index.ts` -- the `LiveQuery` class: `query()`, `findAll`/`findOne`, the `tx`/`txCreateDoc`/`txUpdateDoc`/`txRemoveDoc`/`txMixin` handlers that mutate cached results, query caching and the `CACHE_SIZE` LRU eviction.
- `foundations/core/packages/query/src/types.ts` -- `Query`, `QueryId`, `Callback`.
- `foundations/core/packages/query/src/results.ts` -- `ResultArray`: per-callback cloned result snapshots.
- `foundations/core/packages/query/src/refs.ts` -- `Refs`: a `_class → _id → doc` index used to answer single-doc / `limit:1` queries from already-cached documents.
- `packages/presentation/src/utils.ts` -- the Svelte-facing `LiveQuery` wrapper and `createQuery()` (see [ui-framework](ui-framework.md)).

## Purpose

A one-shot `findAll` gives you a snapshot that is stale the moment another user edits something. `LiveQuery` turns a query into a **subscription**: you register a class + query + callback, get the current result immediately, and then get the callback re-invoked every time an incoming transaction changes what the query matches. It is the bridge between the raw transactor broadcast (a flat stream of `Tx`) and the UI's "this list/doc, always current" model.

`LiveQuery implements WithTx, Client` — it *is* the `TxHandler` registered on the connection (its `tx(...txes)` method receives the live broadcast) and it also proxies `findAll`/`findOne`/`searchFulltext` through to the underlying `Client`.

## Details

### Registering a query

```typescript
query<T extends Doc>(
  _class: Ref<Class<T>>,
  query: DocumentQuery<T>,
  callback: (result: FindResult<T>) => void,
  options?: FindOptions<T>
): () => void   // returns an unsubscribe function
```

Flow:
1. `query()` generates a `callbackId` and looks for an existing identical query (`getQuery` → `findQuery`, comparing `_class`, `query`, and `options` with `deepEqual`).
2. If found, the new callback is **attached to the shared `Query`** (`pushCallback`) — multiple subscribers fan out from one server `findAll`.
3. If not, `createQuery` issues `client.findAll(...)`, wraps the docs in a `ResultArray`, and stores the `Query` in `queries: Map<_class, Map<QueryId, Query>>`.
4. The callback fires once with the initial result (via a `setTimeout(…, 0)` so it's always async), then again on every relevant transaction.
5. The returned function unsubscribes: it deletes the callback; when the last callback is gone, the query is parked in the LRU `queue` rather than destroyed immediately.

```typescript
const unsub = liveQuery.query(
  tracker.class.Issue,
  { space: projectId },
  (issues) => { render(issues) },         // called now AND on every change
  { sort: { modifiedOn: SortingOrder.Descending } }
)
// later:
unsub()
```

### How results auto-update from the broadcast

The connection delivers broadcast `Tx[]` to `LiveQuery.tx(...txes)`. For each transaction it dispatches by type (`TxProcessor`):

| Tx type | Handler | Effect on cached results |
|---------|---------|--------------------------|
| `TxCreateDoc` | `txCreateDoc` | Build the doc; for each query it now matches, insert into the `ResultArray` (respecting `sort`/`limit`) and re-fire callbacks. |
| `TxUpdateDoc` | `txUpdateDoc` | Apply the update to the cached doc; the doc may newly match, stop matching, or re-sort within each query. |
| `TxRemoveDoc` | `txRemoveDoc` | Remove from every query whose result held it. |
| `TxMixin` | `txMixin` | Apply mixin attributes; re-evaluate matches (mixin queries). |
| `TxWorkspaceEvent` | (bulk/index/upgrade) | `BulkUpdateEvent`/`IndexingUpdateEvent` trigger targeted refreshes. |

For each affected `Query`, the handler calls `this.callback(q)` which rebuilds the per-callback snapshot and invokes every callback with a fresh `FindResult`. Matching uses `match(q, doc)` → `findProperty`/`matchQuery` against the hierarchy, so mixin and derived-class semantics are respected. When a transaction can't be reconciled locally (e.g. an item leaves a `limit`-bounded window and the window must be refilled), the query falls back to `refresh(q)` → a fresh server `findAll`.

```
transactor --broadcast Tx[]--> Connection.handlers --> LiveQuery.tx(...txes)
                                                          │ classify each Tx
                                                          ▼
                                  for each matching Query: mutate ResultArray
                                                          ▼
                                  q.callbacks.forEach(cb => cb(snapshot))
                                                          ▼
                                                    UI re-renders
```

### Result caching and the `ResultArray`

Each `Query` holds a `ResultArray` (`results.ts`) — a `Map<Ref<Doc>, WithLookup<Doc>>` of the live documents plus a set of **per-callback clones**:
- `getResult(callbackId)` returns a clone dedicated to that callback, so one subscriber can't mutate another's array.
- `updateDoc`/`push`/`pop`/`delete`/`sort` keep both the master map and every clone in sync.
- `getClone()` is used for one-off `findAll`/`findOne` reads through `LiveQuery`.

This is why callbacks receive immutable-feeling snapshots: each callback owns its own cloned list.

### The `Refs` single-doc index

`refs.ts` indexes every cached doc by `_class:lookup:associations → _id`. `findFromDocs` answers two cases **without hitting the server**:
- exact `_id` queries (`findOne` by id),
- `limit:1`, no-sort, no-projection queries that some cached doc already satisfies.

`LiveQuery.findAll`/`findOne` consult `Refs` first; a hit returns instantly from cache.

### Refcounting and LRU eviction

```typescript
const CACHE_SIZE = 125
```

- A `Query` is shared by all callbacks with identical `_class`/`query`/`options`; `q.callbacks` is the refcount.
- When the last callback unsubscribes, the query moves to `queue` (the LRU pool) instead of being dropped — so a screen that re-mounts the same query reuses the warm result.
- `findAll`/`findOne` also create transient "dump" queries (`createDumpQuery`) that get parked in `queue`.
- When `queue.size > CACHE_SIZE`, `remove()` evicts the least-recently-used queries down to 80 % of `CACHE_SIZE` (100), calling `removeQueue` which also releases their docs from the `Refs` index.

### Reconnect refresh

`refreshConnect(clean)` re-runs every active query after a reconnect. With `clean = true` it first empties results (`cleanQuery` fires callbacks with an empty result) and then re-queries the server, so the UI never shows data from a stale session.

### vs. a one-shot `findAll`

| | `client.findAll` | `LiveQuery.query` |
|--|------------------|-------------------|
| Returns | one snapshot | initial snapshot **+** live updates |
| Update on others' edits | no (stale) | yes, via broadcast |
| Server round-trips | one per call | one per *distinct* query, shared across callbacks |
| Caching | none | LRU result cache + `Refs` single-doc cache |
| Cleanup | none | must call the returned `unsubscribe()` |
| Use when | a momentary read, export, validation | anything rendered on screen |

`LiveQuery.findAll`/`findOne` for `DOMAIN_MODEL` classes bypass the cache and go straight to the client, since the model is immutable for the session.

## Cross-references

- [client-protocol](client-protocol.md) -- the broadcast stream and `TxHandler` that feed `LiveQuery.tx`.
- [transaction-model](transaction-model.md) -- the `Tx` types the handlers dispatch on.
- [data-model](data-model.md) -- `Hierarchy`, `matchQuery`, mixin/derived semantics used by `match`.
- [ui-framework](ui-framework.md) -- `presentation`'s `createQuery`/`LiveQuery` Svelte wrapper.
- Service: [query-package](../services/query-package.md), [presentation-package](../services/presentation-package.md)
- Flows: [live-query-flow](../flows/live-query-flow.md)
- Types: [query-types](../types/query-types.md), [core-types](../types/core-types.md)

## Gotchas

- **You must unsubscribe.** `query()` returns the unsubscribe function; dropping it leaks the callback and keeps the query warm in the LRU pool. The `presentation` wrapper handles this via Svelte `onDestroy`.
- **The first callback is async** (`setTimeout(…, 0)`), so don't assume the result exists synchronously right after `query()` returns.
- Each callback gets its **own clone** of the result. Mutating it does not affect other subscribers or the cache — but it also won't persist; mutations must go through `tx`.
- Queries are de-duplicated by **deep equality** of `_class`/`query`/`options`. A query object rebuilt with a different key order still matches; but a different callback identity creates a new callback on the same shared query.
- `DOMAIN_MODEL` reads are never live-cached — the model is fixed for the session and reloaded only on `TxModelUpgrade`.
- Eviction is **silent**: an evicted-then-re-requested query simply does a fresh `findAll`; it does not error.
