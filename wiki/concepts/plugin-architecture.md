# Plugin & Resource Registry

> How `@hcengineering/platform` turns every artifact in Huly — classes, components, icons, strings, config values — into a typed, string-addressable `Resource`, and how plugins are declared, implemented, and loaded lazily.

## Where in code

- `foundations/core/packages/platform/src/platform.ts` -- `plugin()`, `mergeIds()`, the `Id`/`Plugin`/`Resource`/`IntlString`/`StatusCode` brand types, `_parseId` separator.
- `foundations/core/packages/platform/src/ident.ts` -- `_parseId()` splits an `Id` into `{ component, kind, name }`.
- `foundations/core/packages/platform/src/resource.ts` -- `addLocation()`, `getResource()`, `getPlugin()` (`getResourcePlugin`), lazy plugin loading.
- `foundations/core/packages/platform/src/metadata.ts` -- `Metadata<T>`, `getMetadata()`, `setMetadata()`, `loadMetadata()`.
- `foundations/core/packages/platform/src/index.ts` -- re-exports; declares `URL` and `Asset = Metadata<URL>`.
- `foundations/core/packages/core/src/component.ts` -- example: `export default plugin(coreId, {...})` (the `core` plugin id object).
- `plugins/tracker/src/index.ts` -- example feature plugin id object (`plugin(trackerId, {...})`).
- `plugins/tracker-resources/src/index.ts` -- example implementation package (`default: async () => Resources`).
- `plugins/tracker-assets/src/index.ts` -- example assets package (`loadMetadata(tracker.icon, {...})`).

## Purpose

Huly is assembled from ~190 independent plugins. A plugin must be able to **reference** things owned by another plugin (a class, a UI component, an icon, a translatable string) at compile time, while the **actual value** of that thing (a Svelte component, an SVG URL, a localized message) is only known at runtime and varies per deployment.

The platform solves this with **Platform Resource Identifiers (PRIs)**: every referenceable artifact gets a stable, typed string id of the form `plugin:kind:name`. Code imports the id; the platform resolves the id to a real value lazily, on first use. This decouples *declaration* (a tiny, dependency-free id object) from *implementation* (the heavy code, loaded on demand) from *assets* (icons/strings, loaded per locale).

## Details

### The id format

Every id is a string branded as `Id = string & { __id: true }`, structured as three colon-separated segments:

```
plugin : kind : name
  │       │      └── resource name within the kind, e.g. "Issue"
  │       └───────── kind / namespace, e.g. "class", "component", "string", "icon"
  └───────────────── plugin id, e.g. "tracker"
```

`_parseId` (in `ident.ts`) splits on `_ID_SEPARATOR` (`':'`) and requires at least 3 segments:

```typescript
export function _parseId (id: Id): _IdInfo {
  const path = id.split(_ID_SEPARATOR) // ':'
  if (path.length < 3) {
    throw new PlatformError(new Status(Severity.ERROR, platform.status.InvalidId, { id }))
  }
  return { component: path[0] as Plugin, kind: path[1], name: path.slice(2).join(_ID_SEPARATOR) }
}
```

### Branded types — what a PRI can point at

All of these are `Id` with a phantom type parameter, so TypeScript knows what `getResource`/`translate`/`getMetadata` will hand back:

| Type | Definition | Points at | Resolved by |
|------|-----------|-----------|-------------|
| `Plugin` | `string & { __plugin: true }` | a plugin id | — |
| `Resource<T>` | `Id & { __resource: T }` | runtime value of type `T` (component, function…) | `getResource` |
| `Metadata<T>` | `Id & { __metadata: T }` | a config value of type `T` | `getMetadata` / `setMetadata` |
| `Asset` | `Metadata<URL>` (`= Id & {...}`) | an icon/image URL | `getMetadata` |
| `IntlString<P>` | `Id & { __intl_string: P }` | a translatable message with params `P` | `translate` |
| `StatusCode<P>` | `IntlString<P>` | an operation status / error code | `translate` |

