# Account API (JSON-RPC)

> The **account** service speaks JSON-RPC over a single HTTP `POST` endpoint. Body shape is `{ method, params }`; response is `{ result }` on success or `{ error }` on failure. It handles login, sign-up, OTP, workspace listing/selection, password reset, and invites — and hands back the JWT and transactor `endpoint` a client needs to open the real-time connection.

## Where in code
- `foundations/core/packages/account-client/src/client.ts` -- `AccountClient` interface + `AccountClientImpl` (every method builds `{ method, params }` and `POST`s to the accounts URL)
- `foundations/core/packages/account-client/src/types.ts` -- `LoginInfo`, `WorkspaceLoginInfo`, `OtpInfo`, etc.
- `server/account/src/utils.ts` -- `getEndpoint` resolves the transactor URL returned in `WorkspaceLoginInfo.endpoint`

## Transport

All RPC calls go to a single URL (the accounts base URL itself), method `POST`:

| Setting | Value |
|---------|-------|
| URL | `ACCOUNTS_URL` (from [config.json](front-config.md)) |
| Method | `POST` |
| Content-Type | `application/json` |
| Connection | `keep-alive` |
| Auth | `Authorization: Bearer <token>` (only for methods that require an authenticated user/workspace) |
| `x-timezone` | optional IANA timezone, sent when available |
| Body | `{ "method": "<name>", "params": { ... } }` |

The client retries on network errors until a timeout (default 5 s). Errors come back as `{ error: Status }` and are thrown as `PlatformError`.

## Endpoints

All requests share the same `POST` URL; the table below lists the `method` value and `params` object for each.

### `login`

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `email` | string | yes | Account email |
| `password` | string | yes | Plaintext password |

**Request:**
```json
{ "method": "login", "params": { "email": "a@b.com", "password": "secret" } }
```
**Response (`LoginInfo`):**
```json
{ "result": { "account": "<accountUuid>", "name": "Ann", "socialId": "<personId>", "token": "<jwt>", "tfaRequired": false } }
```
If `tfaRequired` is true, no usable `token` is issued until `verify2fa` succeeds.

### `loginOtp` / `validateOtp` (passwordless)

`loginOtp` params: `{ email }` → returns `OtpInfo { sent, retryOn }` (sends a code).
`validateOtp` params: `{ email, code, password?, action? }` → returns `LoginInfo` with a `token`.

```json
{ "method": "validateOtp", "params": { "email": "a@b.com", "code": "123456" } }
```

### `signUp` (dev-only)

| Param | Type | Description |
|-------|------|-------------|
| `email`, `password`, `firstName`, `lastName` | string | New account |

Returns `LoginInfo`. Marked **deprecated — only for dev setups without a mail service**; production sign-up uses `signUpOtp` + `validateOtp`.

### `getUserWorkspaces`

Params: `{}`. **Requires Bearer token.** Returns `WorkspaceInfoWithStatus[]` (workspace UUID, url, mode, version, status flattened in).

### `selectWorkspace`

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `workspaceUrl` | string | — | The workspace's URL slug |
| `kind` | `'external'` \| `'internal'` \| `'byregion'` | `'external'` | Which transactor URL variant to return |
| `externalRegions` | string[] | `[]` | Regions to treat as external when `byregion` |

**Requires Bearer token.** Returns `WorkspaceLoginInfo` — the payload that unlocks the transactor connection:
```json
{
  "result": {
    "account": "<accountUuid>",
    "token": "<workspace-scoped jwt>",
    "workspace": "<workspaceUuid>",
    "workspaceUrl": "my-team",
    "workspaceDataId": "<dataId>",
    "endpoint": "ws://huly.local:3332",
    "role": "USER",
    "allowGuestSignUp": false
  }
}
```
`kind: 'internal'` returns the internal-network transactor URL; `'external'` returns the public one.

### `requestPasswordReset`

Params: `{ email }`. Returns `void` (sends a reset email).

### `changePassword`

Params: `{ oldPassword, newPassword }`. **Requires Bearer token.** Returns `void`.

### `createInviteLink`

| Param | Type | Description |
|-------|------|-------------|
| `email`, `role`, `autoJoin`, `firstName`, `lastName` | — | Invitee + assigned `AccountRole` |
| `navigateUrl?`, `expHours?` | — | Optional landing URL and expiry |

Returns a string invite id/link. **Requires Bearer token** (an existing workspace member).

### `join` / `signUpJoin`

`join` params: `{ email, password, inviteId, workspaceUrl }` — joins an existing account to a workspace via invite.
`signUpJoin` params: `{ email, password, first, last, inviteId, workspaceUrl }` — creates the account and joins in one step.
Both return `WorkspaceLoginInfo` (already workspace-scoped, ready for the transactor).

Related invite reads: `getInviteInfo({ inviteId })` → `InviteInfo { workspaceName }` (public, no auth); `checkJoin` / `joinByToken` / `checkAutoJoin` → `WorkspaceLoginInfo`.

### `verify2fa`

Params: `{ code }`. Returns `LoginInfo`. Used to complete a login flagged `tfaRequired`.

**Error codes:** every method returns `{ error: Status }` on failure, where `Status` carries a platform status code (e.g. account not found, invalid password, workspace not found, OTP expired) and parameters. The client throws these as `PlatformError`. There is no numeric HTTP error table — failures are `200` with an `error` body, except network/transport failures.

## Auth

- Unauthenticated: `login`, `loginOtp`, `validateOtp`, `signUp`, `signUpOtp`, `requestPasswordReset`, `getInviteInfo`, `getProviders`.
- Authenticated (`Authorization: Bearer <token>`): everything operating on the current user or workspace — `getUserWorkspaces`, `selectWorkspace`, `changePassword`, `createInviteLink`, `getWorkspaceMembers`, etc.
- Two token tiers: the **account token** from `login` scopes you to the account (list/select workspaces). The **workspace-scoped token** from `selectWorkspace`/`join` embeds `workspace` and `role` and is what the transactor and datalake accept. See [authentication](../security/authentication.md).

## Cross-references

- [transactor-rpc](transactor-rpc.md) — connect to `WorkspaceLoginInfo.endpoint` with the workspace token
- [front-config](front-config.md) — `ACCOUNTS_URL` source
- [authentication](../security/authentication.md) — account vs workspace token
- [token-package](../security/token-package.md) — JWT generation/verification
- [account service](../services/account.md)
- [workspace-multitenancy](../concepts/workspace-multitenancy.md)
- [login-flow](../flows/login-flow.md)

## Gotchas

- It is **JSON-RPC, not REST** — there is exactly one `POST` URL; the operation is in the `method` field, not the path.
- Errors are returned with HTTP `200` and an `error` body; only transport problems surface as HTTP errors. Always check `result.error`.
- The `token` from `login` is **not** accepted by the transactor — you must call `selectWorkspace` (or `join`) to get the workspace-scoped token.
- `signUp` is deprecated; prefer the OTP flow in production.
- `getUserWorkspaces`/`getWorkspaceInfo` flatten the workspace `status` object onto the top-level result (`flattenStatus`), so status fields appear inline.
- In browsers the client also sends `credentials: 'include'`; non-browser clients omit cookies and rely solely on the Bearer header.
