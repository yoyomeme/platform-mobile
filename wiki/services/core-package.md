# @hcengineering/core

> The platform-agnostic model/transaction/hierarchy/client runtime. Defines `Doc`/`Tx`/`Class`, the `Hierarchy` + `ModelDb`, the `Client` interface, and `TxOperations` — the high-level CRUD helper.

## Where in code

- `foundations/core/packages/core/src/index.ts` -- barrel re-exporting every module below.
- `foundations/core/packages/core/src/classes.ts` -- core data primitives (`Doc`, `Class`, `Ref`, `Space`, `Domain`, `AttachedDoc`, `Blob`, `AccountRole`).
- `foundations/core/packages/core/src/tx.ts` -- transaction types (`Tx`, `TxCUD`, `TxCreateDoc`, `TxUpdateDoc`, `TxRemoveDoc`, `TxMixin`, `TxApplyIf`), `TxFactory`, `TxProcessor`.
- `foundations/core/packages/core/src/hierarchy.ts` -- `Hierarchy` (class/attribute/mixin lookup, built from model txes).
- `foundations/core/packages/core/src/memdb.ts` -- `MemDb` / `ModelDb` in-memory document store.
- `foundations/core/packages/core/src/storage.ts` -- query/find types (`DocumentQuery`, `FindOptions`, `FindResult`, `Storage`).
- `foundations/core/packages/core/src/client.ts` -- `Client` / `ClientConnection` interfaces, `createClient`, model load + build.
- `foundations/core/packages/core/src/operations.ts` -- `TxOperations`, `ApplyOperations`, `TxBuilder`.
- `foundations/core/packages/core/src/utils.ts` -- `generateId`, `getCurrentAccount`, helpers.

## Purpose

Huly is transaction-sourced: the data schema is itself data. `@hcengineering/core` is the runtime that loads a stream of model transactions, builds a `Hierarchy` of classes/attributes/mixins, holds the model in a `ModelDb`, and exposes generic read (`findAll`) and write (`tx`) operations. Every feature plugin defines its document classes against these primitives, so there is no per-feature API — only `Doc` subclasses and `Tx` instances.

This package is the reference spec for a mobile/Dart re-implementation. **It must stay platform-agnostic**: no DOM, no `WebSocket`, no `IndexedDB`. Transport (`ClientConnection`) and persistence (`TxPersistenceStore`) are injected. The browser/IndexedDB glue lives in `@hcengineering/client-resources`, not here.

## Public API

### Data primitives (`classes.ts`)

| Export | Kind | Notes |
|--------|------|-------|
| `Ref<T extends Doc>` | type | `string & { __ref: T }` — typed id of a doc/class. |
| `Obj` | interface | Base, carries `_class: Ref<Class<this>>`. |
| `Doc<S extends Space>` | interface | `_id`, `_class`, `space`, `modifiedOn/By`, optional `createdOn/By`. |
| `AttachedDoc<Parent, Collection, S>` | interface | Child doc in a collection: `attachedTo`, `attachedToClass`, `collection`. |
| `Space` | interface | Multitenancy container: `name`, `private`, `members: AccountUuid[]`, `archived`. |
| `Class<T extends Obj>` | interface | Schema metadata: `extends?`, `domain?`, `pluralLabel?`. |
| `Mixin<T extends Doc>` | type | Alias for `Class<T>`; adds attributes to a doc at runtime. |
| `Attribute<T>` / `AnyAttribute` | interface | Field metadata: `attributeOf`, `name`, `type`, `index?`. |
| `Domain` | type | Storage partition; constants `DOMAIN_MODEL`, `DOMAIN_TX`/`DOMAIN_MODEL_TX`, `DOMAIN_BLOB`, `DOMAIN_SPACE`, `DOMAIN_TRANSIENT`. |
| `Account` / `AccountRole` | interface / enum | Current user + role (`ReadOnlyGuest`…`Owner`/`Admin`, ordered by `roleOrder`). |
| `Blob` | interface | Provider blob descriptor (`provider`, `contentType`, `etag`, `size`). |
| `Data<T>` / `AttachedData<T>` / `DocData<T>` | type | `Omit<T, keyof Doc>` — attribute payload for create. |

### Transactions (`tx.ts`)

