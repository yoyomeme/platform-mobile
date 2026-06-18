# @hcengineering/query

> The reactive query engine. `LiveQuery` wraps a `Client`, caches `findAll` results, applies incoming transactions to those cached results in place, and re-invokes registered callbacks so the UI stays live without re-fetching.

## Where in code

- `foundations/core/packages/query/src/index.ts` -- the `LiveQuery` class (implements `Client` + `WithTx`), `query`/`queryFind` methods, result cache + LRU queue.
- `foundations/core/packages/query/src/results.ts` -- `ResultArray` mutable result container.
- `foundations/core/packages/query/src/refs.ts` -- `Refs` lookup resolver for `$lookup` population.
- `foundations/core/packages/query/src/types.ts` -- internal `Query`, `Callback`, `QueryId`.

## Purpose

`Client.findAll` is a one-shot read. Most UI needs live data: when a transaction mutates a document matching an open query, the result list should update automatically. `LiveQuery` provides exactly that — it sits between the UI and the `Client`, holds each active query's matched documents in a `ResultArray`, intercepts the transaction stream (it *is* a `Client`, so it forwards `tx` and observes `notify`), and incrementally patches cached results (add/remove/update/re-sort) on each matching tx. Subscribers registered via `query(...)` receive a fresh `FindResult<T>` whenever their data changes.

It also de-duplicates identical queries (multiple subscribers share one cache entry) and keeps a bounded LRU `queue` (`CACHE_SIZE = 125`) of recently-unsubscribed queries so re-subscribing is instant.

## Public API

### `LiveQuery` (`index.ts`)

`class LiveQuery implements WithTx, Client` — constructed with `new LiveQuery(client: Client)`.

| Member | Signature (abridged) | Notes |
|--------|----------------------|-------|
| `query<T>(_class, query, callback, options?)` | `(Ref<Class<T>>, DocumentQuery<T>, (result: FindResult<T>) => void, FindOptions<T>?) => () => void` | Subscribe; returns an **unsubscribe** function. Callback fires initially and on every matching change. |
| `queryFind<T>(_class, query, options?)` | `=> Promise<FindResult<T>>` | One-shot read that reuses the live cache when a matching query exists. |
| `findAll<T>` / `findOne<T>` | `Client` methods | Delegate to the underlying client (cache-aware). |
| `tx(tx)` | `(Tx) => Promise<TxResult>` | Forward write to client; result patching happens via the tx stream. |
| `searchFulltext` / `domainRequest` | `Client` methods | Pass-through. |
| `getHierarchy()` / `getModel()` | accessors | Pass-through. |
| `refreshConnect(clean)` | `(boolean) => Promise<void>` | Re-run all queued/active queries after reconnect. |
| `close()` / `isClosed()` | lifecycle | Closes the underlying client. |

`options.projection` is auto-augmented with `_class`, `space`, `modifiedOn` so the engine can match and re-sort cached docs.

### Result handling

| Export | Notes |
|--------|-------|
| `ResultArray` (`results.ts`) | Mutable ordered result holder; `getClone()` returns a fresh `FindResult` for callbacks (`clean()` releases it). |
| `Refs` (`refs.ts`) | Resolves `$lookup` references against the hierarchy when populating results. |

## Usage

```typescript
import { LiveQuery } from '@hcengineering/query'
import { type Client, type Ref, type FindResult, SortingOrder } from '@hcengineering/core'

declare const client: Client
const lq = new LiveQuery(client)

// Subscribe — callback fires now and on every matching transaction.
const unsubscribe = lq.query(
  tracker.class.Issue as Ref<any>,
  { space: projectId },
  (issues: FindResult<any>) => {
    // Re-render with the latest matched + sorted list.
    render(issues)
  },
  { sort: { modifiedOn: SortingOrder.Descending }, limit: 50 }
)

// One-shot read that piggybacks on the live cache.
const current = await lq.queryFind(tracker.class.Issue as Ref<any>, { space: projectId })

// Always release the subscription.
unsubscribe()
```

## Cross-references

- [core-package](core-package.md) -- the `Client`/`DocumentQuery`/`FindResult` types `LiveQuery` wraps and implements.
- [client-package](client-package.md) -- supplies the `Client` whose tx stream drives updates.
- [presentation-package](presentation-package.md) -- wraps this in a Svelte-aware `LiveQuery` + `createQuery()` with auto-unsubscribe on component destroy.
- Concepts: [live-queries](../concepts/live-queries.md), [transaction-model](../concepts/transaction-model.md).

## Gotchas

- **Always unsubscribe.** `query()` returns the unsubscribe fn; dropping it leaks the subscription. When the last subscriber of a query unsubscribes, the entry moves to the LRU `queue` (capacity 125) rather than being freed immediately — re-subscribing the same query is then a cache hit.
- **Two `LiveQuery` classes exist.** This is the low-level engine in `@hcengineering/query`. The Svelte UI uses a *different* `LiveQuery` in `@hcengineering/presentation` that wraps this one and ties lifecycle to `onDestroy`. Don't confuse them.
- **Callbacks receive clones.** Each emission is a `getClone()` of the cached `ResultArray`; do not retain or mutate it across emissions — treat results as immutable snapshots.
- **Projection is mutated.** `query`/`queryFind` inject `_class`/`space`/`modifiedOn` into any provided `projection`; a query asking for a narrow projection will still receive those fields.
- **Sorting/limits are re-applied on patch.** When a tx changes a matched doc, the engine re-sorts and re-applies `limit`, so a doc can drop out of (or into) a limited window as data changes.
