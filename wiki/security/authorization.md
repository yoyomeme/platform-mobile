# Authorization

> Once authenticated, what a user can see and do is governed by their **workspace role**, their **membership of Spaces**, and **permissions** assigned within space types. The Space is the fundamental access boundary: every `Doc` belongs to a Space, and seeing/editing a Doc means having access to its Space.

## Where in code
- `foundations/core/packages/core/src/classes.ts` -- `AccountRole`, `roleOrder`, `Space`, `TypedSpace`, `SpaceType`, `Role`, `Permission`, `RolesAssignment`
- `foundations/core/packages/token/src/token.ts` -- `Token.grant` (`PermissionsGrant`) carries role + `spaces` for access links
- `services/datalake/pod-datalake/src/middleware.ts` -- a concrete enforcement point (workspace + guest/readonly/admin checks)
- `server/account/src/utils.ts` -- workspace role assignment surfaces in `WorkspaceLoginInfo.role`

## Purpose

Authentication proves *who* you are; authorization decides *what* you may touch. Huly layers three mechanisms — a coarse workspace-wide role, Space membership for tenancy isolation, and fine-grained permissions for customizable space types — so a single workspace can host private projects, shared channels, and guest-shared documents with the right boundaries.

## Details

### Workspace roles

`AccountRole` is an ordered enum; `roleOrder` gives the numeric rank used for "at least this role" checks (higher = more privilege):

| Role | Value | rank |
|------|-------|------|
| `ReadOnlyGuest` | `READONLYGUEST` | 5 |
| `DocGuest` | `DocGuest` | 10 |
| `Guest` | `GUEST` | 20 |
| `User` | `USER` | 30 |
| `Maintainer` | `MAINTAINER` | 40 |
| `Owner` | `OWNER` | 50 |
| `Admin` | `ADMIN` | (system/global) |

The user's role for the selected workspace is returned in `WorkspaceLoginInfo.role` and embedded in the workspace-scoped token. Role comparisons use `roleOrder` rather than identity, so "requires User" means rank ≥ 30.

### Spaces as the access boundary

Every `Doc` has a `space: Ref<Space>`. A `Space` carries:

| Field | Type | Meaning |
|-------|------|---------|
| `members` | `AccountUuid[]` | Accounts with access to the space |
| `owners?` | `AccountUuid[]` | Accounts that own/administer the space |
| `private` | boolean | If true, only `members` can see it |
| `archived` | boolean | Hidden/closed |
| `autoJoin?` | boolean | New users are auto-added |
| `autoJoinForRoles?` | `AccountRole[]` | Roles auto-added on activation (e.g. `Guest`) |

Because access is per-space, a `findAll` only returns docs from spaces the caller may read. Sharing a project, channel, or teamspace is therefore a matter of space membership, not per-doc ACLs.

### Permissions and space types

For customizable spaces (`TypedSpace` → `SpaceType`):

| Type | Role |
|------|------|
| `SpaceType` | A configurable space template; holds `roles: Role[]` and a `targetClass` mixin for role assignment. |
| `Role` (AttachedDoc on SpaceType) | Named bundle of `permissions: Ref<Permission>[]`. |
| `RolesAssignment` | `Record<Ref<Role>, AccountUuid[]>` — which accounts hold which role in a space. |
| `Permission` | An access-control item: `label`, optional `txClass`/`objectClass`/`txMatch`, `forbid?`, and `scope: 'space' | 'workspace'`. |
| `SpaceTypeDescriptor` | Declares `availablePermissions` and `baseClass` for a family of space types. |
| `ModulePermissionGroup` | Maps an `AccountRole` to a set of permissions for an application module. |

`TypedSpace.restricted` means a user must hold a permission for *any* transaction in that space. `Permission.forbid` expresses a deny rule; `txMatch` narrows a permission to transactions matching a query.

### Guest and read-only access

- Guest tiers (`ReadOnlyGuest`, `DocGuest`, `Guest`) are low-rank roles for shared/limited access.
- Tokens can carry `extra.guest = 'true'` or `extra.readonly = 'true'`. Services enforce these: e.g. datalake `withAuthorization` **rejects** guest/readonly tokens for writes and deletes.
- Workspace-level toggles: `allowReadOnlyGuest` and `allowGuestSignUp` (on the workspace; `allowGuestSignUp` is also surfaced in `WorkspaceLoginInfo`).
- **Access links** (`createAccessLink`) issue tokens whose `grant: PermissionsGrant` embeds a `workspace`, `role`, and optional `spaces[]` — scoping a shared link to specific spaces.

### Admin

- `Admin` role and tokens with `extra.admin === 'true'` bypass workspace-scoping checks in services (e.g. datalake `withAdminAuthorization`, and the workspace-match check treats admin/system as always-allowed).
- The system account (`systemAccountUuid`) is treated as a super-identity in service middleware.
- Workspace administrators are configured via the `ADMIN_EMAILS` env var (account service), which elevates the listed emails.

## Cross-references

- [authentication](authentication.md) — how the role gets into the token
- [token-package](token-package.md) — `grant`/`PermissionsGrant`
- [workspace-multitenancy](../concepts/workspace-multitenancy.md) — spaces as tenancy
- [data-model](../concepts/data-model.md) — `Doc.space`
- [account-api](../api/account-api.md) — `updateWorkspaceRole`, `createAccessLink`
- [account service](../services/account.md)
- [core-types](../types/core-types.md)

## Gotchas

- Role checks compare **rank** (`roleOrder`), not equality — never compare role strings directly for "at least X".
- A token's `role` is fixed at `selectWorkspace` time; changing a user's role server-side does not retroactively change an already-issued token until it is re-minted.
- The access boundary is the **Space**, not the Doc — putting a doc in a space the user cannot read effectively hides it; there is no separate per-doc visibility flag.
- `extra.admin === 'true'` and the system account bypass workspace-scoping in services; never set these flags on user-facing tokens.
- Guest/read-only tokens validate fine for reads but are intentionally rejected for mutating datalake operations — handle the `401` distinctly from an expired token.