| Export | Kind | Notes |
|--------|------|-------|
| `Tx` | interface | A transaction; itself a `Doc`. Adds `objectSpace`, `meta?`. |
| `TxCUD<T>` | interface | Create/Update/Remove base: `objectId`, `objectClass`, optional `attachedTo`/`collection`. |
| `TxCreateDoc<T>` | interface | `attributes: Data<T>`. |
| `TxUpdateDoc<T>` | interface | Holds a `DocumentUpdate<T>` (set + `$push`/`$pull`/`$inc`). |
| `TxRemoveDoc<T>` | interface | Delete by id. |
| `TxMixin<D, M>` | interface | `mixin`, `attributes: MixinUpdate<D, M>`. |
| `TxApplyIf` | interface | Conditional/optimistic batch: `match`, `notMatch`, `txes`, `scope`. |
| `TxWorkspaceEvent<T>` | interface | Server→client event; `event: WorkspaceEvent` (`LastTx`, `BulkUpdate`, `MaintenanceNotification`, …). |
| `TxFactory` | class | `new TxFactory(user, isDerived?)` → `createTxCreateDoc`, `createTxUpdateDoc`, `createTxRemoveDoc`, `createTxMixin`, `createTxApplyIf`, `createTxCollectionCUD`. |
| `TxProcessor` | class | Applies txes to docs (`applyUpdate`, `isExtendsCUD`). |
| `DocumentUpdate<T>` | type | Update operations payload for `TxUpdateDoc`. |

### Hierarchy & model (`hierarchy.ts`, `memdb.ts`)

| Member | Signature (abridged) | Notes |
|--------|----------------------|-------|
| `Hierarchy.tx(tx)` | `(tx: Tx) => void` | Apply a model tx to update class/attr/mixin maps. |
| `Hierarchy.getClass(_class)` | `<T>(Ref<Class<T>>) => Class<T>` | Class metadata lookup. |
| `Hierarchy.getDomain(_class)` | `(Ref<Class<Obj>>) => Domain` | Resolve storage domain (`findDomain` for nullable). |
| `Hierarchy.isDerived(_class, from)` | `(Ref, Ref) => boolean` | Inheritance check. |
| `Hierarchy.isMixin(_class)` | `(Ref<Class<Doc>>) => boolean` | |
| `Hierarchy.as(doc, mixin)` / `hasMixin` | mixin proxy access | |
| `Hierarchy.getAllAttributes(clazz, to?)` | `=> Map<string, AnyAttribute>` | |
| `Hierarchy.getAncestors` / `getDescendants` | `=> Ref<Classifier>[]` | |
| `ModelDb extends MemDb` | class | In-memory store for `DOMAIN_MODEL` docs; supports `findAll`, `addTxes`. |

### Client & query (`client.ts`, `storage.ts`)

| Export | Kind | Notes |
|--------|------|-------|
| `Client` | interface | `findAll`, `findOne`, `tx`, `searchFulltext`, `getHierarchy`, `getModel`, `domainRequest`, `close`, optional `notify`. |
| `ClientConnection` | interface | Transport contract: `loadModel`, `findAll`, `tx`, `searchFulltext`, `pushHandler`, `isConnected`, `domainRequest`, `getLastHash?`, `onConnect?`. |
| `TxHandler` | type | `(...tx: Tx[]) => void` — sink for server-pushed txes. |
| `createClient(connect, modelFilter?, txPersistence?, ctx?)` | function | Builds a `Client`: connects, loads model, builds `Hierarchy`+`ModelDb`, wires live tx application. |
| `ClientConnectEvent` | enum | `Connected`, `Reconnected`, `Upgraded`, `Refresh`, `Maintenance`. |
| `TxPersistenceStore` | interface | `load()` / `store(model)` — injected model cache. |
| `DocumentQuery<T>` | type | Mongo-style query: `$in`, `$nin`, `$ne`, `$gt(e)`, `$lt(e)`, `$exists`, `$like`, `$regex`, `$all`, `$size`, `$search`. |
| `FindOptions<T>` | type | `limit`, `sort`, `lookup`, `projection`, `associations`, `total`, `showArchived`. |
| `FindResult<T>` | type | `WithLookup<T>[] & { total, lookupMap? }`. |
| `SortingOrder` | enum | `Ascending = 1`, `Descending = -1`. |

### Operations (`operations.ts`) — `TxOperations`

