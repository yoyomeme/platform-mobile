# Transaction Model — Tx, TxOperations, TxProcessor

> Every write in Huly is a `Tx` document. `TxOperations` builds the right `Tx` for a CRUD intent, `TxProcessor` materializes a `Tx` into (or out of) a `Doc`, and the server broadcasts applied `Tx`es back to all clients for real-time sync.

## Where in code

- `foundations/core/packages/core/src/tx.ts` -- `Tx`, `TxCUD`, `TxCreateDoc`, `TxUpdateDoc`, `TxRemoveDoc`, `TxMixin`, `TxApplyIf`, `TxWorkspaceEvent`; `TxFactory`; `TxProcessor`; `DocumentUpdate` operators.
- `foundations/core/packages/core/src/operations.ts` -- `TxOperations` (high-level CRUD), `ApplyOperations`, `TxBuilder`, `getDiffUpdate`, `updateAttribute`.
- `models/core/src/tx.ts` -- the `@Model` declarations registering the Tx classes (`TTx`, `TTxCUD`, `TTxCreateDoc`, …) into the schema.
- `foundations/core/packages/core/src/memdb.ts` -- `ModelDb.txCreateDoc/txUpdateDoc/txRemoveDoc/txMixin` apply Tx to the in-memory store.
- `foundations/core/packages/core/src/operator.ts` -- `_getOperator` ( `$push`, `$pull`, `$inc`, `$unset`, … ).

## Purpose

Huly is **transaction-sourced**: the durable truth is an append-only log of `Tx` documents, and a document's current state is the fold of all transactions targeting its `_id`. This gives a uniform write path (`client.tx(tx)`), a natural audit/activity feed, optimistic local application, and a trivial real-time channel — the server simply re-broadcasts each applied transaction and every client folds it into its local cache.

`TxOperations` exists so feature code never hand-builds transactions: it offers `createDoc`/`updateDoc`/`removeDoc`/`addCollection`/… that produce correct `Tx`es and submit them.

## Details

### The Tx hierarchy

```typescript
export interface Tx extends Doc {            // a transaction is itself a Doc (stored in DOMAIN_TX)
  objectSpace: Ref<Space>                    // space the tx operates on
  meta?: Record<string, string | number | boolean>
}

export interface TxCUD<T extends Doc> extends Tx {   // create/update/delete/mixin base
  objectId: Ref<T>
  objectClass: Ref<Class<T>>
  attachedTo?: Ref<Doc>            // set when the target is an AttachedDoc (collection item)
  attachedToClass?: Ref<Class<Doc>>
  collection?: string
}
```

| Tx class | Extends | Carries | Effect on the target doc |
|----------|---------|---------|--------------------------|
| `TxCreateDoc<T>` | `TxCUD<T>` | `attributes: Data<T>` | Creates the doc from attributes + tx metadata. |
| `TxUpdateDoc<T>` | `TxCUD<T>` | `operations: DocumentUpdate<T>`, `retrieve?` | Applies field sets and `$`-operators. |
| `TxRemoveDoc<T>` | `TxCUD<T>` | — | Deletes the doc. |
| `TxMixin<D,M>` | `TxCUD<D>` | `mixin`, `attributes: MixinUpdate<D,M>` | Sets/updates the mixin's nested object on the doc. |
| `TxApplyIf` | `Tx` | `match`, `notMatch`, `txes`, `scope` | Conditional/optimistic batch (server-evaluated). |
| `TxWorkspaceEvent<T>` | `Tx` | `event: WorkspaceEvent`, `params` | Server→client signal (indexing, security, maintenance). |

### DocumentUpdate operators

`TxUpdateDoc.operations` is a `DocumentUpdate<T>` — a partial of the doc's data plus Mongo-style array/number operators:

```typescript
export type DocumentUpdate<T extends Doc> = Partial<Data<T>>
  & PushOptions<T>        // $push (with $each/$position), $pull (with $in)
  & SetEmbeddedOptions<T> // $update (array element by $query/$update)
  & IncOptions<T>         // $inc
  & UnsetOptions          // $unset
  & SpaceUpdate           // space?: move to another space
```

### TxFactory — constructing transactions

`TxFactory` is the low-level builder; it stamps `_id`, `_class`, `space` (`core.space.Tx` or `DerivedTx`), `modifiedBy/On`, and the CUD fields:

```typescript
class TxFactory {
  constructor (readonly account: PersonId, readonly isDerived = false) {
    this.txSpace = isDerived ? core.space.DerivedTx : core.space.Tx
  }
  createTxCreateDoc<T>(_class, space, attributes, objectId?, …): TxCreateDoc<T> {
    return { _id: generateId(), _class: core.class.TxCreateDoc, space: this.txSpace,
             objectId: objectId ?? generateId(), objectClass: _class, objectSpace: space,
             modifiedOn: Date.now(), modifiedBy: this.account, attributes }
  }
  createTxUpdateDoc(...), createTxRemoveDoc(...), createTxMixin(...), createTxApplyIf(...)
  createTxCollectionCUD(...)   // wraps a child Tx with attachedTo/attachedToClass/collection
}
```

### TxOperations — the high-level CRUD API

`TxOperations` wraps a `Client` and a `TxFactory`, exposing the surface feature code (and a mobile port) actually calls. Each method builds a `Tx` and submits it via `client.tx`:

```typescript
class TxOperations implements Omit<Client, 'notify'> {
  constructor (readonly client: Client, readonly user: PersonId, readonly isDerived = false) {
    this.txFactory = new TxFactory(user, isDerived)
  }

  async createDoc<T>(_class, space, attributes, id?): Promise<Ref<T>> {
    // guards: AttachedDoc must use addCollection; DOMAIN_MODEL classes must use core.space.Model
    const tx = this.txFactory.createTxCreateDoc(_class, space, attributes, id)
    await this.tx(tx)
    return tx.objectId
  }

  updateDoc<T>(_class, space, objectId, operations, retrieve?): Promise<TxResult>
  removeDoc<T>(_class, space, objectId): Promise<TxResult>

  addCollection<T, P extends AttachedDoc>(_class, space, attachedTo, attachedToClass,
    collection, attributes, id?): Promise<Ref<P>>     // wraps a TxCreateDoc in a collection CUD
  updateCollection(...) / removeCollection(...)

  createMixin<D,M>(...) / updateMixin<D,M>(...)         // TxMixin
  apply(scope?, measure?): ApplyOperations             // start a conditional batch
}
```

Higher-level conveniences:

- `update(doc, update)` / `remove(doc)` infer class/space/collection from a live `doc` and route to `updateDoc`/`updateCollection`/`updateMixin` automatically (splitting mixin attributes from base attributes via `splitMixinUpdate`).
- `diffUpdate(doc, update)` computes only the changed fields (`getDiffUpdate`) and skips the write if nothing changed.

### TxProcessor — applying a Tx to a Doc

`TxProcessor` is the abstract folder. Its static methods turn transactions into document state and are used by both the client cache and the model:

```typescript
TxProcessor.createDoc2Doc(tx)      // TxCreateDoc → new Doc (merges attributes + _id/space/modified*)
TxProcessor.updateDoc2Doc(doc, tx) // applies DocumentUpdate operators in place, bumps modified*
TxProcessor.updateMixin4Doc(doc, tx) // writes tx.attributes into doc[tx.mixin]
TxProcessor.buildDoc2Doc(txes)     // folds a whole tx list → current Doc (or null if removed)
```

`applyUpdate` is the operator dispatcher — `$`-prefixed keys go through `_getOperator`, plain keys are direct sets:

```typescript
static applyUpdate<T extends Doc>(doc: T, ops: any): void {
  for (const key in ops) {
    if (key.startsWith('$')) _getOperator(key)(doc, ops[key])
    else setObjectValue(key, doc, ops[key])
  }
}
```

The instance method `tx(...txes)` dispatches on `tx._class` to abstract `txCreateDoc/txUpdateDoc/txRemoveDoc/txMixin`; `ModelDb` and the live-query cache implement these. Note `TxApplyIf` is resolved server-side, so the client-side processor returns `[]` for it.

### TxApplyIf — optimistic / conditional batches

`ApplyOperations` (from `txOps.apply()`) accumulates CUD txes and `match`/`notMatch` conditions, then `commit()` packages them into one `TxApplyIf`. The server applies all `txes` atomically **only if** every `match` query has ≥1 doc and every `notMatch` has 0 — returning `{ success, serverTime }`. A single tx with no conditions is sent directly (no `TxApplyIf` wrapper):

```typescript
const ops = txOps.apply('issue-rank-fix')
ops.match(tracker.class.Issue, { _id })            // optimistic precondition
await ops.updateDoc(tracker.class.Issue, space, _id, { rank })
const { result } = await ops.commit()              // false ⇒ precondition failed, retry
```

### Lifecycle & broadcast

```
TxOperations.createDoc(...)                 (client)
        │ builds TxCreateDoc, optimistic apply to local cache
        ▼
client.tx(tx)  ──ws──► transactor           (server)
        │                     │ persist to DOMAIN_TX, fold into stored doc, run triggers
        │                     ▼
        │              broadcast Response<Tx[]>  (no request id ⇒ server push)
        ▼                     │
   awaits TxResult            ├──► originating client: reconcile optimistic state
                             └──► every other client: TxProcessor folds tx into cache → UI updates
```

There is no separate subscribe call — connecting to a workspace subscribes you to its transaction stream. **Derived data** (counts, activity, notifications) is produced by server-side triggers emitting *further* transactions (often in `core.space.DerivedTx`), which broadcast the same way.

## Cross-references

- [data-model](data-model.md) — `Doc`/`Class`/`Mixin`/`AttachedDoc` that transactions create and mutate; `Hierarchy.tx` for model txes.
- [client-protocol](client-protocol.md) — the `tx()` RPC and the server→client broadcast framing.
- [live-queries](live-queries.md) — how broadcast txes drive reactive query subscriptions.
- [model-layer](model-layer.md) — `@Model` emits the `TxCreateDoc`s that define classes.
- [tx-types](../types/tx-types.md) — full field reference for each Tx subclass.

## Gotchas

- `createDoc` **throws** for `AttachedDoc` subclasses (use `addCollection`) and for `DOMAIN_MODEL` classes created outside `core.space.Model`. These guards live in `TxOperations.createDoc`.
- `TxApplyIf` is **not** processed by the client `TxProcessor` (`return []`) — its effect only happens after the server evaluates the conditions and broadcasts the contained txes back.
- `TxMixin` writes a nested object keyed by the mixin id; it does **not** create a row. Reading those fields requires `Hierarchy.as(doc, mixin)`.
- `modifiedOn`/`modifiedBy` default to `Date.now()` / the factory's account, but most methods accept explicit overrides — used by migrations and imports to preserve original timestamps.
- `ApplyOperations.commit()` returning `{ result: false }` means a `match`/`notMatch` precondition failed (optimistic conflict), not a transport error — the caller must decide to retry.
- `update(doc, ...)` reads `doc._class`, `doc.space`, and (for attached docs) `attachedTo*` off the passed object — call it with a fresh, fully-populated doc, not a partial.
