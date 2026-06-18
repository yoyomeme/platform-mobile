# Account

> Authentication and user/workspace management service (port `3000`). Exposes a JSON-RPC API over HTTP, issues JWT tokens, owns the global account/person/social-id/workspace database, and routes each workspace to a transactor endpoint by hashing the workspace UUID.

## Where in code
- `pods/account/src/__start.ts` -- process entry point; boots the service.
- `server/account-service/src/index.ts` -- `serveAccount()`: Koa HTTP server, env wiring, JSON-RPC dispatch (`POST /`), cookie/statistics/manage routes.
- `server/account/src/operations.ts` -- all RPC operation implementations; `getMethods(hasSignUp)` builds the method registry.
- `server/account/src/serviceOperations.ts` -- service-to-service (system token) methods (`getServiceMethods()`).
- `server/account/src/utils.ts` -- core helpers: token-aware `selectWorkspace`, password hashing, OTP, workspace creation, and the **workspace→transactor endpoint hashing** (`getEndpoint`, `hashWorkspace`).
- `server/account/src/collections/postgres/` and `collections/mongo` -- `AccountDB` storage implementations.
- `server/account/src/admin.ts` -- `isAdminEmail` (ADMIN_EMAILS).

## Purpose
Account is the single source of truth for identity in Huly. It authenticates users (password, OTP, OAuth providers, 2FA), tracks which workspaces a user belongs to and with what role, mints the JWT tokens every other service trusts, and tells clients which transactor endpoint to connect to for a given workspace. All other backend services verify those tokens using the shared `SERVER_SECRET`.

## Responsibilities
- Login / sign-up (email+password, OTP, guest, OAuth provider via `@hcengineering/auth-providers`), 2FA (TOTP), password reset/aging, account lockout after failed attempts.
- JWT issuance via `@hcengineering/server-token` `generateToken()` signed with `SERVER_SECRET`. User tokens carry no `service`; service tokens set `service`.
- Workspace lifecycle entry points: `createWorkspace` records a `pending-creation` workspace (picked up by the workspace service), plus delete/archive/rename and membership/role management.
- Invites, access links, join flows, read-only guest and guest sign-up toggles.
- Person / social-id management (`ensurePerson`, `addEmailSocialId`, merge persons, user profiles).
- **Transactor routing**: `getEndpoint(workspace, region, kind)` selects a transactor URL deterministically by Java-style hash of the workspace UUID modulo the number of endpoints in the region.
- Periodic cleanup of expired OTP codes (every 3 minutes).

## Key endpoints/methods

### HTTP transport (`server/account-service/src/index.ts`)
| Method / Path | Purpose |
|---------------|---------|
| `POST /` | JSON-RPC entry. Body `{ id, method, params }`; `method` is looked up in `getMethods()`. Unknown method → `UnknownMethod` 404. |
| `PUT /cookie`, `DELETE /cookie` | Set/clear the `account-metadata-Token` httpOnly cookie (workspace stripped from token). |
| `GET /api/v1/statistics` | Metrics/health (admin sees full metrics). |
| `PUT /api/v1/manage?operation=maintenance` | Admin-only; fan-out maintenance to all transactors. |
| OAuth callback routes | Registered by `registerProviders()`. |

Token is taken from the `Authorization: Bearer <jwt>` header or the `account-metadata-Token` cookie. Request meta is read from `x-timezone` and `x-client-network-position` headers.

