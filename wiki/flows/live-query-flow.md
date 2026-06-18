# Live Query Flow

> How a reactive read works: `query(_class, query, cb)` runs an initial `findAll`, fires the callback with results, then keeps the callback fresh by re-evaluating against every broadcast `Tx[]` — and unsubscribes when the returned disposer is called.

## Where in code
- `foundations/core/packages/query/src/index.ts` -- `LiveQuery.query()` (subscribe + disposer), `createQuery`, `callback`, `_tx`/`tx` (apply broadcast txes)
- `foundations/core/packages/query/src/results.ts` -- `ResultArray` (the maintained result set)
- `foundations/core/packages/core/src/client.ts` -- `ClientImpl.updateFromRemote` → `notify` feeds the `LiveQuery`

## Sequence

```
 Caller            LiveQuery             ClientImpl / Connection        Transactor
   |                  |                          |                         |
   | query(_class, q, cb)                        |                         |
   |----------------->|                          |                         |
   |                  | findAll(_class, q, opts) |                         |
   |                  |------------------------->| WS findAll ----------->|
   |                  |                          | FindResult<T> <--------|
   |                  | build ResultArray         |                         |
   |  cb(result)  <---| (initial fire)            |                         |
   |                  |                          |                         |
   |  disposer  <-----|                          |                         |
   |                  |                          |                         |
   |  ...later, someone writes (see transaction-flow)...                   |
   |                  |                          | broadcast Tx[] (no id) <|
   |                  | notify(...tx) → tx(...tx)|                         |
   |                  |  for each matching query:|                         |
   |                  |   add/update/remove docs |                         |
   |  cb(newResult) <-| (re-fire)                 |                         |
   |                  |                          |                         |
   | disposer()       |                          |                         |
   |----------------->| remove callback; if last,|                         |
   |                  | park query in LRU cache  |                         |
```

## Steps

| Step | Action | Error code on failure |
|------|--------|----------------------|
| 1 | `query(_class, query, callback, options?)` — registers a callback under a generated `callbackId`. | |
| 2 | Reuse an existing identical query if one is live (`getQuery`), else `createQuery`. | |
| 3 | Seed results: try the local doc cache (`refs.findFromDocs`); otherwise `client.findAll`. | `FINDALL-001` |
| 4 | When results resolve, set `q.total` and **fire the callback** with the initial `FindResult`. | |
| 5 | On every broadcast `Tx[]` (`notify` → `LiveQuery.tx`), each affected query re-evaluates: add/update/remove the matching doc(s) in its `ResultArray`. | |
| 6 | If results changed, **re-fire the callback** (`callback(q)`), so the UI updates. Over-limit edits trigger a full `refresh` (re-`findAll`). | |
| 7 | Call the returned **disposer** to unsubscribe; when a query has no callbacks left it is parked in an LRU cache (re-usable), then evicted past `CACHE_SIZE`. | |

## Code

```typescript
import { LiveQuery } from '@hcengineering/query'
import tracker from '@hcengineering/tracker'

const lq = new LiveQuery(client)

// Subscribe: callback fires immediately with the initial set, then on every change.
const unsubscribe = lq.query(
  tracker.class.Issue,
  { space: projectSpace, status: openStatus },
  (issues) => {
    render(issues)          // issues: FindResult<Issue>, total available as issues.total
  },
  { sort: { modifiedOn: SortingOrder.Descending }, limit: 50, total: true }
)

// ...when the view closes:
unsubscribe()
```

## Prerequisites

- A ready client (see [model-load-flow](model-load-flow.md)).
- A `LiveQuery` instance wired to that client (its `notify` hook receives broadcast txes via `updateFromRemote`).
- The query/options use only supported operators (`$in`, `$gt`, `$like`, `$exists`, ... see [client-protocol](../concepts/client-protocol.md)).

## Error handling

```typescript
// The initial findAll runs inside createQuery and is caught internally:
//   .catch(err => { Analytics.handleError(err); console.log('failed to update Live Query', err) })
// The callback is NOT invoked on failure — guard your UI for a no-result state until first fire.

// On reconnect with a changed lastTx, the client emits ClientConnectEvent.Refresh, and
// LiveQuery.refreshConnect() re-runs all live queries so no broadcast was missed while offline.
```

## Cross-references

- [transaction-flow](transaction-flow.md) -- the broadcast txes that drive re-fires
- [model-load-flow](model-load-flow.md) -- client readiness
- [live-queries](../concepts/live-queries.md), [client-protocol](../concepts/client-protocol.md)
- Service: [transactor](../services/transactor.md)
- Types: [query-types](../types/query-types.md), [tx-types](../types/tx-types.md), [core-types](../types/core-types.md)

## Gotchas

- **There is no subscribe RPC.** Connecting to a workspace already subscribes you to its tx stream; the `LiveQuery` simply filters the broadcast against each registered query. Reactivity is a client-side re-evaluation of server pushes.
- **The disposer is the only unsubscribe.** `query()` returns `() => void`. Forgetting to call it leaks callbacks; the query stays "live" (parked in the LRU) and keeps re-evaluating.
- **Parked, not destroyed.** When the last callback is removed, the query is kept in an LRU cache (`CACHE_SIZE`) so an identical re-subscribe is instant; it is only truly removed on eviction.
- **Identical queries are shared.** Two callers with the same `_class`/query/options share one underlying query; each gets its own `callbackId`.
- **Limit edge cases force a refresh.** If a change would push the result past `options.limit` (or a `$search` match changes), the layer does a full `findAll` refresh rather than a local splice — correct, but a heavier round-trip.
- **Projections get augmented.** `query()` always adds `_class`, `space`, `modifiedOn` to any `projection` so reconciliation works; expect those fields in results even if you didn't ask for them.
- **Callbacks must be cheap and idempotent.** They can fire many times (initial + every relevant broadcast). Do the diffing/rendering, not heavy work, inside them.
```