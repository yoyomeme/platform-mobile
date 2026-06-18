# Model Layer — the build-time DSL

> `@hcengineering/model` is a decorator DSL (`@Model`, `@Prop`, `@Mixin`, `@Index`, `@UX`) plus a `Builder` that turns plain TypeScript classes into the stream of `TxCreateDoc` transactions that *define* Huly's schema, and a `migration` framework that evolves stored data.

## Where in code

- `foundations/core/packages/model/src/dsl.ts` -- `@Model`, `@Prop`, `@Mixin`, `@Implements`, `@Index`, `@UX`, `@Hidden`, `@ReadOnly`; the `Builder` class; `Type*` helpers (`TypeString`, `TypeRef`, `Collection`, `ArrOf`, …).
- `foundations/core/packages/model/src/migration.ts` -- `MigrationClient`, `MigrateOperation`, `tryMigrate`, `tryUpgrade`, `createDefaultSpace`, `migrateSpace`.
- `foundations/core/packages/model/src/index.ts` -- package re-exports.
- `models/core/src/core.ts` -- canonical `@Model`/`@Prop` declarations (`TObj`, `TDoc`, `TClass`, …).
- `models/core/src/index.ts` -- `createModel(builder)` registering the core classes + domain index config.
- `models/tracker/src/types.ts` -- feature example: `@Model(tracker.class.Issue, task.class.Task)` etc.

## Purpose

Schema in Huly is *data* — `Class`/`Attribute`/`Mixin` documents created by transactions ([data-model](data-model.md)). Authoring those transactions by hand would be verbose and error-prone. The model DSL lets developers write ordinary annotated classes; decorators record metadata, and `Builder.createModel(...)` compiles each class into the exact `TxCreateDoc<Class>` + `TxCreateDoc<Attribute>` transactions, topologically sorted so parents are created before children. The resulting tx array is the model the client loads at startup.

## Details

### Decorators

Decorators don't run logic at class definition — they stash metadata in module-level `Map`s keyed by the class prototype, to be read later by `Builder`.

| Decorator | Applies to | Records |
|-----------|-----------|---------|
| `@Model(_class, _extends, domain?, _implements?)` | class | Marks the class as `ClassifierKind.CLASS` with its id, parent, domain, interfaces. |
| `@Mixin(_class, _extends)` | class | Marks it `ClassifierKind.MIXIN`. |
| `@Implements(_iface, _extends?)` | class | Marks it `ClassifierKind.INTERFACE`. |
| `@Prop(type, label, extra?)` | field | Emits a `TxCreateDoc<Attribute>` describing the field (its `Type`, label, index, custom `_id`). |
| `@Index(kind)` | field | Sets `IndexKind` (`FullText`, `Indexed`, `IndexedDsc`) on the attribute. |
| `@UX(label, icon?, shortLabel?, …, pluralLabel?)` | class | UI labels/icon on the class doc. |
| `@Hidden()` / `@ReadOnly()` | field | Flags on the attribute. |

```typescript
// models/core/src/core.ts
@Model(core.class.Doc, core.class.Obj)
@UX(core.string.Object)
export class TDoc extends TObj implements Doc {
  @Prop(TypeRef(core.class.Doc), core.string.Id)
  @Hidden()
    _id!: Ref<this>

  @Prop(TypeRef(core.class.Space), core.string.Space)
  @Index(IndexKind.Indexed)
  @Hidden()
    space!: Ref<Space>

  @Prop(TypeTimestamp(), core.string.ModifiedDate)
  @Index(IndexKind.Indexed)
    modifiedOn!: Timestamp
}
```

```typescript
// models/tracker/src/types.ts  — a feature class extending another plugin's class
@Model(tracker.class.Issue, task.class.Task)
@UX(tracker.string.Issue, tracker.icon.Issue, 'TSK', 'title', undefined, tracker.string.Issues)
export class TIssue extends TTask implements Issue {
  @Prop(TypeString(), tracker.string.Title)
  @Index(IndexKind.FullText)
    title!: string

  @Prop(TypeRef(tracker.class.IssueStatus), tracker.string.Status,
        { _id: tracker.attribute.IssueStatus })
  @Index(IndexKind.Indexed)
  declare status: Ref<IssueStatus>

  @Prop(Collection(tracker.class.Issue), tracker.string.SubIssues)
    subIssues!: number
}
```

