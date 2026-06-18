# API Reference

> Condensed lookup for the platform's public APIs: the generic Client/Tx API (covers every feature), the account JSON-RPC API, the transactor RPC, and blob storage. For detail, follow the linked pages.

## Client API (the whole data layer)

`@hcengineering/core` — `Client` / `TxOperations`. This is *all* you need to read and write any feature.

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `findAll` | `_class, query, options?` | `FindResult<T>` | All reads. Mongo-style query. |
| `findOne` | `_class, query, options?` | `T \| undefined` | Single doc. |
| `tx` | `tx: Tx` | `TxResult` | All writes. Submit a transaction. |
| `searchFulltext` | `query, options` | `SearchResult` | Full-text search. |
| `loadModel` | `lastTx, hash?` | `Tx[]` | Load model → build Hierarchy. |
| `close` | — | `void` | Close connection. |

`TxOperations` (high-level CRUD helpers, build + send a `Tx`):

| Method | Parameters | Returns |
|--------|-----------|---------|
| `createDoc` | `_class, space, attrs, id?` | `Ref<T>` |
| `updateDoc` | `_class, space, id, ops` | `TxResult` |
| `removeDoc` | `_class, space, id` | `TxResult` |
| `addCollection` | `_class, space, attachedTo, attachedToClass, collection, attrs, id?` | `Ref<T>` |
| `updateCollection` / `removeCollection` | … | `TxResult` |
| `createMixin` / `updateMixin` | `objectId, _class, space, mixin, attrs` | `TxResult` |

See [services/core-package](services/core-package.md), [types/tx-types](types/tx-types.md), [transactor-rpc](api/transactor-rpc.md).

### Query operators (`storage.ts`)
`$in, $nin, $ne, $gt, $gte, $lt, $lte, $exists, $like, $regex, $all, $size, $search`.

### FindOptions
`limit, skip, sort, lookup` (populate refs), `total`, `projection`.

See [types/query-types](types/query-types.md).

## Account API (JSON-RPC over HTTP, :3000)

Body `{ method, params }` → `{ result?, error? }`. Auth: `Authorization: Bearer {token}`.

| Method | Params | Returns |
|--------|--------|---------|
| `login` | `{ email, password }` | `LoginInfo { account, token?, tfaRequired? }` |
| `loginOtp` / `validateOtp` | email + code | `LoginInfo` (passwordless) |
| `signUp` | `{ email, password, first, last }` | `LoginInfo` |
| `getUserWorkspaces` | (token) | `WorkspaceInfoWithStatus[]` |
| `selectWorkspace` | `{ workspaceUrl, kind }` | `WorkspaceLoginInfo { endpoint, token, … }` |
| `requestPasswordReset` / `changePassword` | … | … |
| `createInviteLink` / `join` | … | … |

See [account-api](api/account-api.md), [services/account](services/account.md).

## Transactor RPC (WebSocket, :3332)

Connect `ws://{endpoint}/{token}?sessionId={uuid}`. Framing:
```
Request  = { id?, method, params: any[], meta?, time? }
Response = { result?, id?, error?, terminate?, chunk?, rateLimit?, time? }
```
Methods: `loadModel`, `findAll`, `findOne`, `tx`, `searchFulltext`, `domainRequest`. Live broadcasts arrive as id-less `Response<Tx[]>`.

See [transactor-rpc](api/transactor-rpc.md), [concepts/client-protocol](concepts/client-protocol.md).

## Blob storage (datalake, :4030)

| Operation | Endpoint |
|-----------|----------|
| Download | `GET {DATALAKE_URL}/blob/{workspace}/{uuid}/{filename}` |
| Upload (form) | `POST {DATALAKE_URL}/upload/form-data/{workspace}` |
| Upload (multipart) | S3-style init → PUT parts → complete |

See [datalake-api](api/datalake-api.md), [concepts/storage-blobs](concepts/storage-blobs.md).

## Core types

| Type | Description |
|------|-------------|
| `Ref<T>` | Typed string id of a doc/class |
| `Doc` | Persisted object (`_id`, `_class`, `space`, `modifiedOn/By`) |
| `Space` | Multitenancy container; every doc belongs to a space |
| `AttachedDoc` | Child doc in a parent's collection |
| `Class<T>` / `Mixin<T>` | Schema metadata (from the model) |
| `Tx` | A transaction (itself a `Doc`) |
| `Resource` / `Plugin` / `IntlString` / `Asset` | Platform string-id references |

See [types/core-types](types/core-types.md), [types/platform-types](types/platform-types.md).

## Cross-references

- [overview](overview.md) — Full description
- [types/](types/) — Detailed type pages
- [services/](services/) — Detailed service pages
- [api/](api/) — Endpoint detail
