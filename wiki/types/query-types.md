# Query types

> The shape of `findAll` queries and options: `DocumentQuery<T>`, the query operators, `FindOptions`, `FindResult`, `Lookup`, projection, and sorting. Defined in `@hcengineering/core`.

## Where in code

- `foundations/core/packages/core/src/storage.ts` -- `DocumentQuery`, `QuerySelector`, `FindOptions`, `FindResult`, `Lookup`, `Projection`, `SortingOrder`, `SortingQuery`, the `Storage.findAll` signature
- `foundations/core/packages/query/src/` -- the live-query engine that consumes these (see [query-package service](../services/query-package.md))

## Definition

```typescript
// Per-field selectors. Most operators are constrained by the field type.
export type QuerySelector<T> = {
  $in?: T[]
  $all?: T extends Array<any> ? T : never
  $nin?: T[]
  $ne?: T
  $gt?: T extends number ? number : never
  $gte?: T extends number ? number : never
  $lt?: T extends number ? number : never
  $lte?: T extends number ? number : never
  $exists?: boolean
  $like?: string
  $regex?: string
  $options?: string                 // regex options (e.g. 'i')
  $size?: T extends Array<any> ? number | ArraySizeSelector : never
}

export type ArraySizeSelector =
  | { $gt: number } | { $lt: number } | { $gte: number } | { $lte: number }

// A field value may be the value itself, an array element shorthand, or a selector.
export type ObjQueryType<T> =
  (T extends Array<infer U> ? U | U[] | QuerySelector<U> : T) | QuerySelector<T>

// The query for a class T. Adds $search and allows nested dotted keys.
export type DocumentQuery<T extends Doc> = {
  [P in keyof T]?: ObjQueryType<T[P]>
} & {
  $search?: string
  [key: string]: any // nested queries e.g. 'user.friends.name'
}
```

```typescript
export type FindOptions<T extends Doc> = {
  limit?: number
  sort?: SortingQuery<T>
  lookup?: Lookup<T>
  projection?: Projection<T>
  associations?: AssociationQuery[]
  total?: boolean        // if set, FindResult.total is computed
  showArchived?: boolean
}

export enum SortingOrder {
  Ascending = 1,
  Descending = -1
}

export type SortingQuery<T extends Doc> = {
  [P in keyof T]?: SortingOrder | SortingRules<T[P]>
} & Record<string, SortingOrder | SortingRules<any>>

// 0 = exclude, 1 = include. Mutually-exclusive include/exclude per Mongo rules.
export type Projection<T extends Doc> = {
  [P in keyof T]?: 0 | 1
}
```

```typescript
// Lookup populates ref fields with the referenced documents.
// Forward: map a ref field to the target class.
// Reverse: under _id, pull docs that reference this one.
export type Lookup<T extends Doc> = Refs<T> | ReverseLookups | (Refs<T> & ReverseLookups)

export interface ReverseLookups {
  _id?: ReverseLookup
}
export type ReverseLookup = Record<string, Ref<Class<AttachedDoc>> | [Ref<Class<Doc>>, string]>

// Result rows carry resolved lookups on $lookup.
export type WithLookup<T extends Doc> = T & {
  $lookup?: LookupData<T>
  $associations?: Record<string, WithLookup<Doc>[]>
  $source?: { $score: number, [key: string]: any } // fulltext score
}

// findAll returns an array WITH a total field tacked on.
export type FindResult<T extends Doc> = WithLookup<T>[] & {
  total: number
  lookupMap?: Record<string, Doc>
}
```

```typescript
// The storage contract every client/server implements.
export interface Storage {
  findAll: <T extends Doc>(
    _class: Ref<Class<T>>,
    query: DocumentQuery<T>,
    options?: FindOptions<T>
  ) => Promise<FindResult<T>>

  tx: (tx: Tx) => Promise<TxResult>
}
```

## Fields / Cases

### Query operators (`QuerySelector`)

