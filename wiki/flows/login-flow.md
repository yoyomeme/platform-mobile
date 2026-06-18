# Login Flow

> How a client turns a single instance **base URL** into a workspace **endpoint + token** it can open a real-time connection with: config discovery → account login → workspace list → workspace selection.

## Where in code
- `server/front/src/index.ts` -- serves `GET /config.json` (the discovery document)
- `plugins/login-resources/src/utils.ts` -- `doLogin`, `getWorkspaces`, `selectWorkspace`, `fetchWorkspace`
- `foundations/core/packages/account-client/src/client.ts` -- `AccountClientImpl`: JSON-RPC methods `login`, `getUserWorkspaces`, `selectWorkspace`
- `plugins/workbench-resources/src/connect.ts` -- `connect()` ties selection → transactor connection

## Sequence

```
 Client App            Front (:8087)         Account (:3000)          Transactor
    |                       |                      |                       |
    | GET /config.json      |                      |                       |
    |---------------------->|                      |                       |
    |  { ACCOUNTS_URL,      |                      |                       |
    |    FILES_URL, ... }    |                      |                       |
    |<----------------------|                      |                       |
    |                                              |                       |
    | POST {method:"login", params:{email,password}}                      |
    |--------------------------------------------->|                       |
    |  LoginInfo { account, token, tfaRequired? }  |                       |
    |<---------------------------------------------|                       |
    |                                              |                       |
    | POST {method:"getUserWorkspaces"}  (Bearer token)                   |
    |--------------------------------------------->|                       |
    |  WorkspaceInfoWithStatus[]                    |                       |
    |<---------------------------------------------|                       |
    |                                              |                       |
    | POST {method:"selectWorkspace",              |                       |
    |       params:{workspaceUrl, kind}}  (Bearer) |                       |
    |--------------------------------------------->|                       |
    |  WorkspaceLoginInfo { token, endpoint, ... } |                       |
    |<---------------------------------------------|                       |
    |                                              |                       |
    | ws://{endpoint}/{token}?sessionId=...        |                       |
    |------------------------------------------------------------------->  |
    |                                              |   (see model-load-flow)|
```

## Steps

| Step | Action | Error code on failure |
|------|--------|----------------------|
| 1 | Fetch `GET {BASE_URL}/config.json`; derive `ACCOUNTS_URL`, `FILES_URL`, `UPLOAD_URL`, `COLLABORATOR_URL`, `PULSE_URL`, etc. | `CONFIG-001` |
| 2 | `account.login(email, password)` → `LoginInfo` with a global `token`. (Or `loginOtp`/`validateOtp` for passwordless.) | `Unauthorized` / `InvalidPassword` / `AccountNotFound` |
| 3 | If `LoginInfo.tfaRequired === true`, prompt for 2FA and call `verify2fa(code)` with the returned token. | `InvalidOtp` |
| 4 | `account.getUserWorkspaces()` (Bearer global token) → `WorkspaceInfoWithStatus[]`. | `Unauthorized` |
| 5 | `account.selectWorkspace(workspaceUrl, kind)` (Bearer global token) → `WorkspaceLoginInfo` with a **workspace-scoped** `token` and the transactor `endpoint`. | `WorkspaceNotFound` / `Unauthorized` |
| 6 | If `isWorkspaceCreating(workspace.mode)`, poll `getWorkspaceInfo()` until ready (progress in `processingProgress`). | `WorkspaceArchived` |
| 7 | Connect the transactor WebSocket at `ws://{endpoint}/{token}?sessionId={uuid}`. | (see [model-load-flow](model-load-flow.md)) |

## Code

```typescript
import { getClient as getAccountClient } from '@hcengineering/account-client'
import { loadServerConfig } from '@hcengineering/presentation'

// 1. Discover backend URLs from the single base URL.
const config = await loadServerConfig(`${baseUrl}/config.json`)
const accountsUrl: string = config.ACCOUNTS_URL

// 2. Login with credentials (no token yet).
const anon = getAccountClient(accountsUrl)
const loginInfo = await anon.login(email, password)
if (loginInfo.token == null) {
  // tfaRequired or confirmation pending — handle separately.
  return
}

// 3. List the user's workspaces (Bearer = global token).
const account = getAccountClient(accountsUrl, loginInfo.token)
const workspaces = await account.getUserWorkspaces()

// 4. Select one → get the workspace-scoped token + transactor endpoint.
const ws = await account.selectWorkspace(workspaces[0].url, 'external')
const { token, endpoint, workspace, role } = ws

// `token` + `endpoint` are now everything needed to open the live connection.
// (kind: 'external' for public URL, 'internal' for in-cluster, 'byregion' for region routing.)
```

## Prerequisites

- The user has supplied a valid instance **base URL** (e.g. `https://huly.example.com`).
- `config.json` is reachable (front service up; CORS allows the client origin).
- The account is confirmed and a member of at least one workspace.

## Error handling

```typescript
import { PlatformError } from '@hcengineering/platform'

try {
  const loginInfo = await getAccountClient(accountsUrl).login(email, password)
  // ...
} catch (err: unknown) {
  if (err instanceof PlatformError) {
    // err.status.code is one of: Unauthorized, InvalidPassword, AccountNotFound, InvalidOtp, ...
    showLoginError(err.status)
  } else {
    // Network error — the account client retries network failures up to ~5 s before throwing.
    showNetworkError()
  }
}
```

The account client (`AccountClientImpl`) automatically retries **network** errors (`withRetryUntilTimeout`, default 5 s) but throws application errors (`{ error }` in the JSON-RPC response becomes a `PlatformError`) immediately.

## Cross-references

- [model-load-flow](model-load-flow.md) -- what happens after the WS connects
- [client-protocol](../concepts/client-protocol.md) -- the JSON-RPC + WebSocket protocol
- Service: [account](../services/account.md), [front](../services/front.md), [transactor](../services/transactor.md)
- API: [account-api](../api/account-api.md), [front-config](../api/front-config.md)
- Types: [core-types](../types/core-types.md)

## Gotchas

- **Two different tokens.** `login` returns a *global* token; `selectWorkspace` returns a *workspace-scoped* token. The transactor WebSocket needs the **workspace-scoped** one (`WorkspaceLoginInfo.token`), not the global login token.
- **The endpoint is server-chosen.** The account service hashes the workspace UUID across its `TRANSACTOR_URL` list and returns the chosen transactor as `endpoint`. The client must connect to whatever it is handed — do not hardcode a transactor URL. `kind: 'internal'` vs `'external'` only selects the network face of the same routing.
- **Account is JSON-RPC, not REST.** Every call is `POST {ACCOUNTS_URL}` with body `{ method, params }`; the result is in `{ result }` and errors in `{ error }`. There are no per-method REST paths.
- **Headers.** Authenticated calls send `Authorization: Bearer {token}`, `Content-Type: application/json`, and an optional `x-timezone` meta header.
- **Workspace may still be creating.** A freshly created workspace returns a `mode` that satisfies `isWorkspaceCreating`; poll `getWorkspaceInfo()` until it clears before connecting.
- **Token expiry → reconnect.** If a workspace token is rejected later, re-run `selectWorkspace` to mint a fresh one (the web client does this on dial timeout / `Unauthorized`).
```