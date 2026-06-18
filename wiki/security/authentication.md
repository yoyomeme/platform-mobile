# Authentication

> Huly authenticates users and services with **JWT bearer tokens end-to-end**. The account service mints tokens; every other service verifies them against a shared `SERVER_SECRET`. There are two token tiers — an account-level token and a workspace-scoped token — and a client must upgrade from the first to the second before it can touch live data or files.

## Where in code
- `foundations/core/packages/token/src/token.ts` -- `generateToken` / `decodeToken`, the `Token` claims shape
- `foundations/server/packages/client/src/token.ts` -- `extractToken` / `readToken` (Bearer header or cookie)
- `foundations/core/packages/account-client/src/client.ts` -- client sets `Authorization: Bearer <token>`
- `server/account/src/utils.ts` -- `getEndpoint` (workspace → transactor) embedded in `WorkspaceLoginInfo`
- `services/datalake/pod-datalake/src/middleware.ts` -- datalake token verification example
- `ARCHITECTURE_OVERVIEW.md` §4 -- the end-to-end auth sequence

## Purpose

Mobile and web clients are stateless: no server-side sessions, no session cookies required. A token is the single bearer of identity and workspace scope. Services trust each other because they all sign/verify with the same `SERVER_SECRET`, so the account service can issue a token that the transactor, datalake, and collaborator all accept without an extra round-trip to a central auth store.

## Details

### Algorithm

Tokens are **JWT** signed with **HMAC** using the `jwt-simple` library (`encode`/`decode`). The signing secret comes from server metadata `serverPlugin.metadata.Secret`, defaulting to `'secret'` in dev (`SERVER_SECRET` / `HULY_TOKEN_SECRET` in deployment). The same secret both signs (account) and verifies (every service), making this a symmetric, shared-secret scheme — every backend service holds the same `SERVER_SECRET`.

### Token claims

| Claim | Type | Description |
|-------|------|-------------|
| `account` | AccountUuid | The account the token represents. Must be a valid UUID. |
| `workspace` | WorkspaceUuid? | Present on **workspace-scoped** tokens; absent on account-level tokens. |
| `extra` | `Record<string, any>?` | Flags/metadata, e.g. `service`, `admin: 'true'`, `guest: 'true'`, `readonly: 'true'`. |
| `grant` | `PermissionsGrant?` | Embedded grant for access-link tokens (workspace, role, optional `spaces`). |
| `sub` | AccountUuid? | Subject (for personalized access links). |
| `exp` | number? | Expiry, seconds since epoch. |
| `nbf` | number? | Not-valid-before, seconds since epoch. |

If a service identity is configured (`serverPlugin.metadata.Service`), it is injected as `extra.service` — that is how the datalake tells "service" traffic from "user" traffic.

### Account token vs workspace-scoped token

| | Account token | Workspace-scoped token |
|---|---|---|
| Issued by | `login` / `validateOtp` / `signUp` | `selectWorkspace` / `join` / `signUpJoin` |
| `workspace` claim | absent | present |
| Use | list/select workspaces on the account service | transactor WS, datalake, collaborator |
| Carries `role` | no | yes (the workspace `AccountRole`) |

The transactor and datalake **reject** the account token: the transactor needs the workspace in the URL/token, and datalake middleware checks `token.workspace === {ws}`.

### Service-to-service auth (`SERVER_SECRET`)

Internal services authenticate to each other by minting a token (often `systemAccountUuid` or with `extra.service`/`extra.admin`) signed with the shared `SERVER_SECRET`. Because verification is just an HMAC check with the same secret, no service needs to call the account service to validate inbound calls. This is why the secret must be identical across the whole deployment and treated as a high-value secret.

### The §4 auth sequence (end to end)

```
1. Client → Account:  login(email, password)
                      → LoginInfo { account, token }            (account-level JWT)
2. Client → Account:  getUserWorkspaces()      [Bearer account token]
                      → WorkspaceInfoWithStatus[]
3. Client → Account:  selectWorkspace(url, kind) [Bearer account token]
                      → WorkspaceLoginInfo { token, endpoint, workspace, role }
                                                 (workspace-scoped JWT + transactor URL)
4. Client → Transactor:  WS connect  ws://{endpoint}/{workspaceToken}?sessionId=...
                         transactor decodeToken() → verified, workspace loaded
5. Client → Datalake:    Authorization: Bearer {workspaceToken}
                         middleware: token.workspace === {ws} ? allow : 401
```
The account service picks the transactor `endpoint` deterministically from the workspace UUID (`getEndpoint` hashes the UUID over the configured `TRANSACTOR_URL` list); the client just connects to whatever URL it is handed.

### Token transport per service

| Service | Where the token goes |
|---------|----------------------|
| Account (HTTP RPC) | `Authorization: Bearer <token>` header |
| Transactor (WebSocket) | URL **path**: `ws://{endpoint}/{token}?sessionId=...` |
| Datalake (HTTP) | `Authorization: Bearer <token>` header (or `token` cookie) |

## Cross-references

- [token-package](token-package.md) — `generateToken`/`decodeToken` internals
- [authorization](authorization.md) — what roles/permissions the token grants
- [account-api](../api/account-api.md) — methods that issue tokens
- [transactor-rpc](../api/transactor-rpc.md) — token in the WS path
- [datalake-api](../api/datalake-api.md) — token verification middleware
- [account service](../services/account.md)
- [login-flow](../flows/login-flow.md)

## Gotchas

- The default secret is literally `'secret'` — any real deployment **must** override `SERVER_SECRET`/`HULY_TOKEN_SECRET`, since anyone with it can forge tokens for any account/workspace.
- Token verification is symmetric HMAC; there is no public-key rotation. Rotating the secret invalidates **all** outstanding tokens at once.
- The account token does not work against the transactor or datalake — a client must call `selectWorkspace` first.
- The transactor receives the token in the URL path, so it can appear in proxy/access logs; treat transactor URLs as sensitive.
- `decodeToken(token, verify=false)` skips signature verification (used only for diagnostics in `decodeTokenVerbose`); never trust an unverified decode for access decisions.
