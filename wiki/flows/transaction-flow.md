# Transaction Flow

> How **all writes** work in Huly: `TxOperations` builds a `Tx`, the model-space part is applied optimistically in memory, the tx is sent over the WS via `tx()`, the transactor persists + triggers, then **broadcasts the resulting `Tx[]`** back to every connected client which reconcile their local state.

## Where in code
- `foundations/core/packages/core/src/operations.ts` -- `TxOperations.createDoc/updateDoc/removeDoc/addCollection/...` build txes
- `foundations/core/packages/core/src/tx.ts` -- `TxFactory`, `TxProcessor` (the tx construction + apply primitives)
- `foundations/core/packages/core/src/client.ts` -- `ClientImpl.tx` (optimistic model apply) and `updateFromRemote` (reconcile broadcast)
- `foundations/core/packages/client-resources/src/connection.ts` -- `Connection.tx` (send over WS, with `TxApplyIf` retry) and broadcast handling

## Sequence

```
 TxOperations        ClientImpl          Connection (WS)        Transactor       Other Clients
     |                   |                    |                     |                 |
     | createDoc(...)    |                    |                     |                 |
     |------------------>|                    |                     |                 |
     |  TxFactory builds TxCreateDoc          |                     |                 |
     |                   | (if model space:   |                     |                 |
     |                   |  hierarchy.tx +     |                     |                 |
     |                   |  model.tx — local)  |                     |                 |
     |                   | tx(tx)              |                     |                 |
     |                   |------------------->| send {method:'tx',  |                 |
     |                   |                    |       params:[tx]}   |                 |
     |                   |                    |-------------------->|                 |
     |                   |                    |                     | persist + run   |
     |                   |                    |                     | triggers        |
     |                   |                    | Response (id) ack   |                 |
     |                   |                    |<--------------------|                 |
     |  Ref returned     |<-------------------|                     |                 |
     |<------------------|                    |                     |                 |
     |                   |                    | broadcast Tx[] (no id)                |
     |                   |                    |<--------------------|---------------->|
     |                   | updateFromRemote(...tx) → notify LiveQuery / handlers      |
```

## Steps

| Step | Action | Error code on failure |
|------|--------|----------------------|
| 1 | Call a `TxOperations` helper (`createDoc`, `updateDoc`, `removeDoc`, `addCollection`, ...). | |
| 2 | `TxFactory` builds the concrete tx (`TxCreateDoc` / `TxUpdateDoc` / `TxRemoveDoc` / `TxMixin` / collection CUD). | |
| 3 | **If the tx targets `core.space.Model`**, apply it locally first (`hierarchy.tx` + `model.tx`) for optimistic model updates. | |
| 4 | `Connection.tx` serializes and sends `{ method:'tx', params:[tx] }` over the WS and awaits the ack. | `ConnectionClosed` / rate-limit |
| 5 | Transactor persists the tx, runs server triggers (which may emit *derived* txes), and indexes for full-text. | server error → `PlatformError` |
| 6 | Transactor **broadcasts** the resulting `Tx[]` (the original + any derived) to all sessions, with **no response `id`** (server→client push). | |
| 7 | Each client's `txHandler` → `updateFromRemote` re-applies model txes (skipping ones it already applied) and `notify`s live queries / handlers, which re-fire UI updates. | |

## Code

```typescript
import { TxOperations } from '@hcengineering/core'
import tracker from '@hcengineering/tracker'

// `client` is the live client; `me` is your PersonId used as modifiedBy.
const ops = new TxOperations(client, me)

// CREATE — returns the new doc's Ref synchronously after the tx is acked.
const issueId = await ops.createDoc(tracker.class.Issue, projectSpace, {
  title: 'Fix login',
  status: openStatus,
  priority: IssuePriority.Medium,
  number: nextNumber
  // ...other required attributes
})

// UPDATE — operations object is a $set / $inc / $push style update.
await ops.updateDoc(tracker.class.Issue, projectSpace, issueId, { priority: IssuePriority.High })

// ADD TO A COLLECTION — e.g. a comment attached to the issue.
await ops.addCollection(
  chunter.class.ChatMessage, projectSpace,
  issueId, tracker.class.Issue, 'comments',
  { message: '<p>On it.</p>' }
)

// REMOVE
await ops.removeDoc(tracker.class.Issue, projectSpace, issueId)
```

## Prerequisites

- A ready client with a built model (see [model-load-flow](model-load-flow.md)).
- A `TxOperations` wrapping the client, constructed with the current `PersonId` (used as `modifiedBy`/`createdBy`).
- The target `space` exists and the account has write access (role enforced server-side).

## Error handling

```typescript
import { PlatformError } from '@hcengineering/platform'

try {
  await ops.createDoc(_class, space, attributes)
} catch (err: unknown) {
  if (err instanceof PlatformError) {
    // Server rejected the tx (permissions, validation, archived workspace, ...).
  } else {
    // Connection closed mid-flight. On reconnect, the connection auto-retries the tx
    // ONLY if it can confirm the tx was not already persisted (see retry below).
  }
}
```

`Connection.tx` carries a `retry` predicate: on reconnect it re-sends the tx **only if** `findAll(core.class.Tx, { _id: tx._id })` returns empty — i.e. the server never received it. For `TxApplyIf` it checks the inner tx id. This makes tx delivery idempotent across reconnects.

## Cross-references

- [model-load-flow](model-load-flow.md) -- the client must be ready first
- [live-query-flow](live-query-flow.md) -- how the broadcast `Tx[]` drives reactive UI
- [transaction-model](../concepts/transaction-model.md), [client-protocol](../concepts/client-protocol.md)
- Service: [transactor](../services/transactor.md)
- Types: [tx-types](../types/tx-types.md), [core-types](../types/core-types.md)

## Gotchas

- **One write API.** Every mutation — create, update, delete, mixin, collection — is a `Tx` sent through `tx()`. There is no per-feature write endpoint.
- **Optimism is model-only here.** `ClientImpl.tx` applies *model-space* txes locally before sending. For ordinary (non-model) docs, the optimistic UI update is produced by the **live query** layer when it sees the broadcast (or its own local update path), not by `ClientImpl.tx`.
- **The server echoes your own tx back.** You receive the broadcast of the tx you just sent (no response `id`). `updateFromRemote` de-duplicates model txes via `appliedModelTransactions` so they aren't applied twice; design any local handler to tolerate seeing its own write.
- **Derived txes.** Triggers on the transactor can emit additional txes (notifications, collaborators, activity). A single `createDoc` may broadcast several txes — handlers must process the whole array.
- **`createDoc` rejects AttachedDoc.** Use `addCollection` for `AttachedDoc` subclasses; `createDoc` throws for them. Model-domain classes must use `core.space.Model`.
- **`TxApplyIf` for conditional/atomic writes.** When a write must only land if a precondition holds, wrap it in `TxApplyIf`; the retry/idempotency logic checks the inner tx id.
```