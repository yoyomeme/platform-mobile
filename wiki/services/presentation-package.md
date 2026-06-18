# @hcengineering/presentation

> The Svelte UI's gateway to the data layer. `getClient()` returns the singleton `TxOperations & Client`; `createQuery()` makes a component-scoped reactive query; metadata slots hold the workspace's URLs/token; plus file, search, and pipeline utilities used by every feature plugin.

## Where in code

- `packages/presentation/src/utils.ts` -- `getClient`, `setClient`, `createQuery`, the Svelte `LiveQuery`, `refreshClient`, `onClient`, `getCurrentWorkspaceUrl`.
- `packages/presentation/src/plugin.ts` -- the `presentation` plugin: metadata (`UploadURL`, `DatalakeUrl`, `Token`, `Endpoint`, `WorkspaceUuid`, `CollaboratorUrl`, `PreviewUrl`, `PulseUrl`, …), classes, status codes.
- `packages/presentation/src/pipeline.ts` -- `PresentationPipeline` middleware chain (query optimization, plugin middleware).
- `packages/presentation/src/file.ts`, `image.ts`, `preview.ts` -- blob URL + upload helpers.
- `packages/presentation/src/index.ts` -- barrel re-exporting the above.

## Purpose

Feature plugins are written in Svelte and must not each open their own connection. `@hcengineering/presentation` owns a single configured `Client` for the active workspace and exposes it through `getClient()`. The returned object is a proxy that behaves as both a `Client` (reads) and `TxOperations` (writes), so a component can call `getClient().createDoc(...)` directly.

It also adapts the low-level `@hcengineering/query` engine into a Svelte-friendly `LiveQuery`/`createQuery()` that auto-unsubscribes on component destroy, runs queries through a middleware **pipeline** (optimization + per-plugin presentation middleware), and stores the workspace's deployment metadata (file/datalake/preview/pulse URLs, token, endpoint) for use by file and media helpers.

## Public API

### Client access (`utils.ts`)

| Export | Signature | Notes |
|--------|-----------|-------|
| `getClient()` | `() => TxOperations & Client` | The singleton client proxy: reads (`findAll`/`findOne`) + writes (`createDoc`/`updateDoc`/`addCollection`/…). |
| `setClient(client)` | `(Client) => Promise<void>` | Install/replace the active client; builds the pipeline + live-query layers. Called after login/workspace select. |
| `refreshClient(clean)` | `(boolean) => Promise<void>` | Force all live queries to re-fetch (e.g. after reconnect/`Refresh`). |
| `onClient(listener)` | `(OnClientListener) => void` | Run a callback whenever the client is (re)set; fires immediately if already set. |
| `addRefreshListener(fn)` | register refresh hook | |
| `purgeClient()` / `closeClient()` | lifecycle teardown | |

### Reactive queries (`utils.ts`)

| Export | Signature | Notes |
|--------|-----------|-------|
| `createQuery(dontDestroy?)` | `(boolean?) => LiveQuery` | Make a query bound to the current Svelte component (auto-unsubscribe via `onDestroy`). Pass `true` for a global query that survives component teardown. |
| `LiveQuery` (class) | `query<T>(_class, query, callback, options?) => boolean` | Run/refresh a subscription; `callback(result: FindResult<T>)`. `unsubscribe()` releases it. Re-runs only when args change. |

### Workspace metadata (`plugin.ts`)

Read with `getMetadata(presentation.metadata.X)`:

| Metadata | Type | Holds |
|----------|------|-------|
| `Token` | `Metadata<string>` | Workspace-scoped JWT. |
| `Endpoint` | `Metadata<string>` | Transactor WS URL. |
| `WorkspaceUuid` / `WorkspaceName` / `WorkspaceDataId` | metadata | Active workspace identity. |
| `UploadURL` / `DatalakeUrl` / `HulylakeUrl` | metadata | File upload + blob storage. |
| `PreviewUrl` / `CollaboratorUrl` / `PulseUrl` | metadata | Thumbnails, collaborative editing, push. |
| `ModelVersion` / `FrontVersion` | metadata | Compatibility. |
| `ClientHook` / `FileStorage` | metadata | Injection points (intercept tx/find; pluggable storage). |
| `DisabledFeatures` | `Metadata<Set<string>>` | Feature flags (see `isDisabled`). |

| Helper | Notes |
|--------|-------|
| `getCurrentWorkspaceUrl()` | Active workspace url (from store or location). |
| `isDisabled(feature?)` | Check `DisabledFeatures`. |
| `remToPx(rem)` | Layout helper. |

File/blob helpers live in `file.ts`/`image.ts`/`preview.ts` (resolve a `Ref<Blob>` to a download URL via `DatalakeUrl`/`PreviewUrl`, upload form-data/multipart).

## Usage

```svelte
<script lang="ts">
  import { getClient, createQuery } from '@hcengineering/presentation'
  import { type FindResult, type Ref, SortingOrder, generateId } from '@hcengineering/core'

  const client = getClient()                  // TxOperations & Client
  const query = createQuery()                  // auto-unsubscribes on destroy

  let issues: FindResult<any> | undefined

  // Reactive: re-runs whenever projectId changes; callback fires on every matching tx.
  $: query.query(
    tracker.class.Issue as Ref<any>,
    { space: projectId },
    (res) => { issues = res },
    { sort: { modifiedOn: SortingOrder.Descending }, limit: 50 }
  )

  async function add(title: string) {
    await client.createDoc(myPlugin.class.Thing, projectId, { title }, generateId())
  }
</script>
```

## Cross-references

- [core-package](core-package.md) -- `TxOperations`/`Client`/`Doc` returned by `getClient()`.
- [query-package](query-package.md) -- the low-level `LiveQuery` engine this wraps.
- [client-package](client-package.md) -- produces the `Client` passed to `setClient`.
- [ui-package](ui-package.md) -- components rendered against this data.
- Concepts: [live-queries](../concepts/live-queries.md), [client-protocol](../concepts/client-protocol.md), [ui-framework](../concepts/ui-framework.md).

## Gotchas

- **`getClient()` is a proxy, not a stored instance.** It forwards every call to the current underlying client (and patches `getHierarchy()` through a sub-proxy), so it stays valid across reconnects/`setClient` without callers re-fetching it.
- **Use `createQuery()` inside components, raw `@hcengineering/query` elsewhere.** `createQuery()` registers an `onDestroy` unsubscribe — calling it outside a Svelte component lifecycle leaks (or pass `dontDestroy: true` and manage `unsubscribe()` yourself).
- **`query.query(...)` is idempotent on identical args.** It returns `false` and skips work when `_class`/query/callback/options are deep-equal to the previous call (it stringifies the callback) — define stable callbacks to avoid missed refreshes.
- **Metadata must be set before `setClient`-dependent helpers run.** File/preview/pulse URLs and the token come from `presentation.metadata.*`, populated from the account service's `WorkspaceLoginInfo` + front `config.json` during bootstrap.
- **A middleware pipeline sits in front of live queries.** `setClient` builds `PresentationPipeline` (query optimization + plugin middleware) between the UI `LiveQuery` and the raw client; a plugin can intercept queries via `PresentationMiddlewareFactory`.