High-level CRUD that builds a `Tx` and sends it via `client.tx`. `implements Omit<Client, 'notify'>`.

| Method | Signature (abridged) | Returns |
|--------|----------------------|---------|
| `createDoc` | `(_class, space, attributes: Data<T>, id?)` | `Promise<Ref<T>>` |
| `updateDoc` | `(_class, space, objectId, operations: DocumentUpdate<T>, retrieve?)` | `Promise<TxResult>` |
| `removeDoc` | `(_class, space, objectId)` | `Promise<TxResult>` |
| `addCollection` | `(_class, space, attachedTo, attachedToClass, collection, attributes, id?)` | `Promise<Ref<P>>` |
| `updateCollection` / `removeCollection` | collection variants | `Promise<Ref<T>>` |
| `createMixin` / `updateMixin` | `(objectId, objectClass, objectSpace, mixin, attributes)` | `Promise<TxResult>` |
| `update(doc, update)` / `remove(doc)` | doc-instance convenience (auto-routes mixin/collection) | `Promise<TxResult>` |
| `apply(scope?, measure?, derived?)` | start an `ApplyOperations` batch (→ `TxApplyIf`) | `ApplyOperations` |

### Utilities (`utils.ts`)

| Export | Signature | Notes |
|--------|-----------|-------|
| `generateId<T>(join?)` | `(join?: string) => Ref<T>` | 24-hex-ish id: `timestamp + random + counter`. |
| `generateUuid()` | `() => string` | `crypto.randomUUID()`. |
| `getCurrentAccount()` / `setCurrentAccount(a)` | account singleton | |
| `toFindResult(docs, total?)` | wrap array as `FindResult` | |

## Usage

```typescript
import core, {
  type Client,
  type ClientConnection,
  createClient,
  TxOperations,
  generateId,
  getCurrentAccount,
  type Ref,
  type Doc,
  SortingOrder
} from '@hcengineering/core'

// `connect` is platform-provided: it returns a ClientConnection wired to a TxHandler.
declare function connect(txHandler: (...tx: any[]) => void): Promise<ClientConnection>

const client: Client = await createClient(connect)

// Reads — generic findAll over any Doc class.
const issues = await client.findAll(
  tracker.class.Issue as Ref<any>,
  { space: projectId, $search: undefined },
  { sort: { modifiedOn: SortingOrder.Descending }, limit: 50, total: true }
)

// Writes — wrap the client in TxOperations.
const ops = new TxOperations(client, getCurrentAccount().primarySocialId)
const id = await ops.createDoc(myPlugin.class.Thing, spaceId, { title: 'Hello' }, generateId())
await ops.updateDoc(myPlugin.class.Thing, spaceId, id, { title: 'Updated' })
```

## Cross-references

- [client-package](client-package.md) -- transport that satisfies `ClientConnection`.
- [query-package](query-package.md) -- `LiveQuery` reactive layer over `Client`.
- [platform-package](platform-package.md) -- `IntlString`/`Asset`/`Resource` used in class metadata.
- Concepts: [data-model](../concepts/data-model.md), [transaction-model](../concepts/transaction-model.md), [client-protocol](../concepts/client-protocol.md).
- Types: [core-types](../types/core-types.md), [tx-types](../types/tx-types.md).
- Flows: [model-load-flow](../flows/model-load-flow.md), [transaction-flow](../flows/transaction-flow.md).

## Gotchas

- **Platform-agnostic boundary.** `core` must never import DOM/`WebSocket`/`IndexedDB`. Model persistence and the socket live in `client-resources`. A Dart port re-implements the protocol; the TS package is the spec, not a dependency.
- **`createDoc` cannot create `AttachedDoc`.** Use `addCollection` for docs inherited from `AttachedDoc`; `createDoc` throws otherwise. It also throws for `DOMAIN_MODEL` classes with a non-`core.space.Model` space.
- **Model txes are split out.** In `ClientImpl.tx`, txes targeting `core.space.Model` are applied to `Hierarchy`+`ModelDb` locally before being sent; remote echoes are de-duplicated via an applied-tx set.
- **`Ref` is a branded string.** It is just a string at runtime; the `__ref` brand exists only for compile-time typing.
- **`findAll` on a `DOMAIN_MODEL` class** is served from the local `ModelDb`, not the connection — model data is fully in memory after load.