`Ref<T extends Doc>` (a typed doc/class id) lives in `core`, not `platform`, but uses the same id-string discipline — class ids like `core:class:Doc` are PRIs too.

### Declaring a plugin: `plugin()`

A plugin's **public surface** is a single id object built with `plugin(pluginId, namespace)`. The namespace is a nested record whose leaves are `''` cast to a branded type; `plugin()` walks it and replaces each leaf with its full `plugin:kind:name` id via `identify`:

```typescript
// foundations/core/packages/core/src/component.ts
export const coreId = 'core' as Plugin

export default plugin(coreId, {
  class: {
    Doc: '' as Ref<Class<Doc>>,        // becomes "core:class:Doc"
    Tx: '' as Ref<Class<Tx>>,          // becomes "core:class:Tx"
    TxCreateDoc: '' as Ref<Class<TxCreateDoc<Doc>>>
  },
  // ... space, mixin, string, icon, status, metadata namespaces
})
```

```typescript
// plugins/tracker/src/index.ts
export const trackerId = 'tracker' as Plugin

const pluginState = plugin(trackerId, {
  class:     { Project: '' as Ref<Class<Project>>, Issue: '' as Ref<Class<Issue>> },
  mixin:     { IssueTypeData: '' as Ref<Mixin<Issue>> },
  component: { EditIssue: '' as AnyComponent, CreateIssue: '' as AnyComponent },
  icon:      { Issue: '' as Asset, Project: '' as Asset },
  string:    { /* IntlString ids */ }
})
export default pluginState
```

`identify` throws if a key would overwrite an already-set string, so id collisions are caught at startup. `mergeIds(plugin, ns, merge)` lets a second module (e.g. a model package) extend an existing plugin's id object with additional ids under the same plugin prefix.

### The three-package convention

A feature is split across three packages so that pulling in a *reference* never pulls in a *UI bundle*:

| Package | Example | Role | Registered via |
|---------|---------|------|----------------|
| `<name>` | `tracker` (`plugins/tracker/src/index.ts`) | **Declaration.** Exports the `plugin()` id object, interfaces, and `<name>Id`. Tiny, near-zero deps. | imported directly |
| `<name>-resources` | `tracker-resources` | **Implementation.** `export default async (): Promise<Resources>` mapping `kind → { name → value }` (Svelte components, action functions, presenters). | `addLocation(id, () => import(...))` |
| `<name>-assets` | `tracker-assets` | **Assets.** Calls `loadMetadata(plugin.icon, {...})` to register SVG sprite URLs, and `addStringsLoader(id, loader)` for translations. | imported for side effects |

```typescript
// plugins/tracker-resources/src/index.ts  — implementation
export default async (): Promise<Resources> => ({
  component: { Issues, MyIssues, EditIssue, CreateIssue /* … */ },
  activity:  { PriorityIcon, StatusIcon }
})
```

