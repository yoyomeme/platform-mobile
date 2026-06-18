# Login (`login`)

> The login/onboarding UI flow plugin: sign-in, sign-up, OTP/2FA, workspace selection, invites, and password recovery — a thin UI shell over the account service.

## Where in code
- `plugins/login/src/index.ts` -- plugin id (`loginId = 'login'`), `pages` list, metadata, and the `function` registry of account-service-backed resources
- `plugins/login-resources/` -- UI (page components per `Pages` value) and `utils.ts` (the reference onboarding flow, cited in MOBILE_APP_ARCHITECTURE)
- Backed by `foundations/core/packages/account-client/` -- the actual JSON-RPC account client

## Purpose
`login` is **pure UI/flow orchestration** — it has *no document classes*. It defines the set of
onboarding pages and a registry of `Resource` functions that wrap the **account service** (the
JSON-RPC service at `ACCOUNTS_URL`) for login, workspace selection, password change, invites, and
2FA. After a workspace is selected it hands a `WorkspaceLoginInfo` (token + transactor `endpoint`) to
the workbench, which opens the real-time connection.

## "Pages" (the onboarding flow)
`pages` enumerates the screens: `login`, `signup`, `createWorkspace`, `password`, `recovery`,
`selectWorkspace`, `admin`, `join`, `autoJoin`, `confirm`, `confirmationSend`, `auth`,
`login-password`, `changePassword`, `tfa`.

## Key registry (no doc classes — functions + metadata)
| Member | Kind | Description |
|---|---|---|
| `function.SelectWorkspace(workspace, token)` | Resource | Resolves a workspace → `[Status, WorkspaceLoginInfo, …]` (yields the transactor `endpoint`). |
| `function.GetWorkspaces()` | Resource | Lists the account's `WorkspaceInfoWithStatus[]`. |
| `function.FetchWorkspace()` | Resource | Current workspace info/status. |
| `function.GetPerson()` | Resource | The logged-in `contact.Person`. |
| `function.ChangePassword` / `RequestPasswordSetup` / `CheckHasPassword` | Resource | Password lifecycle. |
| `function.SendInvite` / `ResendInvite` / `GetInviteLink` | Resource | Workspace invitations. |
| `function.LeaveWorkspace`, `ExchangeGuestToken`, `GetWorkspacePermissions` | Resource | Membership / guest / permission queries. |
| `metadata.AccountsUrl`, `LoginEndpoint`, `LastAccount`, `LoginAccount` | Metadata | Account service URL + cached identity. |
| `metadata.TransactorOverride`, `DisableSignUp`, `HideLocalLogin` | Metadata | Deployment toggles. |
| `metadata.PasswordValidations` | Metadata | Min length / digits / special chars rules. |
| Re-exported types | -- | `LoginInfo`, `WorkspaceLoginInfo`, `OtpInfo`, `RegionInfo` (from `account-client`). |

## Notable flows
- **Login → workspace → connect:** `login`/`login-password` (or OTP `auth`/`tfa`) → account `login`
  returns `LoginInfo { account, token, tfaRequired? }` → `selectWorkspace` returns
  `WorkspaceLoginInfo { token, endpoint, … }` → workbench connects the transactor WS to `endpoint`.
- **Invites/join:** `join`/`autoJoin` consume an invite link; `confirm`/`confirmationSend` handle email
  verification.
- **Password/2FA:** `changePassword`, `recovery`, `tfa` — all account-service round-trips.

## Mobile relevance
**Directly maps to the mobile auth/onboarding flow.** The mobile app reimplements these screens, but
the **function registry is the exact account-service API contract** to port: enter base URL → fetch
`config.json` for `ACCOUNTS_URL` → `login`/OTP → `getUserWorkspaces` → `selectWorkspace` →
`WorkspaceLoginInfo.endpoint` → transactor WS. `metadata.PasswordValidations` drives client-side
password rules; cache identity like `LastAccount` in secure storage.

## Cross-references
- Plugins: [workbench](workbench.md) (consumes `WorkspaceLoginInfo`, opens the connection), [setting](setting.md) (password/2FA management), [contact](contact.md) (`GetPerson`)
- Concepts: [client-protocol](../concepts/client-protocol.md), [workspace-multitenancy](../concepts/workspace-multitenancy.md)
- Services: `services/account.md`, `services/front.md` (config.json)
- Reference: MOBILE_APP_ARCHITECTURE.md §1.2 (login & workspace selection)

## Gotchas
- No `Doc` classes — this plugin is flow + account-service wrappers only; don't look for a model.
- Auth happens against the **account service** (HTTP JSON-RPC), *not* the transactor; the transactor
  connection comes only after `selectWorkspace` yields an `endpoint`.
- `tfaRequired` on `LoginInfo` means the `tfa` page must run before a usable token is issued.
- `TransactorOverride` lets a deployment force a transactor URL, overriding the account-supplied
  `endpoint` — honor it if set.
