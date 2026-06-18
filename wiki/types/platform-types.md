# Platform types

> The branded-string id system and operation-status types from `@hcengineering/platform`: `Resource`, `Plugin`, `Metadata`, `Asset`, `IntlString`, `Status`, `Severity`, `PlatformError`.

## Where in code

- `foundations/core/packages/platform/src/platform.ts` -- `Id`, `Plugin`, `Resource`, `IntlString`, `StatusCode`, the `plugin()` / `mergeIds()` id factories
- `foundations/core/packages/platform/src/metadata.ts` -- `Metadata<T>`, `getMetadata` / `setMetadata`
- `foundations/core/packages/platform/src/index.ts` -- `Asset = Metadata<URL>`
- `foundations/core/packages/platform/src/status.ts` -- `Severity`, `Status`, `PlatformError`, `errorToStatus`
- `foundations/core/packages/platform/src/resource.ts` -- `getResource()` resolution + plugin loaders

## The branded-string id pattern

Almost everything in the platform is referenced by a string id of the form `plugin:kind:name` (e.g. `core.string.ClassLabel`, `workbench.icon.Add`). At runtime these are plain strings; at compile time they are **branded** with a phantom field that carries what the id points at:

```typescript
export type Id = string & { __id: true }              // 'plugin:kind:name'
export type Plugin = string & { __plugin: true }       // a plugin id
export type Resource<T> = Id & { __resource: T }        // resolves to a value of type T
export type IntlString<T extends Record<string, any> = any> = Id & { __intl_string: T } // i18n message id
export type Metadata<T> = Id & { __metadata: T }        // a configured value of type T
export type Asset = Metadata<URL>                       // an asset URL (icon/sprite)
export type StatusCode<T extends Record<string, any> = any> = IntlString<T> // status id == i18n id
```

The brand (`__resource`, `__metadata`, `__intl_string`, ...) is **never present at runtime** — it only lets the compiler know that resolving `Resource<MyComponent>` yields a `MyComponent`, that an `IntlString<{ count: number }>` needs a `count` param, etc.

Ids are produced by the `plugin()` factory, which walks a namespace object and replaces each leaf with `prefix:key:...`:

```typescript
export function plugin<N extends Namespace>(plugin: Plugin, namespace: N): N
export function mergeIds<N, M>(plugin: Plugin, ns: N, merge: M): N & M
```

## Definition

```typescript
// Resolution: Resource<T> is loaded lazily from its plugin and cached.
export async function getResource<T>(resource: Resource<T>): Promise<T>
export function getResourceP<T>(resource: Resource<T>): T | Promise<T> // sync if cached
export function getResourcePlugin<T>(resource: Resource<T>): Plugin

// Metadata: a configured value (URL, host, flag) keyed by Metadata<T>.
export function getMetadata<T>(id: Metadata<T>): T | undefined
export function setMetadata<T>(id: Metadata<T>, value: T): void
```

```typescript
// Operation status.
export enum Severity {
  OK = 'OK',
  INFO = 'INFO',
  WARNING = 'WARNING',
  ERROR = 'ERROR'
}

export class Status<P extends Record<string, any> = any> {
  readonly severity: Severity
  readonly code: StatusCode<P>  // also an i18n id for the human message
  readonly params: P            // params for the i18n template
  constructor (severity: Severity, code: StatusCode<P>, params: P)
}

// Error wrapper carrying a Status.
export class PlatformError<P extends Record<string, any>> extends Error {
  readonly status: Status<P>
  constructor (status: Status<P>)
}

// Normalizes any thrown value into a Status for RPC / telemetry.
export function errorToStatus (err: unknown): Status
export function unknownStatus (message: string): Status<any>
```

## Fields / Cases

### Id family

| Type | Brand | Resolves to | Resolved via |
|------|-------|-------------|--------------|
| `Plugin` | `__plugin` | (an identifier) | — |
| `Resource<T>` | `__resource: T` | a runtime value `T` (component, function) | `getResource()` |
| `Metadata<T>` | `__metadata: T` | a configured value `T` | `getMetadata()` |
| `Asset` | (= `Metadata<URL>`) | an icon/sprite URL | `getMetadata()` |
| `IntlString<P>` | `__intl_string: P` | a translated string | i18n loader / `translate()` |
| `StatusCode<P>` | (= `IntlString<P>`) | a status message | i18n |

### `Severity`

| Case | Value | Meaning |
|------|-------|---------|
| `OK` | `'OK'` | Success. |
| `INFO` | `'INFO'` | Informational. |
| `WARNING` | `'WARNING'` | Non-fatal warning. |
| `ERROR` | `'ERROR'` | Failure. |

### Common platform `StatusCode`s (from `platform.status`)

| Code | Params | Typical HTTP |
|------|--------|--------------|
| `Unauthorized` | — | 401 |
| `Forbidden` | — | 403 |
| `TokenExpired` | — | 401 |
| `WorkspaceNotFound` | `{ workspaceUuid?, workspaceName?, workspaceUrl? }` | — |
| `AccountNotFound` | `{ account? }` | — |
| `ResourceNotFound` | `{ resource }` | — |
| `UnknownError` | `{ message }` | 500 |

## Usage

```typescript
import { getResource, getMetadata, setMetadata, Status, Severity, PlatformError } from '@hcengineering/platform'
import platform from '@hcengineering/platform'

// Resolve a lazily-loaded component/function by its Resource id:
const View = await getResource(tracker.component.IssuePresenter)

// Read/write configured values:
setMetadata(platform.metadata.locale, 'en')
const locale = getMetadata(platform.metadata.locale)

// Raise a typed error:
throw new PlatformError(
  new Status(Severity.ERROR, platform.status.Unauthorized, {})
)

// Normalize a caught error into a Status for the wire:
try { /* ... */ } catch (err) {
  const status = errorToStatus(err)
}
```

```typescript
// Defining a plugin's ids (the branding flows from the `as` casts):
export default plugin('myPlugin' as Plugin, {
  class: { Widget: '' as Ref<Class<Widget>> },
  string: { Title: '' as IntlString },
  icon: { Logo: '' as Asset },
  component: { WidgetView: '' as AnyComponent }
})
```

## Related types

- Ids reference model classes: [core-types](core-types.md) (`Ref<Class<T>>`).
- `StatusCode` doubles as an i18n message id (see localization).

## Cross-references

- [plugin-architecture concept](../concepts/plugin-architecture.md)
- [localization concept](../concepts/localization.md)
- [model-layer concept](../concepts/model-layer.md)
- [platform-package service](../services/platform-package.md)

## Gotchas

- All ids are **plain strings at runtime**; the brand fields exist only for the type checker. You construct one with `'' as Resource<T>` (the empty string is replaced by `plugin()` at module init).
- `Resource<T>` resolves **asynchronously and lazily** — the owning plugin is loaded on first `getResource()`, then both the plugin and the resolved value are cached. Use `getResourceP()` when you want the cached value synchronously.
- `Metadata` is just a typed key into a global map; nothing is loaded — you must `setMetadata`/`loadMetadata` before reading, or `getMetadata` returns `undefined`.
- `StatusCode<P>` IS an `IntlString<P>`: the status code and its human-readable (translated) message share the same id. `Status.params` feeds the i18n template.
- `PlatformError` wraps a `Status`; prefer `errorToStatus(err)` over manual `instanceof` chains — it unwraps `PlatformError`, bare `Status`, status-like objects, and `{ status }` envelopes.
- `Asset` is exactly `Metadata<URL>` — icons resolve via `getMetadata`, not `getResource`.
