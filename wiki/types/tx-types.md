# Transaction types

> Every write in Huly is a transaction (`Tx`) — itself a `Doc`. The server stores the tx log and replays/broadcasts it; clients build documents by folding transactions. Defined in `@hcengineering/core`.

## Where in code

- `foundations/core/packages/core/src/tx.ts` -- all `Tx*` interfaces, `DocumentUpdate`, collection operators, `TxProcessor`, `TxFactory`
- `models/core/src/tx.ts` -- the model classes (`TTx`, `TTxCreateDoc`, ...) that register tx classes into the model
- `foundations/core/packages/core/src/operations.ts` -- `TxOperations`, the high-level CRUD helper that builds these txes

## Definition

```typescript
// A transaction is a Doc. objectSpace is the space the tx OPERATES on
// (distinct from tx.space, which is core.space.Tx / DerivedTx).
export interface Tx extends Doc {
  objectSpace: Ref<Space>
  meta?: Record<string, string | number | boolean> // non-persisted
}

// Create/Update/Delete base. Carries the target object + optional collection link.
export interface TxCUD<T extends Doc> extends Tx {
  objectId: Ref<T>
  objectClass: Ref<Class<T>>
  attachedTo?: Ref<Doc>
  attachedToClass?: Ref<Class<Doc>>
  collection?: string
}

export interface TxCreateDoc<T extends Doc> extends TxCUD<T> {
  attributes: Data<T> // = Omit<T, keyof Doc>
}

export interface TxUpdateDoc<T extends Doc> extends TxCUD<T> {
  operations: DocumentUpdate<T>
  retrieve?: boolean // ask server to return the updated doc
}

export interface TxRemoveDoc<T extends Doc> extends TxCUD<T> {}

// Define create/update for mixin attributes (stored under the mixin's class id).
export interface TxMixin<D extends Doc, M extends D> extends TxCUD<D> {
  mixin: Ref<Mixin<M>>
  attributes: MixinUpdate<D, M>
}
```

```typescript
// Conditional / optimistic batch. Applies `txes` only if all match/notMatch hold.
export interface TxApplyIf extends Tx {
  scope?: string                       // only one op per scope at a time
  match?: DocumentClassQuery<Doc>[]    // every query must match >= 1 doc
  notMatch?: DocumentClassQuery<Doc>[] // every query must match 0 docs
  txes: TxCUD<Doc>[]                   // executed if conditions hold
  notify?: boolean
  extraNotify?: Ref<Class<Doc>>[]      // classes to bulk-notify
  measureName?: string
}

export interface DocumentClassQuery<T extends Doc> {
  _class: Ref<Class<T>>
  query: DocumentQuery<T>
}

export interface TxApplyResult {
  success: boolean
  serverTime: number
}

// Sent by the server (e.g. during model upgrade, security change, bulk update).
export interface TxWorkspaceEvent<T = any> extends Tx {
  event: WorkspaceEvent
  params: T
}

export enum WorkspaceEvent {
  UpgradeScheduled,
  IndexingUpdate,
  SecurityChange,
  MaintenanceNotification,
  BulkUpdate,
  LastTx
}
```

```typescript
// The update payload for TxUpdateDoc. Combines a plain partial set with operators.
export type DocumentUpdate<T extends Doc> = Partial<Data<T>> &
  PushOptions<T> &       // $push / $pull
  SetEmbeddedOptions<T> & // $update
  IncOptions<T> &        // $inc
  UnsetOptions &         // $unset
  SpaceUpdate            // optional space change

export interface PushOptions<T extends object> {
  $push?: Partial<OmitNever<ArrayAsElementPosition<Required<T>>>>
  $pull?: Partial<OmitNever<ArrayAsElement<Required<T>>>>
}
export interface IncOptions<T extends object> {
  $inc?: Partial<OmitNever<NumberProperties<T>>>
}
export interface SetEmbeddedOptions<T extends object> {
  $update?: Partial<OmitNever<ArrayAsElementUpdate<Required<T>>>>
}
export interface UnsetOptions {
  $unset?: Record<string, any>
}

// $push supports positional insert; $pull supports filtered removal.
export interface Position<X extends PropertyType> { $each: X[], $position: number }
export interface PullArray<X extends PropertyType> { $in: X[] }
```

## Fields / Cases

### Transaction class hierarchy