### JSON-RPC methods (selected, from `getMethods()`)
| Method | Description |
|--------|-------------|
| `login` / `loginOtp` / `loginAsGuest` | Authenticate; returns a `LoginInfo` (account + workspace-less token). |
| `signUp` / `signUpOtp` / `validateOtp` | Registration (gated by `DISABLE_SIGNUP`). |
| `selectWorkspace` | Returns `WorkspaceLoginInfo` with a workspace-scoped token, role, and the routed transactor `endpoint`. |
| `getUserWorkspaces` / `getWorkspaceInfo` / `getWorkspacesInfo` | Workspace listings/info for a user. |
| `createWorkspace` | Creates a `pending-creation` workspace record. |
| `join` / `joinByToken` / `checkJoin` / `getInviteInfo` | Invite-based join flows. |
| `getLoginInfoByToken` / `getLoginWithWorkspaceInfo` | Validate a token and return identity/workspace info (used by other services). |
| `changePassword` / `requestPasswordReset` / `restorePassword` / `checkPasswordAging` | Password management. |
| `generate2faSecret` / `enable2fa` / `disable2fa` / `verify2fa` | TOTP 2FA. |
| `updateWorkspaceRole` / `getWorkspaceMembers` / `leaveWorkspace` | Membership & roles. |
| Service methods (`getServiceMethods()`) | System-token methods used by transactor/workspace/etc. |

## Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `ACCOUNT_PORT` | `3000` | HTTP listen port. |
| `DB_URL` | (required) | CockroachDB/Postgres connection (MongoDB deprecated; needs `PROCEED_V7_MONGO=true`). |
| `DB_NS` | `global_account` | Account DB namespace/schema. |
| `TRANSACTOR_URL` | (required) | Comma-separated transactor endpoints (`internal;external;region`) used by `getEndpoint`. |
| `SERVER_SECRET` / `SECRET` | `secret` | JWT signing secret shared with all services. |
| `REGION_INFO` | `cockroach\|CockroachDB` | Region list (`region\|name;...`). |
| `STATS_URL` | `http://huly.local:4900` | Metrics endpoint. |
| `MAIL_URL` / `MAIL_AUTH_TOKEN` | — | Email service for OTP/confirmation. |
| `FRONT_URL` | `http://huly.local:8087` | Used in email confirmation links. |
| `OTP_TIME_TO_LIVE` / `OTP_RETRY_DELAY` | `60` | OTP TTL / retry delay (seconds). |
| `MAX_FAILED_LOGIN_ATTEMPTS` | `5` | Account lock threshold (`<=0` disables). |
| `DISABLE_SIGNUP` | `false` | When `true`, removes `signUp`/`signUpOtp`. |
| `ADMIN_EMAILS` | — | Comma-separated admin emails. |
| `OLD_ACCOUNTS_URL` / `OLD_ACCOUNTS_NS` | — | Migration from legacy account DB. |

## Cross-references
- API surface: [account-api](../api/account-api.md)
- Routing & token verification on connect: [transactor](transactor.md)
- Token format and signing: [authentication](../security/authentication.md)
- Login sequence: [login-flow](../flows/login-flow.md)
- Client request transport: [client-protocol](../concepts/client-protocol.md)
- Multi-tenant model: [workspace-multitenancy](../concepts/workspace-multitenancy.md)
- Workspace creation consumer: [workspace](workspace.md)

## Gotchas
- **Transactor selection is deterministic, not load-balanced.** `getEndpoint` hashes the workspace UUID (`hashWorkspace`, Java `String.hashCode` semantics) modulo the per-region endpoint count. The same workspace always maps to the same transactor; adding/removing endpoints reshuffles mappings.
- `TRANSACTOR_URL` entries are `;`-separated triples `internalUrl;externalUrl;region`. Empty `externalUrl` falls back to `internalUrl`. The `kind` (internal/external) and `x-client-network-position` decide which URL the client receives.
- User tokens deliberately omit `service` (`setMetadata(serverToken.metadata.Service, undefined)`); service tokens set it. Mixing them changes trust handling downstream.
- A `selectWorkspace` token without a valid token still succeeds for read-only-guest workspaces (`allowReadOnlyGuest`), returning a `readonly`/`DocGuest` role.
- MongoDB is deprecated in v7 and the path is intentionally hard-failed unless `PROCEED_V7_MONGO=true`.
