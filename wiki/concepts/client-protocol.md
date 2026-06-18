# Transactor Client Protocol

> The WebSocket protocol a Huly client speaks to the **transactor**: handshake, request/response framing, serialization, the generic RPC methods (`loadModel`/`findAll`/`tx`/…), and the id-less live transaction broadcast.

## Where in code

- `foundations/core/packages/rpc/src/rpc.ts` -- wire types (`Request`, `Response`, `HelloRequest`, `HelloResponse`, `RateLimitInfo`) and `RPCHandler` serialization (JSON / MessagePack).
- `foundations/core/packages/client-resources/src/connection.ts` -- the `Connection` class: socket lifecycle, hello handshake, request↔response id matching, chunked results, ping/pong, reconnect, the RPC method wrappers.
- `foundations/core/packages/client/src/index.ts` -- `ClientSocket`, `ClientSocketReadyState`, `ClientFactoryOptions`, `pingConst`/`pongConst`, the `ClientSocketFactory` metadata hook.
- `foundations/core/packages/core/src/storage.ts` -- `DocumentQuery`, `FindOptions`, `FindResult`, query operators returned by `findAll`.

## Purpose

Huly is **transaction-sourced**, not a REST app. There is no per-feature endpoint. A client opens **one** WebSocket to the transactor for a workspace and then performs **every read** through `findAll`/`findOne` and **every write** through `tx`. The same socket also receives a live stream of transactions (yours and other users') so local state stays in sync without polling. This page documents that single channel; everything above it (LiveQuery, plugins) is built on it.

## Details

### Connection URL

The endpoint comes from the account service's `selectWorkspace` response (field `endpoint`), and the token is the workspace-scoped JWT. The `sessionId` query param is appended by `openConnection`:

```
ws://{endpoint}/{token}?sessionId={uuid}
```

`connect(url, handler, workspace, user, opt)` (bottom of `connection.ts`) constructs a `Connection`. The caller passes a `TxHandler` — the function that receives broadcast transactions — and `ClientFactoryOptions` (socket factory, binary/compression toggles, `onConnect`/`onHello`/`onUpgrade`/`onError` callbacks).

```typescript
export function connect (
  url: string,
  handler: TxHandler,          // receives id-less broadcast Tx[]
  workspace: WorkspaceUuid,
  user: PersonUuid,
  opt?: ClientFactoryOptions
): ClientConnection
```

On mobile/native, supply `opt.socketFactory` (or set `client.metadata.ClientSocketFactory`) so the platform's own WebSocket is used instead of the browser `WebSocket`.

### Handshake (Hello)

The socket's `onopen` immediately sends a `HelloRequest` with `id: -1`. It is always serialized as **plain JSON** (`serialize(helloRequest, false)`), because binary/compression mode is negotiated by the hello itself.

```typescript
interface HelloRequest extends Request<any[]> {
  binary?: boolean        // client wants MessagePack frames
  compression?: boolean   // client wants Snappy compression
}

interface HelloResponse extends Response<any> {
  binary: boolean         // server-confirmed binary mode
  reconnect?: boolean     // true => this is a reconnect, not a fresh connect
  serverVersion: string
  lastTx?: string         // id of the last applied transaction
  lastHash?: string       // last model hash (used to skip model reload)
  account: Account        // the resolved Account for this session
  useCompression?: boolean
}
```

`handleMsg` recognizes the hello by `resp.id === -1` and `resp.result === 'hello'`. It then:
- sets `binaryMode` / `compressionMode` from the response,
- clears the dial timer, stores `lastHash` and `account`,
- marks `helloReceived = true`, resolves all `onConnectHandlers`,
- replays any in-flight requests via `v.reconnect?.()`,
- fires `onConnect(Connected | Reconnected, lastTx, sessionId)` and starts the ping loop.

A special `resp.result?.state === 'upgrading'` (still `id === -1`) means the workspace is being upgraded: it fires `ClientConnectEvent.Maintenance`, sets `upgrading = true`, and applies a 3 s reconnect delay.

### Request / Response framing

```typescript
interface Request<P extends any[]> {
  id?: ReqId                                       // ReqId = string | number
  method: string
  params: P
  meta?: Record<string, string | number | boolean> // tracing metadata
  time?: number                                     // client send time
}

interface Response<R> {
  result?: R
  id?: ReqId            // matches Request.id; ABSENT => live broadcast
  error?: Status
  terminate?: boolean   // server is closing the session
  rateLimit?: RateLimitInfo
  chunk?: { index: number, final: boolean } // large FindResult split across frames
  time?: number; bfst?: number; queue?: number // server timing
}
```

Each outgoing request gets a monotonically increasing numeric `id` (`this.lastId++`), is stored in a `Map<ReqId, RequestPromise>`, and serialized with `meta: ctx.extractMeta()` and `time: Date.now()`. When a `Response` arrives with a matching `id`, `handleMsg` resolves (or rejects, on `error`) that promise and deletes it from the map.

```
client                                    transactor
  | Request{id:7, method:'findAll', ...} ----->|
  |<----- Response{id:7, result:[...docs]}      |   (id-matched reply)
  |                                             |
  |<----- Response{result:[Tx,Tx]}              |   (NO id => live broadcast)
```

### Serialization (`RPCHandler`)

`rpc.ts` `RPCHandler.protoSerialize` / `protoDeserialize`:

| Mode | Encode | Decode |
|------|--------|--------|
| JSON (default) | `JSON.stringify(obj, rpcJSONReplacer)` | `JSON.parse(str, rpcJSONReceiver)` |
| Binary | `Packr.pack(obj)` (MessagePack, `msgpackr`) | `Packr.unpack(bytes)` |

`rpcJSONReplacer`/`rpcJSONReceiver` preserve the non-standard shape of `FindResult` — an array that also carries `total` and `lookupMap` — by wrapping it as `{ dataType: 'TotalArray', total, lookupMap, value }`. Without this, the extra array properties would be lost across JSON.

**Compression:** when `compressionMode` is on (negotiated in hello, `ENABLE_COMPRESSION` on the server), inbound frames are decompressed with **Snappy** (`snappyjs` `uncompress`) before `readResponse`. Compression applies only after `helloReceived`.

A first mobile cut can request `binary: false, compression: false` and speak plain JSON.

### Core RPC methods

These are the entire data API — `Connection` exposes one wrapper per method, each just `sendRequest({ method, params })`:

| Method | Signature (params) | Purpose |
|--------|--------------------|---------|
| `loadModel` | `(last: Timestamp, hash?: string)` | Load model transactions → build the `Hierarchy`. Once at startup. Returns `Tx[]` or a `LoadModelResponse`. |
| `getAccount` | `()` | The session `Account` (cached from hello). |
| `findAll` | `(_class, query, options?)` | **All reads.** Mongo-style `DocumentQuery`, returns `FindResult<T>`. |
| `findOne` | (via LiveQuery / `findAll` with `limit:1`) | Single doc. |
| `tx` | `(tx: Tx)` | **All writes.** Submit a transaction; returns `TxResult`. |
| `searchFulltext` | `(query: SearchQuery, options)` | Full-text search → `SearchResult`. |
| `domainRequest` | `(domain, params, options?)` | Low-level per-domain operation. |
| `loadChunk`/`loadDocs`/`upload`/`clean`/`getDomainHash`/`closeChunk` | domain sync ops | Used by backup/migration tooling, not normal feature reads. |

`findAll` query operators (from `storage.ts` `QuerySelector`): `$in, $nin, $ne, $gt, $gte, $lt, $lte, $exists, $like, $regex, $options, $all, $size`, plus top-level `$search`. `FindOptions`: `limit, skip*, sort, lookup` (populate refs into `$lookup`), `projection, associations, total, showArchived`.

`Connection.findAll` also post-processes the result: it expands `result.lookupMap` into each doc's `$lookup`, and re-applies simple equality query values that the server may have stripped.

### Live transaction broadcast

The defining feature: a `Response` **with no `id`** is a server→client broadcast of transactions. `handleMsg` routes it to every registered `TxHandler`:

```typescript
} else {
  const txArr = Array.isArray(resp.result) ? (resp.result as Tx[]) : [resp.result as Tx]
  for (const tx of txArr) {
    if (tx?._class === core.class.TxModelUpgrade) { this.opt?.onUpgrade?.(); return }
  }
  this.handlers.forEach((handler) => { handler(...txArr) })
}
```

There is **no subscribe call** — connecting to a workspace subscribes you to its tx stream. The handler is typically `LiveQuery.tx`, which applies the transactions to cached query results so the UI reacts. A `TxModelUpgrade` tx triggers a full model reload instead.

### Chunked results

A large `FindResult` can be split across frames. Responses carry `chunk: { index, final }`; `handleMsg` accumulates `promise.chunks`, and on `chunk.final` sorts by index, concatenates, and rebuilds a single `FindResult` (re-attaching `total` and `lookupMap`) before resolving the request.

### Rate limiting

`RateLimitInfo` (`{ remaining, limit, current, reset, retryAfter? }`) rides on responses. When `remaining` drops below `limit/3`, the client raises a `slowDownTimer` that delays subsequent sends. A response with `remaining === 0` and a matching request id schedules a resend after `retryAfter` ms via `promise.sendData()`. Server defaults: `RATE_LIMIT_MAX=250` per `RATE_LIMIT_WINDOW=30000` ms.

### Keep-alive & timeouts

Constants in `connection.ts`:

| Constant | Value | Meaning |
|----------|-------|---------|
| `pingTimeout` | 10 s | Interval at which the client sends `ping`. |
| `hangTimeout` | 5 min | No response within this → close the socket and reconnect. |
| `dialTimeout` | 30 s | No hello within this → `onDialTimeout` + force reconnect. |

`ping`/`pong!` are the literal strings `pingConst`/`pongConst`. They may arrive as text, `ArrayBuffer`, or `Blob`; `checkArrayBufferPing` handles the binary cases. The server may also send `pingConst` to the client (`resp.result === pingConst`), which the client answers with a ping of its own.

### Reconnect & terminate

`onclose`/`onerror` call `scheduleOpen(ctx, force)`, which recreates the socket after a backoff `delay` (incremented up to 3 on errors). In-flight requests survive a reconnect: each `RequestPromise` keeps a `reconnect` hook that re-sends after the new hello. A `Response` with `terminate: true` (e.g. workspace archived/not-found) sets `closed = true`, closes the socket, and calls `onError(code)` — no reconnect.

## Cross-references

- [transaction-model](transaction-model.md) -- `Tx` shape and how transactions mutate documents.
- [data-model](data-model.md) -- `Doc`/`Class`/`Hierarchy` that `loadModel` builds.
- [live-queries](live-queries.md) -- the `TxHandler` that consumes the broadcast stream.
- [workspace-multitenancy](workspace-multitenancy.md) -- where `endpoint`/`token`/`workspace` come from.
- Service: [transactor](../services/transactor.md), [core-package](../services/core-package.md)
- API: [transactor-rpc](../api/transactor-rpc.md)
- Flows: [login-flow](../flows/login-flow.md), [model-load-flow](../flows/model-load-flow.md), [live-query-flow](../flows/live-query-flow.md)
- Types: [core-types](../types/core-types.md)

## Gotchas

- **The hello frame is always plain JSON**, even when binary mode is requested — binary only starts after `HelloResponse` confirms it. Decoding the hello with MessagePack will fail.
- **No `id` means broadcast, not error.** Don't treat an id-less `Response` as an orphaned reply; it is the live tx stream and must go to the `TxHandler`.
- `FindResult` is an array with extra `total`/`lookupMap` properties. Naive `JSON.stringify`/`parse` loses them — the `rpcJSONReplacer`/`rpcJSONReceiver` `TotalArray` wrapping exists precisely to round-trip them. A reimplementation must replicate this.
- Compression and binary are **independent and negotiated** — honor `HelloResponse.binary` and `useCompression`, not what you requested.
- `ping` is never stored in the request map (`data.method !== pingConst` guards), so don't expect a tracked promise for it.
- A reimplementation must match request ids exactly; an unmatched response id is logged and dropped (`unknown response id`).
