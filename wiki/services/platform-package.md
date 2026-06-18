# @hcengineering/platform

> The plugin/resource registry: `plugin()` to mint namespaced ids, `getResource` to lazily load implementations, plus `Metadata`, `IntlString` localization, and the `Status`/`PlatformError` error system.

## Where in code

- `foundations/core/packages/platform/src/index.ts` -- barrel; also defines `URL` and `Asset = Metadata<URL>`.
- `foundations/core/packages/platform/src/platform.ts` -- `plugin()`, `mergeIds()`, the `Id`/`Plugin`/`Resource`/`IntlString`/`StatusCode` brand types, platform status codes.
- `foundations/core/packages/platform/src/resource.ts` -- `getResource`, `addLocation`, lazy plugin loading.
- `foundations/core/packages/platform/src/metadata.ts` -- `Metadata<T>`, `getMetadata`/`setMetadata`/`loadMetadata`.
- `foundations/core/packages/platform/src/i18n.ts` -- `translate`, `translateCB`, `addStringsLoader`.
- `foundations/core/packages/platform/src/status.ts` -- `Status`, `PlatformError`, `Severity`, helpers.
- `foundations/core/packages/platform/src/event.ts` -- `setPlatformStatus`, `monitor`, event listeners.
- `foundations/core/packages/platform/src/ident.ts` -- `_parseId` (splits `plugin:kind:name`).

## Purpose

Huly is plugin-based. Every plugin declares a typed namespace of **ids** (class refs, component resources, intl strings, metadata, status codes) via `plugin()`. These ids are compile-time strings of the form `plugin:kind:name`. At runtime, `getResource` resolves a `Resource<T>` id to its actual implementation by lazily importing the owning plugin's resource module. This indirection lets the model reference UI components, functions, icons, and strings without static imports — enabling code splitting and deferred loading.

`Metadata<T>` holds deployment-time config (URLs, tokens, feature flags). `IntlString` ids drive ICU localization. `Status`/`PlatformError` provide a structured, i18n-keyed error model used across the platform.

## Public API

### Identity & plugins (`platform.ts`)

| Export | Kind | Notes |
|--------|------|-------|
| `Id` | type | `string & { __id: true }` — base for all platform ids. |
| `Plugin` | type | `string & { __plugin: true }` — plugin id. |
| `Resource<T>` | type | `Id & { __resource: T }` — id of a loadable implementation of type `T`. |
| `IntlString<T>` | type | `Id & { __intl_string: T }` — localizable string id with typed params. |
| `StatusCode<T>` | type | `IntlString<T>` doubling as an error/status code. |
| `Namespace` | type | `Record<string, Record<string, string>>`. |
| `plugin(plugin, namespace)` | function | `<N extends Namespace>(plugin: Plugin, namespace: N) => N` — fills each leaf with `plugin:kind:name`. |
| `mergeIds(plugin, ns, merge)` | function | Extend an existing plugin namespace with additional ids. |
| `getEmbeddedLabel(str)` | function | Wrap a literal string as an `IntlString` (no translation lookup). |

### Resources (`resource.ts`)

| Export | Signature | Notes |
|--------|-----------|-------|
| `getResource<T>(resource)` | `(Resource<T>) => Promise<T>` | Resolve id → implementation; lazy-loads + caches the plugin. |
| `getResourceP<T>(resource)` | `(Resource<T>) => T \| Promise<T>` | Sync if cached, else promise. |
| `getResourceC<T>(resource, cb)` | callback form | Invokes `cb(value)` once resolved. |
| `addLocation<R>(plugin, loader)` | `(Plugin, PluginLoader<R>) => void` | Register a plugin's lazy resource module. |
| `getPlugins()` | `() => Plugin[]` | List registered plugins. |
| `getResourcePlugin(resource)` | `(Resource<T>) => Plugin` | Owning plugin of a resource id. |
| `Resources` / `PluginModule<R>` / `PluginLoader<R>` | types | Resource module shapes. |

### Metadata (`metadata.ts`)

