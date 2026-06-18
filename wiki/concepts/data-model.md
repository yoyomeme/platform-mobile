# Data Model — Doc, Class, Hierarchy, ModelDb

> The runtime type system of Huly: every record is a `Doc` of some `Class`; the schema itself is *data* (classes, mixins, attributes) loaded as transactions into a `Hierarchy`, with model objects held in a `ModelDb`.

## Where in code

- `foundations/core/packages/core/src/classes.ts` -- `Obj`, `Doc`, `AttachedDoc`, `Class`, `Mixin`, `Interface`, `Attribute`, `Ref`, `Domain`, `Space`, `Classifier`, `ClassifierKind`, `IndexKind`.
- `foundations/core/packages/core/src/hierarchy.ts` -- the `Hierarchy` class: class lookups, `isDerived`, mixin proxies, attribute resolution, domain resolution.
- `foundations/core/packages/core/src/memdb.ts` -- `MemDb`, `ModelDb`, `TxDb`: in-memory stores keyed by class/id, `findAll`/`findOne`.
- `foundations/core/packages/core/src/component.ts` -- the `core` plugin id object: `core.class.Doc`, `core.class.Class`, domains.
- `models/core/src/core.ts` -- the `@Model`/`@Prop` declarations that *generate* the core classes (`TObj`, `TDoc`, `TClass`, …).

## Purpose

Huly has **no fixed schema and no per-feature tables**. Instead, the "schema" is a set of documents: a `Class` is itself a `Doc`, an `Attribute` is a `Doc`, a `Mixin` is a `Doc`. Plugins contribute their classes by emitting transactions that create these schema documents. At startup the client loads that transaction stream and replays it to build a `Hierarchy` (the class graph + attributes) and a `ModelDb` (the model documents).

The payoff: one generic storage interface (`findAll`/`tx`) serves every feature. A mobile client that understands `Doc`, `Class`, `Hierarchy`, and `Tx` can read and write *any* feature's data without bespoke APIs.

## Details

### The object spine

```typescript
export type Ref<T extends Doc> = string & { __ref: T }   // typed id of a doc or class

export interface Obj { _class: Ref<Class<this>> }        // base: every object knows its class

export interface Doc<S extends Space = Space> extends Obj {
  _id: Ref<this>
  space: Ref<S>                  // multitenancy container — every doc belongs to a Space
  modifiedOn: Timestamp
  modifiedBy: PersonId
  createdBy?: PersonId           // filled by platform
  createdOn?: Timestamp          // filled by platform
}

export interface AttachedDoc<Parent extends Doc = Doc, Collection = ..., S extends Space = Space>
  extends Doc<S> {
  attachedTo: Ref<Parent>        // e.g. an Issue
  attachedToClass: Ref<Class<Parent>>
  collection: Collection         // named child collection, e.g. "comments"
}
```

`Data<T> = Omit<T, keyof Doc>` and `AttachedData<T> = Omit<T, keyof AttachedDoc>` are the "payload-only" shapes used when creating a doc (the platform fills `_id`, `space`, `modified*`).

### Classifiers: Class, Mixin, Interface

Schema metadata are `Classifier` docs distinguished by `ClassifierKind`:

```typescript
export enum ClassifierKind { CLASS, INTERFACE, MIXIN }

export interface Classifier extends Doc, UXObject { kind: ClassifierKind }

export interface Class<T extends Obj> extends Classifier {
  extends?: Ref<Class<Obj>>            // single inheritance
  implements?: Ref<Interface<Doc>>[]
  domain?: Domain                      // storage partition (inherited if absent)
  pluralLabel?: IntlString
}

export type Mixin<T extends Doc> = Class<T>   // a Mixin is structurally a Class
```

| Kind | Meaning | Storage |
|------|---------|---------|
| `CLASS` | A concrete document type with a `domain`. | Owns rows in its domain. |
| `INTERFACE` | A contract (`implements`), no storage. | None. |
| `MIXIN` | Extra attributes attached to an existing doc *at runtime*, stored as a nested object keyed by the mixin id. | Inline on the base doc. |

### Mixins: runtime attribute extension

A mixin does not create a new record — it stores its extra fields as a sub-object on the host doc, under a key equal to the mixin's class id:

```typescript
// a doc with the tracker IssueTypeData mixin applied looks like:
{ _id, _class: "tracker:class:Issue", title: "...",
  "tracker:mixin:IssueTypeData": { /* mixin-only fields */ } }
```

`Hierarchy.as(doc, mixin)` returns a `Proxy` that overlays the mixin's nested object onto the base doc so callers see one flat object. `Hierarchy.hasMixin(doc, mixin)` checks whether the nested key exists (`typeof doc[mixin] === 'object'`).

### The Hierarchy

`Hierarchy` is the in-memory class graph. It is fed `Tx`es (via `hierarchy.tx(tx)`) and maintains:

```typescript
class Hierarchy {
  private classifiers   : Map<Ref<Classifier>, Classifier>            // id → class/mixin/interface doc
  private attributes    : Map<Ref<Classifier>, Map<string, AnyAttribute>>  // class → its own attrs
  private attributesById : Map<Ref<AnyAttribute>, AnyAttribute>
  private descendants   : Map<Ref<Classifier>, Ref<Classifier>[]>     // class → all subclasses
  private ancestors     : Map<Ref<Classifier>, Ref<Classifier>[]>     // class → all superclasses
}
```

Key methods used everywhere in the codebase:

| Method | Returns | Use |
|--------|---------|-----|
| `getClass(_class)` | `Class<T>` | Resolve a class doc (throws if missing/interface). |
| `findClass(_class)` | `Class<T> \| undefined` | Non-throwing resolve. |
| `isDerived(_class, from)` | `boolean` | Is `_class` a subclass of `from`? (`ancestors.includes(from)`) |
| `isImplements(_class, iface)` | `boolean` | Does the class (or an ancestor) implement an interface? |
| `getAncestors(_class)` / `getDescendants(_class)` | `Ref<Classifier>[]` | Walk the class graph. |
| `getDomain(_class)` / `findDomain(_class)` | `Domain` | Resolve storage domain (inherited up the chain). |
| `getBaseClass(mixin)` | `Ref<Class<T>>` | First non-mixin/interface ancestor — the "real" stored class. |
| `getAllAttributes(class, to?)` | `Map<string, AnyAttribute>` | All attributes including inherited (optionally up to `to`). |
| `getOwnAttributes(class)` | `Map<string, AnyAttribute>` | Only attributes declared on this class. |
| `findAttribute(class, name)` | `AnyAttribute \| undefined` | Attribute lookup across ancestors + interfaces. |
| `as(doc, mixin)` / `asIf(doc, mixin)` | `M` / `M \| undefined` | View a doc through a mixin (proxy). |

`isDerived` is O(1) because `ancestors` is precomputed:

```typescript
isDerived<T extends Obj>(_class: Ref<Class<T>>, from: Ref<Class<T>>): boolean {
  return this.ancestors.get(_class)?.includes(from) ?? false
}
```

### How the model loads as transactions

`Hierarchy.tx` interprets only the four CUD transaction classes and only for classifier/attribute objects:

```typescript
tx (tx: Tx): void {
  switch (tx._class) {
    case core.class.TxCreateDoc: this.txCreateDoc(tx as TxCreateDoc<Doc>); return
    case core.class.TxUpdateDoc: this.txUpdateDoc(tx as TxUpdateDoc<Doc>); return
    case core.class.TxRemoveDoc: this.txRemoveDoc(tx as TxRemoveDoc<Doc>); return
    case core.class.TxMixin:     this.txMixin(tx as TxMixin<Doc, Doc>)
  }
}
```

A `TxCreateDoc` whose `objectClass` is `Class`/`Mixin`/`Interface` becomes a classifier (and triggers `updateAncestors`/`updateDescendant`); one whose `objectClass` is `Attribute` becomes an attribute on `attribute.attributeOf`:

```typescript
private txCreateDoc (tx: TxCreateDoc<Doc>): void {
  if (this.isClassifierTx(tx)) {
    const _id = tx.objectId as Ref<Classifier>
    this.classifiers.set(_id, TxProcessor.createDoc2Doc(tx as TxCreateDoc<Classifier>))
    this.updateAncestors(_id); this.updateDescendant(_id)
  } else if (tx.objectClass === core.class.Attribute) {
    this.addAttribute(TxProcessor.createDoc2Doc(tx as TxCreateDoc<AnyAttribute>))
  }
}
```

