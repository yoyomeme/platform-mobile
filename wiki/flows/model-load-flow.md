# Model Load Flow

> How a client, once it has a transactor `endpoint + token`, opens the WebSocket, performs the Hello handshake, loads the **model** (the schema-as-data), and builds an in-memory `Hierarchy` + `ModelDb` — with hash-keyed caching so reconnects are cheap.

## Where in code
- `foundations/core/packages/client-resources/src/connection.ts` -- `Connection`: socket, Hello handshake, `loadModel(last, hash)`
- `foundations/core/packages/core/src/client.ts` -- `createClient`, `loadModel`, `buildModel` (builds `Hierarchy` + `ModelDb`)
- `foundations/core/packages/client-resources/src/index.ts` -- `GetClient` resource + `createModelPersistence` (IndexedDB cache, keyed by workspace)
- `foundations/core/packages/core/src/client.ts` -- `TxPersistenceStore` interface (`load`/`store` of `LoadModelResponse`)

## Sequence

```
 Client (createClient)        Connection (WS)            Transactor
    |                             |                          |
    | connect(txHandler)          |                          |
    |---------------------------->|                          |
    |                             | ws open                   |
    |                             |------------------------->|
    |                             | HelloRequest             |
    |                             |  {binary, compression}    |
    |                             |------------------------->|
    |                             | HelloResponse             |
    |                             |  {serverVersion, lastTx,  |
    |                             |   lastHash, account}      |
    |                             |<-------------------------|
    | persistence.load()          |                          |
    | → cached {hash, txs}        |                          |
    |                             |                          |
    |  if cachedHash == lastHash  → mode 'same' (no fetch)    |
    |                             |                          |
    |  else loadModel(lastTxTime, cachedHash)                |
    |---------------------------->|------------------------->|
    |                             | LoadModelResponse         |
    |                             |  {full, transactions,     |
    |                             |   hash}                   |
    |                             |<-------------------------|
    | buildModel(txes) →          |                          |
    |   Hierarchy + ModelDb        |                          |
    | persistence.store(merged)    |                          |
    |                             |                          |
    | client ready (findAll/tx)    |                          |
```

## Steps

| Step | Action | Error code on failure |
|------|--------|----------------------|
| 1 | Open `ws://{endpoint}/{token}?sessionId={uuid}`. Dial timeout ~30 s. | `DIAL-TIMEOUT` |
| 2 | On open, send `HelloRequest { method:'hello', id:-1, binary, compression }`. | |
| 3 | Receive `HelloResponse { serverVersion, lastTx, lastHash, account, useCompression, reconnect }`; store `lastHash`. | `VERSION-MISMATCH` (via `onHello`) |
| 4 | `persistence.load()` returns the cached model `{ hash, transactions }` (IndexedDB / local store). | |
| 5 | If `cached.hash === lastHash` → **mode `same`**: skip the network fetch, rebuild from cached txes. | |
| 6 | Else `loadModel(lastTxTime, cached.hash)` → `LoadModelResponse { full, transactions, hash }`. `full=false` means a diff to append. | `LOADMODEL-001` |
| 7 | `buildModel`: apply each model `Tx` into a new `Hierarchy` (classes/attrs/mixins) and `ModelDb`. | |
| 8 | `persistence.store(...)` the concatenated model (cache keyed by workspace, validated by `hash`). | |
| 9 | Construct the client; flush any buffered live txes; client is ready for `findAll`/`tx`. | |

## Code

```typescript
import { createClient } from '@hcengineering/core'
import { connect } from '@hcengineering/client-resources'

// txHandler receives BOTH the model txes at load and live broadcast txes after.
const client = await createClient(
  async (txHandler) => connect(`${endpoint}/${token}`, txHandler, workspaceUuid, accountUuid, {
    onHello: (serverVersion) => {
      // Return false to abort (e.g. client/server version skew) — triggers a reload upstream.
      return isCompatible(serverVersion)
    },
    onConnect: async (event, lastTx, sessionId) => { /* Connected | Reconnected | Refresh | Upgraded */ }
  }),
  modelFilter,          // optional: trim model to allowed plugins ('client' | 'ui' | 'none')
  persistenceStore      // TxPersistenceStore: { load(), store() } — the hash-keyed cache
)

// Now the model is built:
const hierarchy = client.getHierarchy()   // class/attribute/mixin metadata
const model = client.getModel()           // DOMAIN_MODEL docs queried locally
```

## Prerequisites

- A valid workspace-scoped `token` and transactor `endpoint` (see [login-flow](login-flow.md)).
- A `TxPersistenceStore` implementation for caching (IndexedDB on web; SQLite/Hive on mobile). It may be a no-op that always returns an empty model — then every start does a full `loadModel`.

## Error handling

```typescript
// Version skew: the Hello handshake exposes serverVersion; onHello returning false closes the socket.
onHello: (serverVersion) => {
  if (frontVersion !== serverVersion) {
    // web client reloads; a native client should prompt to update.
    return false
  }
  return true
}

// Dial timeout: no Hello within ~30s → onDialTimeout fires; re-select the workspace in case
// the endpoint moved, then reconnect.
onDialTimeout: async () => {
  const fresh = await account.selectWorkspace(workspaceUrl, token)
  if (fresh.endpoint !== endpoint) reload()
}
```

If `loadModel` returns `full: true` (an `upgrade`), the client **discards** its `Hierarchy`/`ModelDb` and rebuilds from scratch; a `false` response is a diff appended to the cached transactions.

## Cross-references

- [login-flow](login-flow.md) -- obtaining the endpoint + token first
- [transaction-flow](transaction-flow.md) -- once ready, how writes flow
- [live-query-flow](live-query-flow.md) -- once ready, how reactive reads work
- [client-protocol](../concepts/client-protocol.md), [model-layer](../concepts/model-layer.md)
- Service: [transactor](../services/transactor.md)
- Types: [tx-types](../types/tx-types.md), [core-types](../types/core-types.md)

## Gotchas

- **The model is data, not a schema file.** `loadModel` returns a stream of `Tx`es; `buildModel` replays them into a `Hierarchy` (classes, attributes, mixins) and a `ModelDb`. Plugins register their classes by emitting these model txes.
- **Cache key is the hash, not a version string.** `HelloResponse.lastHash` is compared to the cached model hash. Equal → `mode: 'same'`, zero network. The cache must be invalidated by hash, never by guesswork.
- **`loadModel` takes the last tx *time*, not the hash alone.** The client passes `getLastTxTime(cachedTxes)` plus the cached `hash`; the server returns either a full model or just the newer txes.
- **DOMAIN_MODEL reads are local.** After build, `findAll` on a `DOMAIN_MODEL` class is answered by the in-memory `ModelDb` (no round-trip); everything else goes to the transactor over the WS.
- **Buffer before ready.** Live broadcast txes that arrive while the model is still building are buffered (`txBuffer`) and replayed once the client exists, so none are lost. Model-space txes are filtered out of that buffer to avoid double-apply.
- **Optional MessagePack + Snappy.** The handshake negotiates `binary` (MessagePack via `Packr`) and `compression` (Snappy). A first mobile cut can use plain JSON (`binary:false, compression:false`).
- **`TxModelUpgrade` means reload.** If a `TxModelUpgrade` arrives on the live stream, the client must rebuild the model (the web client reloads the page).
```