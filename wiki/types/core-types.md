# Core data-model types

> The foundational document, class, space, and identity types that every persisted object in Huly is built from. Defined in `@hcengineering/core`.

## Where in code

- `foundations/core/packages/core/src/classes.ts` -- all types on this page (Obj, Doc, AttachedDoc, Class, Mixin, Ref, Space, TypedSpace, Account, PersonId, Domain, Timestamp, Markup, Blob, Arr, Collection, etc.)
- `models/core/src/core.ts` -- the model-side `TDoc`/`TClass`/`TSpace` classes that register these into the model
- `foundations/core/packages/core/src/storage.ts` -- `DocumentQuery`/`FindOptions` that consume these types

## Definition

```typescript
// Typed string id of a document. The `__ref` phantom field is brand-only
// (never present at runtime) and carries the target type for the compiler.
export type Ref<T extends Doc> = string & { __ref: T }

export type Timestamp = number
export type Markup = string        // rich-text / HTML markup string
export type Hyperlink = string
export type Rank = string          // LexoRank ordering key
export type MarkupBlobRef = Ref<Blob> // ref to a blob holding a collaborative doc snapshot
export type Arr<T extends PropertyType> = T[]
export type Domain = string & { __domain: true } // storage partition name

// Base of everything: only carries its class id.
export interface Obj {
  _class: Ref<Class<this>>
}

// A persisted object. Every doc belongs to a Space.
export interface Doc<S extends Space = Space> extends Obj {
  _id: Ref<this>
  space: Ref<S>
  modifiedOn: Timestamp
  modifiedBy: PersonId
  createdBy?: PersonId // filled by the platform
  createdOn?: Timestamp // filled by the platform
}

// A child doc living in a parent's collection (e.g. a comment on an issue).
export interface AttachedDoc<
  Parent extends Doc = Doc,
  Collection extends Extract<keyof Parent, string> | string = Extract<keyof Parent, string> | string,
  S extends Space = Space
> extends Doc<S> {
  attachedTo: Ref<Parent>
  attachedToClass: Ref<Class<Parent>>
  collection: Collection
}

// Schema metadata for a class (itself a Doc, stored in DOMAIN_MODEL).
export interface Class<T extends Obj> extends Classifier {
  extends?: Ref<Class<Obj>>
  implements?: Ref<Interface<Doc>>[]
  domain?: Domain
  shortLabel?: string
  sortingKey?: string
  filteringKey?: string
  pluralLabel?: IntlString
}

// A Mixin is structurally a Class<T> — it adds attributes to existing docs at runtime.
export type Mixin<T extends Doc> = Class<T>

export interface Classifier extends Doc, UXObject {
  kind: ClassifierKind // CLASS | INTERFACE | MIXIN
}
```

```typescript
// Multitenancy container — a project, channel, team, etc. Every Doc has a space.
export interface Space extends Doc {
  name: string
  description: string
  private: boolean
  members: AccountUuid[]
  archived: boolean
  owners?: AccountUuid[]
  autoJoin?: boolean
  autoJoinForRoles?: AccountRole[]
}

// Space whose roles/permissions are configured by a SpaceType.
export interface TypedSpace extends Space {
  type: Ref<SpaceType>
  restricted?: boolean // if true, user must have permission for any tx
}
```

```typescript
// Identity. Accounts and persons use branded UUID/id strings.
export type PersonUuid = string & { __personUuid: true }
export type AccountUuid = PersonUuid & { __accountUuid: true } // same UUID, but an account exists
export type PersonId = string & { __personId: true }           // a social id; the actor on every tx/doc

export interface Account {
  uuid: AccountUuid
  role: AccountRole
  primarySocialId: PersonId
  socialIds: PersonId[]
  fullSocialIds: SocialId[]
}

export enum AccountRole {
  ReadOnlyGuest = 'READONLYGUEST',
  DocGuest = 'DocGuest',
  Guest = 'GUEST',
  User = 'USER',
  Maintainer = 'MAINTAINER',
  Owner = 'OWNER',
  Admin = 'ADMIN'
}
```

```typescript
// A blob document describing stored binary content (managed via the storage client).
export interface Blob extends Doc {
  provider: string        // storage provider id
  contentType: string
  etag: string
  version: string | null  // provider doc version, if supported
  size: number
}

// Collection<T> is the attribute TYPE that marks a field as a collection of AttachedDocs.
// The runtime value of such a field is a count (CollectionSize<T> = T[]['length']).
export interface Collection<T extends AttachedDoc> extends Type<CollectionSize<T>> {
  of: Ref<Class<T>>
  itemLabel?: IntlString
}
```

## Fields / Cases

### `Doc`

