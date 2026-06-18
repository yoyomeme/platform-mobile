# Workspaces & Multitenancy

> How Huly isolates tenants: a **workspace** is a self-contained dataset served by one transactor; every `Doc` lives in a `Space`; data is partitioned by `Domain`; and access is governed by account membership and `AccountRole`.

## Where in code

- `foundations/core/packages/core/src/classes.ts` -- `Doc`, `Space`, `TypedSpace`, `SpaceType`, `Role`, `Permission`, `Account`, `AccountRole`, and the `DOMAIN_*` constants.
- `foundations/core/packages/core/src/storage.ts` -- `DocumentQuery`/`FindOptions` and `shouldShowArchived` (the space/archived gating on reads).
- `MOBILE_APP_ARCHITECTURE.md` §1.2 (login & workspace selection) and §1.4 (data-model primitives).
- `ARCHITECTURE_OVERVIEW.md` -- transactor/account/workspace service topology and the auth flow.

## Purpose

Huly is multi-tenant at the **workspace** level: each workspace is an isolated graph of documents and transactions. Within a workspace, the **space** is the next isolation boundary — a project, channel, team, or teamspace — and **every document belongs to exactly one space**. This two-level model (workspace → space → doc) is how the platform keeps one user's tracker board separate from another's, and how the same transactor process can serve many tenants while a client only ever sees the workspaces it has been granted.

## Details

### Workspace → transactor resolution

A client never hardcodes a transactor URL. The account service (`:3000`) owns the mapping:

```
login(email, password)            -> token (account-scoped JWT)
getUserWorkspaces(token)          -> WorkspaceInfoWithStatus[]
selectWorkspace(workspaceUrl,kind)-> WorkspaceLoginInfo { token, endpoint, role, workspace }
```

The account service holds a list of transactors (`TRANSACTOR_URL`), **deterministically hashes the workspace UUID** to pick one, and returns it as `endpoint`. The client connects to whatever `endpoint` it is handed — region/load sharding is entirely server-side. `kind: 'internal' | 'external' | 'byregion'` chooses the internal-network vs public URL.

```
              ┌──────────── account (:3000) ────────────┐
 login ─────► │ JWT + getUserWorkspaces                  │
 select ws ─► │ hash(workspaceUuid) -> transactor URL    │
              └───────────────┬──────────────────────────┘
                              │ WorkspaceLoginInfo{ endpoint, token, role }
                              ▼
                ws://{endpoint}/{token}?sessionId=...   (one socket per workspace)
                              ▼
                    transactor (:3332) — serves THIS workspace's Doc/Tx graph
```

The returned `token` is **scoped to that workspace** and carries the user's `role`. See [client-protocol](client-protocol.md) for what happens on that socket.

### Every Doc belongs to a Space

```typescript
interface Doc<S extends Space = Space> extends Obj {
  _id: Ref<this>
  space: Ref<S>          // ← mandatory: the owning space
  modifiedOn: Timestamp
  modifiedBy: PersonId
  createdBy?: PersonId
  createdOn?: Timestamp
}

interface Space extends Doc {
  name: string
  description: string
  private: boolean
  members: AccountUuid[]      // who can see/use this space
  archived: boolean
  owners?: AccountUuid[]
  autoJoin?: boolean
  autoJoinForRoles?: AccountRole[]
}
```

The `space` field is the per-document tenancy tag *inside* a workspace. The transactor uses space membership to decide which documents a session may read and which transactions it may apply. A query that does not constrain `space` returns only documents in spaces the account is a member of.

### Space subtypes

| Type | Adds | Use |
|------|------|-----|
| `Space` | base members/owners/private/archived | generic container |
| `SystemSpace` | (marker) | platform-owned spaces |
| `TypedSpace` | `type: Ref<SpaceType>`, `restricted?` | spaces governed by a configurable type (roles/permissions) |

`SpaceType` + `SpaceTypeDescriptor` + `Role` + `Permission` form the configurable RBAC layer:

```typescript
interface SpaceType extends Doc {
  descriptor: Ref<SpaceTypeDescriptor>
  targetClass: Ref<Class<Space>>   // dynamic mixin holding role assignments
  roles: CollectionSize<Role>
  members?: AccountUuid[]
  autoJoin?: boolean
}

interface Role extends AttachedDoc<SpaceType, 'roles'> {
  name: string
  permissions: Ref<Permission>[]
}

interface Permission extends Doc {
  txClass?: Ref<Class<Tx>>
  objectClass?: Ref<Class<Doc>>
  scope?: 'space' | 'workspace'
  forbid?: boolean
  txMatch?: DocumentQuery<Tx>
}
```

