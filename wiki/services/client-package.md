# @hcengineering/client + client-resources

> The connection layer. `@hcengineering/client` declares the `ClientFactory` contract and socket abstractions; `@hcengineering/client-resources` implements `GetClient` — opening the transactor WebSocket, loading the model, and wiring live tx delivery.

## Where in code

- `foundations/core/packages/client/src/index.ts` -- `clientId` plugin, `ClientFactory`, `ClientFactoryOptions`, `ClientSocket(Factory)`, `FilterMode`, ping/pong constants.
- `foundations/core/packages/client-resources/src/index.ts` -- the `GetClient` resource: token decode, model persistence (IndexedDB), tx filtering, `createClient` wiring.
- `foundations/core/packages/client-resources/src/connection.ts` -- `connect(url, handler, workspace, user, opt?)` and the `Connection` class implementing `ClientConnection` over a socket.

## Purpose

`@hcengineering/core` defines *what* a client and connection are (`Client`, `ClientConnection`, `createClient`) but never touches a socket. `@hcengineering/client` adds the **factory contract** — how the app obtains a `Client` from a `(token, endpoint)` pair — plus a DOM-free `ClientSocket` abstraction so the transport can be swapped (browser `WebSocket`, Node `ws`, native bridge).

`@hcengineering/client-resources` is the concrete implementation registered as the `GetClient` resource. It decodes the JWT to extract workspace + account, opens the transactor WebSocket via `connect`, supplies an IndexedDB-backed `TxPersistenceStore` to cache the model by hash, applies model filtering (`client`/`ui` modes strip server-only and UI-only model elements), and hands everything to `core.createClient`.

## Public API

### `@hcengineering/client` (`index.ts`)

| Export | Kind | Notes |
|--------|------|-------|
| `clientId` | `Plugin` | `'client'`. |
| `ClientFactory` | type | `(token: string, endpoint: string, opt?: ClientFactoryOptions) => Promise<Client>`. |
| `ClientFactoryOptions` | interface | `socketFactory?`, `useBinaryProtocol?`, `useProtocolCompression?`, `connectionTimeout?`, `onHello?`, `onUpgrade?`, `onError?`, `onConnect?`, `onDialTimeout?`, `ctx?`, `useGlobalRPCHandler?`. |
| `ClientSocketFactory` | type | `(url: string) => ClientSocket`. |
| `ClientSocket` | interface | DOM-free socket: `onmessage`/`onclose`/`onopen`/`onerror`, `send`, `close`, `readyState`, `bufferedAmount?`. |
| `ClientSocketReadyState` | enum | `CONNECTING`, `OPEN`, `CLOSING`, `CLOSED`. |
| `FilterMode` | type | `'none' \| 'client' \| 'ui'`. |
| `pingConst` / `pongConst` | const | `'ping'` / `'pong!'` keep-alive. |
| default `plugin(clientId, …)` | — | `metadata.ClientSocketFactory`, `metadata.FilterModel`, `metadata.UseBinaryProtocol`, `metadata.ConnectionTimeout`, `metadata.OverridePersistenceStore`; `function.GetClient: Resource<ClientFactory>`. |

### `@hcengineering/client-resources`

| Export | Signature | Notes |
|--------|-----------|-------|
| default `async () => ({ function: { GetClient } })` | resource module | The `ClientFactory` implementation. |
| `connect(url, handler, workspace, user, opt?)` | `(string, TxHandler, WorkspaceUuid, PersonUuid, ClientFactoryOptions?) => ClientConnection` | Constructs a `Connection` (socket transport) implementing `ClientConnection`. |

`GetClient(token, endpoint, opt?)` resolves filter mode from `clientPlugin.metadata.FilterModel`, builds a `handler` that calls `connect(concatLink(endpoint, '/' + token), …)`, decodes the token payload for `workspace`/`account`, applies a connection-timeout race, and returns `createClient(handler, modelFilter, modelPersistence, opt?.ctx)`.

## Usage

```typescript
import clientPlugin, { type ClientFactory } from '@hcengineering/client'
import { getResource, setMetadata } from '@hcengineering/platform'
import { type Client } from '@hcengineering/core'

// `token` + `endpoint` come from the account service's WorkspaceLoginInfo.
async function openWorkspace(token: string, endpoint: string): Promise<Client> {
  // Optional: filter the model to UI-relevant txes and tune timeout.
  setMetadata(clientPlugin.metadata.FilterModel, 'ui')
  setMetadata(clientPlugin.metadata.ConnectionTimeout, 30_000)

  const factory: ClientFactory = await getResource(clientPlugin.function.GetClient)
  return await factory(token, endpoint, {
    onConnect: async (event, lastTx, data) => {
      // event ∈ ClientConnectEvent: Connected | Reconnected | Upgraded | Refresh | Maintenance
    },
    onUpgrade: () => location.reload(),
    onDialTimeout: async () => { /* show "cannot reach server" */ }
  })
}
```

### Connection lifecycle

```
GetClient(token, endpoint)
   │  decode JWT → { workspace, account }
   ▼
connect(`${endpoint}/${token}`, upgradeHandler, workspace, account)
   │  open ClientSocket → HelloRequest/HelloResponse handshake
   ▼
createClient(handler, modelFilter, persistence)
   │  persistence.load() → cached model (by hash)
   │  conn.loadModel(lastTx, hash) → diff | full set of Tx[]
   │  buildModel() → Hierarchy + ModelDb
   ▼
Client ready; server pushes Tx[] (no id) → TxHandler → updateFromRemote → notify
   │  keep-alive: ping/pong; reconnect → onConnect(Reconnected|Refresh|Upgraded)
   ▼
client.close() → conn.close()
```

## Cross-references

- [core-package](core-package.md) -- `createClient`, `ClientConnection`, `Client`, `TxPersistenceStore`.
- [query-package](query-package.md) -- wraps the resulting `Client` in `LiveQuery`.
- [presentation-package](presentation-package.md) -- `setClient` installs this `Client` for the Svelte UI.
- Concepts: [client-protocol](../concepts/client-protocol.md).
- Flows: [model-load-flow](../flows/model-load-flow.md), [login-flow](../flows/login-flow.md).

## Gotchas

- **The JWT is the routing key.** `GetClient` decodes `token.split('.')[1]` (base64) to read `workspace` + `account`; it throws `'Workspace or account not found in token'` if either is missing. The transactor endpoint must already be the workspace-scoped one returned by `selectWorkspace`.
- **`client-resources` is browser-coupled.** It uses `localStorage`/`IndexedDB` for the model cache (`model.db.persistence`). A mobile/native port must replace this `TxPersistenceStore` (override via `clientPlugin.metadata.OverridePersistenceStore`) — this is the DOM glue that `core` deliberately omits.
- **Filter mode changes the model you see.** `'client'` strips server-only plugins; `'ui'` additionally strips disabled/unknown plugins. Pick `'none'` for a full model (e.g. server tooling), `'ui'` for an end-user app.
- **Connection timeout rejects, it does not retry.** If `connectionTimeout > 0` and no event arrives in time, the in-flight `connect` is closed and the promise rejects via `onDialTimeout`; reconnection is the `Connection`'s job afterward.
- **Server broadcasts arrive as id-less responses.** Connecting subscribes you to the workspace tx stream — there is no separate subscribe call; the `TxHandler` is the only delivery path.