So the startup sequence is: `loadModel` → stream of `Tx[]` → for each, `hierarchy.tx(tx)` (builds the class graph) **and** `modelDb.addTxes(...)` (stores the model docs).

### ModelDb / MemDb — the in-memory store

`MemDb` (abstract) indexes docs two ways and implements the `Storage` query interface:

```typescript
abstract class MemDb extends TxProcessor implements Storage {
  private objectsByClass : Map<Ref<Class<Doc>>, Map<Ref<Doc>, Doc>>  // class → its docs
  private objectById     : Map<Ref<Doc>, Doc>

  addDoc (doc: Doc): void {
    this.hierarchy.getAncestors(doc._class).forEach((_class) =>
      this.getObjectsByClass(_class).set(doc._id, doc))   // indexed under every ancestor class
    this.objectById.set(doc._id, doc)
  }

  async findAll<T extends Doc>(_class, query, options?): Promise<FindResult<T>> { /* matchQuery + sort + lookup + clone */ }
}
```

Because a doc is indexed under **all** its ancestor classes, `findAll(core.class.Doc, {})` would match everything, while `findAll(tracker.class.Issue, {})` matches only issues. `findAll` runs `matchQuery` (Mongo-style operators), optional `$lookup` population, `sort`, `limit`, then `hierarchy.clone` (which re-applies mixin proxies to the result).

Concrete subclasses:

| Class | Holds | Notes |
|-------|-------|-------|
| `ModelDb` | model objects + classifiers (the `DOMAIN_MODEL`) | `addTxes(ctx, txes, clone)` replays a model transaction batch; applies create/update/remove/mixin. |
| `TxDb` | raw transactions | `tx()` just `addDoc`s the tx. |
| `Hierarchy` | classifiers + attributes (separate from ModelDb) | not a `MemDb`; purpose-built maps. |

### Domains — storage partitions

`Domain = string & { __domain: true }`. A class declares a `domain` (or inherits it); the domain selects the physical store. Core domains:

```typescript
DOMAIN_MODEL = 'model'   // classes, mixins, attributes, config — loaded into ModelDb on the client
DOMAIN_TX    = 'tx'      // the transaction log
DOMAIN_SPACE = 'space'
DOMAIN_BLOB  = 'blob'    // s3 blob metadata
DOMAIN_TRANSIENT = 'transient'   // memdb-only, not persisted
DOMAIN_RELATION  = 'relation'
DOMAIN_SEQUENCE  = 'sequence'
```

`findDomain` walks the `extends` chain (caching the result on the class) until it finds a domain, so subclasses don't have to repeat it — and `Builder` actually forbids re-declaring an inherited domain.

## Cross-references

- [transaction-model](transaction-model.md) — how `Tx`es create/update docs and how `TxProcessor` materializes them.
- [model-layer](model-layer.md) — the `@Model`/`@Prop` DSL that *emits* the classifier/attribute transactions consumed here.
- [plugin-architecture](plugin-architecture.md) — class/mixin ids are PRIs from `plugin()` id objects.
- [client-protocol](client-protocol.md) — `loadModel` / `findAll` over the transactor WebSocket.
- [core-types](../types/core-types.md) — full field reference for `Doc`, `Class`, `Space`, `Attribute`.

## Gotchas

- A doc is stored under **every** ancestor class in `objectsByClass`, so removing/adding must walk ancestors (`addDoc`/`delDoc` do this). Hand-rolling a store and indexing only by `_class` would break polymorphic `findAll`.
- `findAll` queries the **base class** (`getBaseClass(_class)`) then post-filters for the mixin key when `_class` is a mixin — querying a mixin returns only docs that actually have that mixin applied.
- Mixins are *not* rows. `findAll(mixinClass, …)` does not hit a separate table; it scans the base class and filters on the nested mixin object's presence.
- `getClass` **throws** for unknown classes and for interfaces; use `findClass`/`hasClass` when a class may be absent (e.g. a plugin disabled on this workspace).
- `ModelDb.findAll` clones results (`hierarchy.clone`) so callers can't mutate the store; `findAllSync` does **not** clone — treat its results as read-only.
- `createdBy`/`createdOn` are optional on the type but filled by the server; do not assume they are present on locally-constructed docs before a round-trip.
