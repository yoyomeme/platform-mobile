# Token Package (`@hcengineering/server-token`)

> The small package that mints and verifies all Huly JWTs. `generateToken` is called by the account service to issue account- and workspace-scoped tokens; `decodeToken` is called by every backend service (transactor, datalake, collaborator, front, …) to verify inbound requests against the shared secret.

## Where in code
- `foundations/core/packages/token/src/token.ts` -- `generateToken`, `decodeToken`, `decodeTokenVerbose`, `Token`, `PermissionsGrant`, `TokenError`
- `foundations/core/packages/token/src/plugin.ts` -- `serverPlugin.metadata.Secret` / `.Service` metadata keys
- `foundations/core/packages/token/src/index.ts` -- package exports
- `foundations/server/packages/client/src/token.ts` -- `extractToken`/`readToken` helpers used by services to pull the token from headers/cookies

## Purpose

Centralizing token logic means one signing algorithm, one secret source, and one claims shape across 30+ services. Any service can verify a token locally (HMAC check) instead of calling back to the account service, which keeps the auth path fast and the trust model simple: hold the shared secret → trust the token.

## Details

### Algorithm

JWT via the `jwt-simple` library: `encode(payload, secret)` to sign, `decode(token, secret, noVerify)` to verify. Symmetric HMAC; the secret is resolved by `getSecret()` from `serverPlugin.metadata.Secret`, defaulting to `'secret'` when unset (`SERVER_SECRET` / `HULY_TOKEN_SECRET` in deployment). Account UUIDs and workspace UUIDs are validated with the `uuid` library before signing.

### Token claims

```ts
interface Token {
  account: AccountUuid
  workspace: WorkspaceUuid          // omitted/undefined for account-level tokens
  extra?: Record<string, any>       // e.g. { service, admin, guest, readonly }
  grant?: PermissionsGrant
  sub?: AccountUuid                  // subject (access links)
  exp?: number                      // expiry, seconds since epoch
  nbf?: number                      // not-before, seconds since epoch
}
```

| Field | Type | Description |
|-------|------|-------------|
| `account` | AccountUuid | Identity. Validated as a UUID at sign time. |
| `workspace` | WorkspaceUuid | Scopes the token to a workspace; absent ⇒ account-level token. |
| `extra` | object | Free-form flags. `service` is auto-injected when `serverPlugin.metadata.Service` is set. |
| `grant` | `PermissionsGrant` | Embedded grant for access links. |
| `sub` / `exp` / `nbf` | — | Standard JWT subject / expiry / not-before. |

### `PermissionsGrant`

| Field | Type | Description |
|-------|------|-------------|
| `workspace` | WorkspaceUuid | Workspace the grant applies to (validated UUID). |
| `role` | AccountRole | Role granted. |
| `grantedBy?` | AccountUuid | Issuer (for workspace-side validation). |
| `firstName?` / `lastName?` | string | Display identity for open-ended links. |
| `spaces?` | string[] | Restricts the grant to specific spaces. |
| `extra?` | object | Additional grant metadata. |

When `generateToken` is given a `grant` without `sub`, it **requires both `nbf` and `exp`** (open-ended access links must be time-bounded). The grant is sanitized to a known field set before encoding.

### Operations

| Operation | Signature | When used |
|-----------|-----------|-----------|
| `generateToken` | `(accountUuid, workspaceUuid?, extra?, secret?, options?) → string` | Account service mints login / workspace / access-link tokens. `options` = `{ grant?, nbf?, exp?, sub? }`. |
| `decodeToken` | `(token, verify = true, secret?) → Token` | Services verify inbound tokens; throws `TokenError` on bad signature/format. |
| `decodeTokenVerbose` | `(ctx, token) → Token` | Same as decode, but logs the unverified payload on failure for diagnostics. |
| `extractToken` (server-client) | `(headers) → Token | undefined` | Pull `Authorization: Bearer` or `token` cookie, then `decodeToken`. |

### How services verify

- **Transactor** — token is in the WS URL path (`/{token}`); the transactor decodes it, verifies the signature, and loads the `workspace` claim to scope the session.
- **Datalake** — `extractToken(req.headers)` (Bearer or cookie) → `decodeToken`; middleware then checks `token.workspace === {ws}` and inspects `extra.admin`/`guest`/`readonly`.
- **Collaborator** — verifies the same workspace-scoped token before allowing CRDT document sessions.
- **Front** — verifies a token only for protected routes like `/api/v1/statistics`.

All of them call `decodeToken` with the same default secret, so a token minted by the account service is accepted everywhere without extra coordination.

## Usage example

```typescript
import { generateToken, decodeToken } from '@hcengineering/server-token'

// Account service: mint a workspace-scoped token
const token = generateToken(accountUuid, workspaceUuid, { service: 'account' })

// Any service: verify on the way in
const claims = decodeToken(token)        // throws TokenError if invalid
if (claims.workspace !== requestedWorkspace) {
  throw new Error('Unauthorized')
}
```

## Cross-references

- [authentication](authentication.md) — token tiers and the auth sequence
- [authorization](authorization.md) — how `grant`/`role` drive access
- [account-api](../api/account-api.md) — RPC methods that call `generateToken`
- [transactor-rpc](../api/transactor-rpc.md) — token in the WS path
- [datalake-api](../api/datalake-api.md) — `extractToken` + workspace check
- [transactor service](../services/transactor.md), [datalake service](../services/datalake.md), [collaborator service](../services/collaborator.md)

## Gotchas

- The default secret is `'secret'`. Override it in every environment; a leaked secret lets anyone forge a token for any account/workspace.
- The HMAC is symmetric — every service shares the exact same `SERVER_SECRET`. Rotating it invalidates all live tokens simultaneously.
- `generateToken` throws `TokenError` if `account`/`workspace`/`grant.workspace` is not a valid UUID — pass UUIDs, not URL slugs.
- An open-ended `grant` (no `sub`) must include both `nbf` and `exp`, or signing throws.
- `decodeToken(token, false)` skips verification — only for diagnostics; never gate access on an unverified decode.
- `extra.service` is injected automatically when the service metadata is configured; do not set it by hand on user tokens.
