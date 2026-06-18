# Transactor RPC (WebSocket)

> The **transactor** is the live data channel. A client opens one WebSocket per workspace, performs a Hello handshake, then issues request/response RPC calls. Reads go through `findAll`/`findOne`, writes through `tx`, and the server pushes new transactions back as id-less broadcasts — that is the real-time mechanism. There is no per-feature API; this is essentially the whole data API.

## Where in code
- `foundations/core/packages/rpc/src/rpc.ts` -- `Request`/`Response`/`HelloRequest`/`HelloResponse` framing, `RPCHandler` serialization
- `foundations/core/packages/client-resources/src/connection.ts` -- `Connection` class: handshake, send/receive, ping, reconnect, the RPC methods
- `foundations/core/packages/client-resources/src/index.ts` -- builds the WS URL: `concatLink(endpoint, '/' + token)`

## Connection

```
ws(s)://{endpoint}/{token}?sessionId={uuid}
```
- `endpoint` — from `WorkspaceLoginInfo.endpoint` returned by the account service `selectWorkspace`.
- `token` — the **workspace-scoped** JWT, placed in the URL **path** (not a header).
- `sessionId` — a client-generated id appended as a query param; reused across reconnects of the same session.

### Hello handshake

First frame after connect is a `HelloRequest`:
```ts
HelloRequest = { method: 'hello', params: [], binary?: boolean, compression?: boolean }
```
The server replies with a `HelloResponse`:
```ts
HelloResponse = {
  binary: boolean,          // server-selected serialization
  serverVersion: string,
  lastTx?: string,          // id of last tx — pass to loadModel
  lastHash?: string,        // last model hash — cache key for the model
  account: Account,
  useCompression?: boolean,
  reconnect?: boolean
}
```
The client adopts `binary`/`useCompression` from the response for all subsequent frames.

### Request / Response framing

```ts
Request<P>  = { id?, method: string, params: P, meta?, time? }
Response<R> = { result?, id?, error?, terminate?, chunk?, rateLimit?, time?, bfst?, queue? }
```
- Each request carries a numeric/string `id`; the matching response echoes it. The client matches responses to pending requests by `id`.
- `chunk { index, final }` streams a large result across multiple frames.
- `rateLimit` (`RateLimitInfo { remaining, limit, current, reset, retryAfter }`) signals throttling.
- `error` is a platform `Status`.

## Methods

All issued via `sendRequest({ method, params })`. `params` is a positional array.

| Method | Params | Purpose |
|--------|--------|---------|
| `loadModel` | `[last: Timestamp, hash?]` | Load model transactions to build the `Hierarchy` (classes/attributes/mixins). Run once at startup; returns `Tx[]` or `LoadModelResponse`. |
| `findAll` | `[_class, query, options?]` | **All reads.** Mongo-style query → `FindResult<T>` (array + optional `total`, `lookupMap`). |
| `findOne` | `[_class, query, options?]` | Single doc (implemented as `findAll` with `limit: 1`). |
| `tx` | `[tx]` | **All writes.** Submit one transaction; broadcast back to all clients. |
| `searchFulltext` | `[query, options]` | Full-text search → `SearchResult`. |
| `domainRequest` | `[domain, params, options?]` | Low-level per-domain operations → `DomainResult`. |
| `getAccount` | `[]` | Current account. |
| `loadChunk` / `loadDocs` / `closeChunk` / `getDomainHash` | domain ops | Bulk/sync domain transfer (backup/restore tooling). |
| `upload` / `clean` | `[domain, docs]` | Bulk write/delete of raw docs. |
| `forceClose` | `[]` | Terminate the session. |

## Live broadcast

The server pushes transactions to subscribed clients as a `Response<Tx[]>` **with no `id`** (it is not a reply to any request). The client routes id-less responses to its registered `TxHandler`(s) (`pushHandler`), applies them to its local cache, and the UI reacts. **There is no subscribe call** — connecting to a workspace subscribes you to its tx stream. Server-originated lifecycle events arrive the same way (e.g. `TxWorkspaceEvent`).

## Serialization & compression

`RPCHandler` (`rpc.ts`):
- **JSON** by default (`JSON.stringify`/`JSON.parse` with `rpcJSONReplacer`/`rpcJSONReceiver`).
- **Binary** via MessagePack (`Packr` from `msgpackr`) when `binary` is negotiated.
- Optional compression when `useCompression` is negotiated.
- A custom `TotalArray` envelope preserves `total`/`lookupMap` metadata that rides alongside `findAll` array results through (de)serialization.

A first mobile cut can negotiate plain JSON (`binary: false`, `compression: false`) and ignore MessagePack/compression.

## Keep-alive & timeouts

- Client sends a `ping` request periodically; a missing pong past the hang timeout closes the socket and triggers reconnect.
- `sessionId` is preserved across reconnects so the server can resume the session.
- Reconnect is automatic unless a request sets `allowReconnect: false`.

## Cross-references

- [account-api](account-api.md) — supplies `endpoint` + workspace token
- [client-protocol concept](../concepts/client-protocol.md)
- [data-model concept](../concepts/data-model.md) — `Doc`/`Tx`/`Hierarchy`
- [transaction-model concept](../concepts/transaction-model.md)
- [live-queries concept](../concepts/live-queries.md)
- [transactor service](../services/transactor.md)
- [core-types](../types/core-types.md)
- [authentication](../security/authentication.md)

## Gotchas

- The **token is in the URL path** (`/{token}`), not an `Authorization` header — different from the account and datalake HTTP APIs.
- Only the **workspace-scoped** token works here; the account-level token from `login` is rejected.
- Live updates are **id-less responses** — a client that only matches responses to outstanding request ids will silently drop the entire real-time stream. Handle id-less frames explicitly.
- `params` is a **positional array**, unlike the account API's named-object `params`.
- `findOne` is sugar for `findAll(..., { limit: 1 })`; there is no distinct server method semantics to rely on.
- Respect `rateLimit.retryAfter` — the transactor enforces request limits (e.g. `RATE_LIMIT_MAX` per `RATE_LIMIT_WINDOW`).