Convention: model implementation classes are prefixed `T` (`TDoc`, `TIssue`); they `implements` the public interface declared in the `<name>` plugin package, and reference ids via the plugin id object (`tracker.class.Issue`).

### `@Prop` mechanics

`@Prop` builds a `TxCreateDoc<Attribute>` immediately and pushes it onto the class's `ClassTxes.txes`. The attribute's `objectId` defaults to the field name (overridable via `extra._id`), and `attributeOf` is back-patched to the owning class id when the class is generated:

```typescript
export function Prop (type: Type<PropertyType>, label: IntlString, extra = {}) {
  return function (target: any, propertyKey: string): void {
    const txes = getTxes(target)
    txes.txes.push({
      _id: generateId(), _class: core.class.TxCreateDoc, objectClass: core.class.Attribute,
      objectId: extra._id ?? (propertyKey as Ref<Attribute<PropertyType>>),
      attributes: { ...extra, name: propertyKey, index: getIndex(target, propertyKey),
                    type, label, attributeOf: txes._id /* fixed later */ }
    })
  }
}
```

`Type` helpers (`TypeString()`, `TypeRef(_class)`, `TypeNumber(min,max)`, `Collection(class)`, `ArrOf(type)`, `TypeRef`, `TypeCollaborativeDoc()`, `TypeRank()`, `TypeEnum(of)`, `TypeAny(presenter, …)`, …) return the `Type<T>` object stored on the attribute, each carrying its own `_class`, label, and icon.

### The Builder

`Builder` accumulates generated `Tx[]` and maintains a live `Hierarchy` it feeds as it goes:

```typescript
export class Builder {
  private readonly txes: Tx[] = []
  readonly hierarchy = new Hierarchy()
  onTx?: (tx: Tx) => void

  createModel (...classes: Array<new () => Obj>): void {
    const txes = classes.map((ctor) => getTxes(ctor.prototype))
    // 1. validate: a class may not redeclare a domain its ancestor already set
    // 2. toposort by `extends` so parents are emitted first
    const generated = this.generateTransactions(txes, byId)
    for (const tx of generated) {
      this.txes.push(tx); this.onTx?.(tx); this.hierarchy.tx(tx)
    }
  }

  createDoc<T>(_class, space, attributes, objectId?, modifiedBy?): T  // seed instance docs
  mixin<D,M>(objectId, objectClass, mixin, attributes): void          // apply a mixin in the model
  getTxes (): Tx[]
}
```

`_generateTx(classTxes)` emits one `TxCreateDoc<Class|Mixin|Interface>` for the classifier (mapping `ClassifierKind` → `core.class.Class/Mixin/Interface`) followed by all its attribute create-txes with `attributeOf` patched and ids namespaced as `${classId}_${attrId}`. Topological sort uses `toposort` over the `extends` edges and is **reversed** so base classes come first.

### How `createModel` registers a plugin's schema

Each model package exports `createModel(builder)`; the build harness calls them all against one shared `Builder`. The package lists every `T`-class plus any seed docs / mixin configs:

```typescript
// models/core/src/index.ts
export function createModel (builder: Builder): void {
  builder.createModel(
    TObj, TDoc, TClass, TMixin, TInterface,
    TTx, TTxCUD, TTxCreateDoc, TTxUpdateDoc, TTxRemoveDoc, TTxMixin, TTxApplyIf,
    TSpace, TAttribute, TType, TStatus, /* … */
  )
  // seed config docs go through builder.createDoc / builder.mixin:
  builder.createDoc(core.class.DomainIndexConfiguration, core.space.Model, {
    domain: DOMAIN_TX, disabled: [{ _class: 1 }], indexes: [{ keys: { objectSpace: 1 } }]
  })
  builder.mixin(core.class.MigrationState, core.class.Class, core.mixin.IndexConfiguration,
    { indexes: [], searchDisabled: true })
}
```

`builder.createDoc` and `builder.mixin` are how non-class model data (index configs, space types, permissions, default statuses) get baked into the same tx stream.