| Operator | Applies to | Meaning |
|----------|-----------|---------|
| `$in` | any | Value is in the given array. |
| `$nin` | any | Value is NOT in the array. |
| `$ne` | any | Not equal. |
| `$gt` / `$gte` | number | Greater (or equal) than. |
| `$lt` / `$lte` | number | Less (or equal) than. |
| `$exists` | any | Field present (`true`) / absent (`false`). |
| `$like` | string | SQL-style LIKE pattern. |
| `$regex` (+ `$options`) | string | Regex match; `$options: 'i'` for case-insensitive. |
| `$all` | array | Array contains all listed elements. |
| `$size` | array | Array length equals N, or `ArraySizeSelector` (`$gt`/`$lt`/...). |
| `$search` | top-level | Full-text search across the query (not a field selector). |

### `FindOptions`

| Field | Type | Description |
|-------|------|-------------|
| `limit?` | `number` | Max rows. |
| `sort?` | `SortingQuery<T>` | Field → `SortingOrder` (or `SortingRules`). |
| `lookup?` | `Lookup<T>` | Populate ref fields / reverse collections. |
| `projection?` | `Projection<T>` | Per-field `0`/`1` include-exclude. |
| `associations?` | `AssociationQuery[]` | Follow relation graph edges. |
| `total?` | `boolean` | Compute `FindResult.total`. |
| `showArchived?` | `boolean` | Include archived-space docs. |

## Usage

```typescript
import core, { SortingOrder } from '@hcengineering/core'

// Operators in a query:
const recent = await client.findAll(
  tracker.class.Issue,
  {
    space: spaceId,
    priority: { $in: [Priority.High, Priority.Urgent] },
    modifiedOn: { $gt: Date.now() - 86_400_000 },
    title: { $like: '%bug%' }
  },
  {
    limit: 50,
    total: true,
    sort: { modifiedOn: SortingOrder.Descending },
    projection: { title: 1, priority: 1, modifiedOn: 1 }
  }
)
console.log(recent.total) // total available, independent of limit

// Forward lookup: resolve the assignee ref into the actual Person doc.
const withAssignee = await client.findAll(
  tracker.class.Issue,
  { space: spaceId },
  { lookup: { assignee: contact.class.Person } }
)
const person = withAssignee[0].$lookup?.assignee

// Reverse lookup: pull all comments attached to each issue.
const withComments = await client.findAll(
  tracker.class.Issue,
  { space: spaceId },
  { lookup: { _id: { comments: chunter.class.ChatMessage } } }
)
```

## Related types

- The docs being queried: [core-types](core-types.md) (`Doc`, `Ref`, `Class`).
- Queries also appear inside transactions: [tx-types](tx-types.md) (`TxApplyIf.match`, `DocumentClassQuery`).

## Cross-references

- [client-protocol concept](../concepts/client-protocol.md)
- [live-queries concept](../concepts/live-queries.md)
- [fulltext-search concept](../concepts/fulltext-search.md)
- [query-package service](../services/query-package.md)
- [core-package service](../services/core-package.md)

## Gotchas

- `FindResult<T>` IS an array (`WithLookup<T>[]`) — you iterate it directly. `total` and `lookupMap` are extra properties stuck on the array, and `total` is only populated when `options.total === true`. Without it, `total` may be `0` or stale.
- Operator typing is enforced: `$gt`/`$lt` resolve to `never` on non-number fields, `$all`/`$size` to `never` on non-array fields — so misusing them is a compile error.
- `DocumentQuery` has an index signature (`[key: string]: any`), so dotted nested keys (`'attachedTo.title'`) and unknown keys type-check as `any`. This is intentional but removes type safety for those keys — spell them carefully.
- Lookup results land on `$lookup`, not on the field itself. The field still holds the raw `Ref`; the resolved doc is at `row.$lookup?.<field>`.
- `showArchived` defaults are computed (`shouldShowArchived`): querying by a literal `_id` or `space` string implicitly includes archived docs even when you don't pass `showArchived`.
- `Projection` follows Mongo's include/exclude exclusivity — don't mix `1`s and `0`s for non-`_id` fields in the same projection.