```typescript
// plugins/tracker-assets/src/index.ts  — assets
import { loadMetadata } from '@hcengineering/platform'
import tracker from '@hcengineering/tracker'
const icons = require('../assets/icons.svg') as string
loadMetadata(tracker.icon, { Issue: `${icons}#issue`, Project: `${icons}#project` /* … */ })
```

### Lazy resolution: `getResource`

A `Resource<T>` is never resolved until something calls `getResource`. The platform finds the owning plugin (segment 0), loads that plugin's `Resources` map (once), looks up `kind.name`, and caches the value:

```typescript
export async function getResource<T> (resource: Resource<T>): Promise<T> {
  const cached = cachedResource.get(resource)
  if (cached !== undefined) return cached
  const info = _parseId(resource)                      // { component, kind, name }
  let resources = loading.get(info.component) ?? loadPlugin(info.component)
  if (resources instanceof Promise) {
    resources = await resources
    loading.set(info.component, resources)
  }
  const value = resources[info.kind]?.[info.name]
  if (value === undefined) {
    throw new PlatformError(new Status(Severity.ERROR, platform.status.ResourceNotFound, { resource }))
  }
  cachedResource.set(resource, value)
  return value
}
```

Companion forms: `getResourceP` (sync if cached, else a Promise), `getResourceC` (callback style), `getResourcePlugin` (returns just the owning `Plugin` — the "getPlugin" of the registry).

### Location registration & plugin loading

`addLocation(plugin, loader)` registers *how* to load a plugin's resources; `loadPlugin` invokes the loader exactly once (memoized in the `loading` map) and unwraps the module's `default` export:

```typescript
const locations = new Map<Plugin, PluginLoader<Resources>>()
export function addLocation<R extends Resources> (plugin: Plugin, module: PluginLoader<R>): void {
  locations.set(plugin, module)
}
export function getPlugins (): Plugin[] { return Array.from(locations.keys()) }
```

The application bootstrap wires every plugin's loader (see `dev/prod/src/platform.ts`):

```typescript
addLocation(trackerId, async () => await import('@hcengineering/tracker-resources'))
// core has no UI resources, so it registers an empty loader:
addLocation(coreId, async () => ({ default: async () => ({}) }))
```

### Metadata — deployment-time config values

`Metadata<T>` is for values known only at runtime/deploy time (endpoint URLs, the current `locale`, asset URLs). Unlike `Resource`, metadata is set imperatively and read synchronously:

```typescript
export function setMetadata<T> (id: Metadata<T>, value: T): void { metadata.set(id, value) }
export function getMetadata<T> (id: Metadata<T>): T | undefined { return metadata.get(id) }
// loadMetadata(ids, data) bulk-sets a whole namespace, throwing if any key is missing.
```

`Asset` is just `Metadata<URL>`, which is why icons are registered with `loadMetadata` and read with `getMetadata`.

### Resolution flow

```
import id  ──► "tracker:component:EditIssue"  (compile-time, typed Resource<AnyComponent>)
                         │ getResource(id)
                         ▼
              _parseId → { component:"tracker", kind:"component", name:"EditIssue" }
                         │ loadPlugin("tracker")  (once)
                         ▼
              locations.get("tracker")()  ──► import("tracker-resources")
                         │ module.default()
                         ▼
              Resources = { component: { EditIssue: <SvelteComponent>, … } }
                         │ resources["component"]["EditIssue"]
                         ▼
              cache + return  <SvelteComponent>
```

## Cross-references

- [localization](localization.md) — `IntlString`, `translate`, `addStringsLoader`, `-assets` string loaders.
- [data-model](data-model.md) — `Ref`/`Class`/`Mixin` ids are PRIs registered into the `Hierarchy`.
- [model-layer](model-layer.md) — model packages use `mergeIds` and `Builder` to register classes for these ids.
- [platform-package](../services/platform-package.md) — package overview.
- [platform-types](../types/platform-types.md) — `Resource`, `Metadata`, `Status` type reference.

## Gotchas

- An id leaf is the empty string `''` until `plugin()`/`identify` runs. If you read a raw id object field before `plugin()` processes it (rare), you get `''`. Always import the `default` export, which is the processed object.
- `getResource` **throws `ResourceNotFound`** if the `-resources` package never registered that `name`, and **throws `NoLocationForPlugin`** if `addLocation` was never called for the plugin. A common bootstrap bug is forgetting one `addLocation`/`addStringsLoader` line.
- The id namespace (`kind`) must match the key in the `Resources` map exactly (`component`, `activity`, `function`, …). A `tracker:component:Foo` id resolves against `resources.component.Foo`, not `resources.components.Foo`.
- Declaration packages (`<name>`) must stay dependency-light. Importing UI code into them defeats the lazy-loading split and bloats every consumer.
- `name` may itself contain colons (`path.slice(2).join(':')`), so multi-segment names are legal; only the first two segments are structural.
- Resources and metadata caches are process-global maps. In a long-lived client there is no eviction — values resolve once and stay cached for the session.