### Migrations

The model only *defines* schema; evolving already-stored data is the migration framework's job. A plugin exposes a `MigrateOperation`:

```typescript
export interface MigrateOperation {
  preMigrate?: (client: MigrationClient, logger, mode) => Promise<void>  // raw, pre-model-update
  migrate:     (client: MigrationClient, mode) => Promise<void>          // raw domain ops
  upgrade:     (state, client: () => Promise<MigrationUpgradeClient>, mode) => Promise<void> // high-level
}
```

`MigrationClient` is a **raw, per-domain** API (bypassing the model/Tx layer) for bulk edits: `find`, `update`, `bulk`, `traverse` (cursor), `move`, `create`, `delete`, plus `hierarchy`, `model`, `storageAdapter`. `MigrationUpgradeClient` is a normal `Client`, so `upgrade` steps use `TxOperations`.

Each migration is a named state run once; `tryMigrate`/`tryUpgrade` skip already-applied states (tracked as `MigrationState` docs in `DOMAIN_MIGRATION`) and respect a `mode` of `'create' | 'upgrade'`:

```typescript
export async function tryMigrate (mode, client, plugin, migrations: Migrations[]): Promise<void> {
  const states = client.migrateState.get(plugin) ?? new Set()
  for (const migration of migrations) {
    if (states.has(migration.state)) continue
    if (migration.mode != null && migration.mode !== mode) continue
    await migration.func(client, mode)
    await client.create(DOMAIN_MIGRATION, { plugin, state: migration.state, /* MigrationState */ })
  }
}
```

Helpers: `createDefaultSpace` (idempotently ensure a system space exists), `migrateSpace` (move docs + their txes between spaces), `migrateSpaceRanks` (re-rank with lexorank).

### Build-to-runtime flow

```
@Model / @Prop / @Index / @UX        (compile-time metadata in module Maps)
        │  createModel(builder) per plugin
        ▼
Builder.createModel(...)             toposort by extends → _generateTx per class
        │  emits TxCreateDoc<Class> + TxCreateDoc<Attribute>[] + builder.createDoc/mixin docs
        ▼
builder.getTxes(): Tx[]              the serialized model (DOMAIN_MODEL transactions)
        │  shipped to / loaded by the client via loadModel
        ▼
Hierarchy + ModelDb                  (runtime class graph + model store — see data-model)
        ║  separately, on workspace create/upgrade:
        ╚═► MigrateOperation.migrate/upgrade  evolve stored data via MigrationClient / TxOperations
```

## Cross-references

- [data-model](data-model.md) — the `Class`/`Attribute`/`Mixin`/`Hierarchy` runtime these txes build.
- [transaction-model](transaction-model.md) — the `TxCreateDoc`/`TxMixin` the DSL emits; `TxFactory` used by `Builder`.
- [plugin-architecture](plugin-architecture.md) — `mergeIds`/`plugin()` ids referenced by `@Model`/`@Prop`.
- [localization](localization.md) — `@Prop` labels and `@UX` labels are `IntlString`s.
- [core-package](../services/core-package.md) / [platform-package](../services/platform-package.md) — package overviews.

## Gotchas

- Decorators run as a **side effect of importing** the model file. A `T`-class that is never imported into a `createModel(...)` list contributes nothing — its schema simply won't exist.
- `Builder` forbids a class declaring its own `domain` if an ancestor already has one (it throws during `createModel`); domain is inherited, declared once on the base class.
- Attribute ids are `${classId}_${fieldName}` unless you pass `extra._id`. Use a stable custom `_id` (e.g. `tracker.attribute.IssueStatus`) when other code must reference the attribute directly.
- `createModel` order within a single `createModel(...)` call doesn't matter (it toposorts by `extends`), but a child class's parent must be registered *somewhere* in the overall build, or hierarchy construction will fail.
- Migrations run with a **raw** `MigrationClient` that does not go through the Tx/trigger pipeline — derived data and triggers are bypassed. Use `upgrade` (Tx-based) when you need triggers to fire.
- A migration `state` name is permanent: once recorded in `DOMAIN_MIGRATION` it never re-runs. Renaming a state re-runs it; reusing a name silently skips.