`RolesAssignment = Record<Ref<Role>, AccountUuid[] | undefined>` maps role → members, stored on the space's `targetClass` mixin. A `restricted` `TypedSpace` requires an explicit permission for any transaction.

### Domains — storage partitions

A `Domain` (`type Domain = string & { __domain: true }`) groups documents by storage backend/table within a workspace. A class declares its domain; reads/writes for that class route to the corresponding partition.

| Constant | Value | Holds |
|----------|-------|-------|
| `DOMAIN_MODEL` | `model` | The model (classes, attributes, mixins). In-memory, loaded via `loadModel`; never live-cached. |
| `DOMAIN_MODEL_TX` | `model_tx` | Transactions that build the model. |
| `DOMAIN_TRANSIENT` | `transient` | Ephemeral, not persisted (presence, typing…). |
| `DOMAIN_SPACE` | `space` | `Space` documents. |
| `DOMAIN_BLOB` | `blob` | S3/datalake blob references. |
| `DOMAIN_RELATION` | `relation` | `Relation` edges between docs. |
| `DOMAIN_COLLABORATOR` | `collaborator` | Collaborative-doc state. |
| `DOMAIN_SEQUENCE` | `sequence` | Counters (e.g. issue numbers). |
| `DOMAIN_CONFIGURATION` | `_configuration` | Config docs. |
| `DOMAIN_MIGRATION` | `_migrations` | Migration bookkeeping. |

Feature plugins define their own domains (e.g. tracker issues, chunter messages) for storage locality. From a client's perspective the domain is mostly transparent — `findAll(_class, …)` resolves the domain via the `Hierarchy` — but `DOMAIN_MODEL` is special: those classes are read from the in-memory model, not via live queries.

### Accounts, membership & roles

```typescript
interface Account {
  uuid: AccountUuid
  role: AccountRole          // workspace-level role for this session
  primarySocialId: PersonId
  socialIds: PersonId[]
  fullSocialIds: SocialId[]
}

enum AccountRole {
  ReadOnlyGuest, DocGuest, Guest, User, Maintainer, Owner, Admin
}
```

Roles are ordered (`roleOrder`): `ReadOnlyGuest(5) < DocGuest(10) < Guest(20) < User(30) < Maintainer(40) < Owner(50) < Admin(100)`. The session `Account` (delivered in the `HelloResponse`) carries the workspace-level role; `Space.members`/`owners` and `SpaceType` roles refine access **within** a space. Effective access at a point is the intersection of: account is in the workspace, account is a member of the doc's space, and the account's role satisfies any space-type permissions.

`shouldShowArchived` (storage.ts) governs whether archived-space docs appear: archived content is hidden unless the query explicitly targets a single `_id` or a single `space`, or sets `options.showArchived`.

## Cross-references

- [client-protocol](client-protocol.md) -- the workspace-scoped socket and `endpoint`/`token` from `selectWorkspace`.
- [data-model](data-model.md) -- `Doc`/`Class`/`Hierarchy` and how a class maps to a domain.
- [transaction-model](transaction-model.md) -- transactions are themselves space-scoped docs.
- [storage-blobs](storage-blobs.md) -- `DOMAIN_BLOB` and datalake file storage.
- Service: [transactor](../services/transactor.md), [core-package](../services/core-package.md)
- Flows: [login-flow](../flows/login-flow.md)
- Types: [core-types](../types/core-types.md)

## Gotchas

- **Workspaces are fully isolated** — there is no cross-workspace query. Switching workspace means a new `selectWorkspace`, a new token, and a new transactor socket.
- A doc's `space` is **required and immutable in practice**; moving a doc between spaces is a remove+create, not an update of `space`.
- The transactor URL is **not stable per workspace across deployments** — it is derived by hashing the workspace UUID against the current transactor list. Always re-resolve via `selectWorkspace`; never cache the endpoint as a workspace identity.
- `DOMAIN_MODEL` classes are read from the in-memory model, so `LiveQuery` does **not** keep them live — they change only on a model upgrade.
- Membership-filtered reads are silent: a query that returns fewer docs than expected may be hitting space membership, not a bug.
- Archived spaces are hidden by default; if a list "loses" items after archiving, that is `shouldShowArchived` behavior.