| Field | Type | Description |
|-------|------|-------------|
| `_id` | `Ref<this>` | Unique id of this document. |
| `_class` | `Ref<Class<this>>` | Class id (inherited from `Obj`). |
| `space` | `Ref<S>` | Owning space; drives multitenancy and access. |
| `modifiedOn` | `Timestamp` | Last-modified epoch ms. |
| `modifiedBy` | `PersonId` | Social id of the last modifier. |
| `createdBy?` | `PersonId` | Creator social id (platform-filled). |
| `createdOn?` | `Timestamp` | Creation epoch ms (platform-filled). |

### `AttachedDoc` (extends `Doc`)

| Field | Type | Description |
|-------|------|-------------|
| `attachedTo` | `Ref<Parent>` | Parent document id. |
| `attachedToClass` | `Ref<Class<Parent>>` | Parent class id. |
| `collection` | `Collection` | Name of the parent field this child lives under. |

### `Space`

| Field | Type | Description |
|-------|------|-------------|
| `name` / `description` | `string` | Display info. |
| `private` | `boolean` | If true, only members may see it. |
| `members` | `AccountUuid[]` | Accounts with access. |
| `archived` | `boolean` | Soft-archive flag. |
| `owners?` | `AccountUuid[]` | Space owners. |
| `autoJoin?` | `boolean` | Auto-add new users. |

### `Class<T>`

| Field | Type | Description |
|-------|------|-------------|
| `extends?` | `Ref<Class<Obj>>` | Superclass. |
| `implements?` | `Ref<Interface<Doc>>[]` | Implemented interfaces. |
| `domain?` | `Domain` | Storage partition for instances. |
| `kind` | `ClassifierKind` | `CLASS` / `INTERFACE` / `MIXIN` (from `Classifier`). |

### Standard domains (constants)

| Constant | Value | Use |
|----------|-------|-----|
| `DOMAIN_MODEL` | `'model'` | Class/Mixin/Attribute metadata. |
| `DOMAIN_TX` | `'tx'` | Transactions (see [tx-types](tx-types.md)). |
| `DOMAIN_BLOB` | `'blob'` | S3/blob data. |
| `DOMAIN_SPACE` | `'space'` | Spaces. |
| `DOMAIN_TRANSIENT` | `'transient'` | Non-persisted live objects. |
| `DOMAIN_SEQUENCE` | `'sequence'` | Numeric sequences. |

## Usage

```typescript
import core, { type Ref, type Doc, type Space, SortingOrder } from '@hcengineering/core'

// A Ref is just a string at runtime, but typed at compile time:
const spaceId: Ref<Space> = 'my-space' as Ref<Space>

// findAll is typed by class; results are Doc subtypes in that space.
const spaces = await client.findAll(core.class.Space, { archived: false })
```

```typescript
// Helper types derived from Doc:
type Data<T extends Doc>        // = Omit<T, keyof Doc> — the attributes you pass to createDoc
type AttachedData<T extends AttachedDoc> // = Omit<T, keyof AttachedDoc>
type DocData<T extends Doc>     // picks the right one for plain vs attached docs
```

## Related types

- Transactions that create/mutate these docs: [tx-types](tx-types.md) (`TxCreateDoc`, `TxUpdateDoc`, ...).
- Querying these docs: [query-types](query-types.md) (`DocumentQuery`, `FindOptions`, `Lookup`).
- Branded id helpers (`Ref`, `Asset`, `IntlString`, `Resource`): [platform-types](platform-types.md).

## Cross-references

- [data-model concept](../concepts/data-model.md)
- [model-layer concept](../concepts/model-layer.md)
- [workspace-multitenancy concept](../concepts/workspace-multitenancy.md)
- [core-package service](../services/core-package.md)

## Gotchas

- `Ref<T>` and all `__*`-branded ids are **plain strings at runtime**. The brand field (`__ref`, `__personId`, `__domain`, ...) exists only for the type checker; never read it. Cast with `as Ref<T>` to construct one.
- `Mixin<T>` is the *same shape* as `Class<T>`. A mixin does not create a new document; it stores extra attributes on an existing doc under a key equal to the mixin's class id. See `updateMixin4Doc` in `tx.ts`.
- Every `Doc` MUST have a `space`. Even model objects and transactions have one (txes live in `core.space.Tx` / `core.space.DerivedTx`).
- `createdBy`/`createdOn` are optional in the type but are filled by the platform on create — treat them as present when reading.
- `Collection<T>` is an attribute *type descriptor*, not a runtime array. The field's runtime value is the item count; the items themselves are separate `AttachedDoc`s queried by `attachedTo`.
- `AccountUuid` is a subtype of `PersonUuid` (intersection brand). `PersonId` (a social id) is what appears on `modifiedBy`/`createdBy`, NOT the account uuid.