| Export | Signature | Notes |
|--------|-----------|-------|
| `Metadata<T>` | type | `Id & { __metadata: T }` — config slot. |
| `getMetadata<T>(id)` | `(Metadata<T>) => T \| undefined` | |
| `setMetadata<T>(id, value)` | `(Metadata<T>, T) => void` | |
| `loadMetadata(ids, data)` | bulk set, throws on missing key | |

### Localization (`i18n.ts`)

| Export | Signature | Notes |
|--------|-----------|-------|
| `translate<P>(message, params, language?, skipError?)` | `=> Promise<string>` | ICU-format an `IntlString<P>`; falls back to the id on failure. |
| `translateCB<P>(message, params, language, resolve, skipError?)` | sync-if-cached callback | |
| `addStringsLoader(plugin, loader)` | register per-plugin string loader | |

### Errors / status (`status.ts`, `event.ts`)

| Export | Kind | Notes |
|--------|------|-------|
| `Severity` | enum | `OK`, `INFO`, `WARNING`, `ERROR`. |
| `Status<P>` | class | `{ severity, code: StatusCode<P>, params: P }`. |
| `PlatformError<P>` | class | `Error` wrapping a `Status`; `.status` property. |
| `OK` / `ERROR` / `UNAUTHORIZED` | const | Pre-built statuses. |
| `unknownStatus(message)` / `unknownError(err)` / `errorToStatus(err)` | functions | Coerce into `Status`. |
| `setPlatformStatus(status)` | function | Broadcast a status as a platform event. |
| `monitor<T>(status, promise)` | function | Wrap a promise: emit status, then `OK`/error. |

The default export `platform` declares the platform's own `status` codes (`Unauthorized`, `TokenExpired`, `WorkspaceNotFound`, `InvalidPassword`, …) and `metadata` (`locale`, `LoadHelper`).

## Usage

```typescript
import platform, {
  plugin,
  type Plugin,
  type Resource,
  type IntlString,
  type Metadata,
  getResource,
  getMetadata,
  setMetadata,
  translate,
  Status,
  Severity,
  PlatformError
} from '@hcengineering/platform'

// 1. Declare a plugin namespace — leaves become 'myplugin:kind:name'.
const myPluginId = 'myplugin' as Plugin
export default plugin(myPluginId, {
  component: {
    Editor: '' as Resource<any>
  },
  string: {
    Title: '' as IntlString
  },
  metadata: {
    ApiUrl: '' as Metadata<string>
  }
})

// 2. Configure metadata at startup.
setMetadata(myPlugin.metadata.ApiUrl, 'https://huly.example.com')

// 3. Lazily resolve a component implementation.
const Editor = await getResource(myPlugin.component.Editor)

// 4. Localize.
const label = await translate(myPlugin.string.Title, {})

// 5. Structured errors.
throw new PlatformError(new Status(Severity.ERROR, platform.status.Unauthorized, {}))
```

## Cross-references

- [core-package](core-package.md) -- `Class`/`Doc` metadata fields are typed as `IntlString`/`Asset`.
- [client-package](client-package.md) -- the `client` plugin declares its `GetClient` resource + metadata here.
- [ui-package](ui-package.md) -- `showPopup` accepts `Resource<...>` component ids resolved via `getResource`.
- Concepts: [plugin-architecture](../concepts/plugin-architecture.md), [localization](../concepts/localization.md).
- Types: [platform-types](../types/platform-types.md).

## Gotchas

- **`plugin()` mutates ids in place by convention.** Declared leaves use `'' as Resource<T>`; `plugin()` overwrites each empty string with the real `plugin:kind:name`. Reusing a key across `plugin`/`mergeIds` throws (`'identify' overwrites '<key>'`).
- **`getResource` is async and lazy.** First call for a plugin triggers a dynamic import of its resource module; subsequent calls hit the `cachedResource` map. Use `getResourceP`/`getResourceC` to avoid an unnecessary promise when already cached.
- **A missing resource throws `PlatformError`** with `platform.status.ResourceNotFound`, and a missing plugin location throws `NoLocationForPlugin` — register modules with `addLocation` before resolving.
- **`translate` never throws on a bad id.** It returns the id string itself (and caches a `Status`) so the UI degrades gracefully instead of crashing.
- **Metadata is a flat global map.** `setMetadata` is process-wide; there is no scoping per workspace beyond what callers encode in the value.