| Type | Extends | Adds | Purpose |
|------|---------|------|---------|
| `Tx` | `Doc` | `objectSpace`, `meta?` | Base transaction. |
| `TxCUD<T>` | `Tx` | `objectId`, `objectClass`, `attachedTo?`, `collection?` | Base for create/update/remove. |
| `TxCreateDoc<T>` | `TxCUD<T>` | `attributes: Data<T>` | Create a new doc. |
| `TxUpdateDoc<T>` | `TxCUD<T>` | `operations: DocumentUpdate<T>`, `retrieve?` | Mutate fields / arrays. |
| `TxRemoveDoc<T>` | `TxCUD<T>` | — | Delete a doc. |
| `TxMixin<D,M>` | `TxCUD<D>` | `mixin`, `attributes: MixinUpdate<D,M>` | Set mixin attributes on a doc. |
| `TxApplyIf` | `Tx` | `match`, `notMatch`, `txes`, ... | Conditional/optimistic batch (server-only apply). |
| `TxWorkspaceEvent<T>` | `Tx` | `event`, `params` | Server-emitted system event. |

### `DocumentUpdate` operators

| Operator | Where | Effect |
|----------|-------|--------|
| `field: value` | top-level | Plain set of an attribute. |
| `$push` | `PushOptions` | Append to array; `{ $each, $position }` for positional insert. |
| `$pull` | `PushOptions` | Remove matching elements; `{ $in: [...] }` for set removal. |
| `$inc` | `IncOptions` | Atomic numeric increment/decrement. |
| `$update` | `SetEmbeddedOptions` | Update embedded array elements matching `$query`. |
| `$unset` | `UnsetOptions` | Remove a field. |
| `space` | `SpaceUpdate` | Move the doc to another space. |

## Usage

```typescript
// You rarely build Tx objects by hand. Use TxOperations (the client) instead;
// each call constructs a Tx via TxFactory and sends it through tx().
await client.createDoc(tracker.class.Issue, spaceId, { title, ... })           // -> TxCreateDoc
await client.updateDoc(tracker.class.Issue, spaceId, issueId, {                 // -> TxUpdateDoc
  title: 'New title',
  $push: { labels: labelRef },
  $inc: { commentsCount: 1 }
})
await client.removeDoc(tracker.class.Issue, spaceId, issueId)                   // -> TxRemoveDoc

// Collections (AttachedDocs) build a TxCreateDoc wrapped as a collection CUD:
await client.addCollection(chunter.class.ChatMessage, spaceId,
  parentId, parentClass, 'messages', { message })                              // -> collection TxCreateDoc
```

```typescript
// TxProcessor folds a tx stream into a document (client-side, in live queries):
const doc = TxProcessor.buildDoc2Doc<Issue>(txesForObject) // create + updates + mixins
```

## Related types

- The docs these txes operate on: [core-types](core-types.md) (`Doc`, `AttachedDoc`, `Data<T>`).
- The queries embedded in `TxApplyIf.match`: [query-types](query-types.md) (`DocumentQuery`).

## Cross-references

- [transaction-model concept](../concepts/transaction-model.md)
- [client-protocol concept](../concepts/client-protocol.md)
- [event-queue concept](../concepts/event-queue.md)
- [core-package service](../services/core-package.md)
- [transactor service](../services/transactor.md)

## Gotchas

- `tx.space` is **not** the operated space. The tx lives in `core.space.Tx` (or `core.space.DerivedTx` for derived txes); the doc being changed lives in `tx.objectSpace`.
- `TxApplyIf` is applied on the **server only** — `TxProcessor.tx()` returns `[]` for it client-side. Use it for optimistic concurrency: the batch commits atomically iff all `match`/`notMatch` conditions hold.
- `TxMixin` does not create a document. It writes `attributes` onto the existing doc under a key equal to the mixin class id (`doc[mixinRef] = { ... }`).
- `Data<T> = Omit<T, keyof Doc>` — so `TxCreateDoc.attributes` excludes `_id`, `_class`, `space`, `modifiedOn/By`; those come from the tx envelope itself (see `TxProcessor.createDoc2Doc`).
- A document is **state derived from its tx log**, not stored standalone in the canonical model. `buildDoc2Doc` returns `null` if a `TxRemoveDoc` is present, `undefined` if no create exists.
- `$push`/`$pull`/`$inc`/`$update`/`$unset` are typed against the doc's array/number fields via mapped types (`ArrayAsElement*`, `NumberProperties`). Passing a wrong-shaped operand is a compile error.
