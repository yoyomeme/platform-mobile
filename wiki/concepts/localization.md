# Localization — IntlString & platform i18n

> Translatable text in Huly is an `IntlString` PRI (`plugin:string:Name`); the platform resolves it to a locale-specific, parameterized message via `translate`, with each plugin's messages supplied by an `-assets` package through `addStringsLoader`.

## Where in code

- `foundations/core/packages/platform/src/i18n.ts` -- `translate`, `translateCB`, `addStringsLoader`, `loadPluginStrings`, the `Loader` type, translation/cache maps.
- `foundations/core/packages/platform/src/platform.ts` -- `IntlString<P>`, `StatusCode<P>`, `getEmbeddedLabel`, `_EmbeddedId`, `_ID_SEPARATOR`.
- `foundations/core/packages/platform/src/ident.ts` -- `_parseId` (splits `plugin:string:Name`).
- `foundations/core/packages/platform/src/metadata.ts` -- `platform.metadata.locale` set via `setMetadata`.
- `plugins/contact-assets/src/index.ts` / `plugins/tracker-assets/src/index.ts` -- example `-assets` packages calling `addStringsLoader` / `loadMetadata`.
- `plugins/tracker-assets/lang/en.json` (and `de/fr/ja/…`) -- the message catalog files a loader returns.

## Purpose

A plugin declares the *existence* of a string at compile time but must not embed its translations. `IntlString` lets code reference a message by id (`tracker:string:Issues`), while the actual text — per language, with ICU placeholder substitution — is loaded lazily from JSON catalogs registered by the feature's `-assets` package. This is the same declare/implement/asset split as the rest of the [plugin architecture](plugin-architecture.md), specialized for text.

## Details

### IntlString and StatusCode

```typescript
// platform.ts
export type IntlString<T extends Record<string, any> = any> = Id & { __intl_string: T }
export type StatusCode<T extends Record<string, any> = any> = IntlString<T>  // error codes are i18n ids too
```

The type parameter `T` is the message's parameter shape, so `translate(msg, params)` is type-checked against the placeholders the message expects. A `StatusCode` *is* an `IntlString` — that's why a `Status`'s `code` can be translated directly into a human message.

String ids follow the standard PRI form and live under the `string` kind of a plugin's id object:

```typescript
// inside plugins/tracker/src/index.ts → plugin(trackerId, { string: { Issues: '' as IntlString, … } })
tracker.string.Issues   // === "tracker:string:Issues"
```

### Registering messages: addStringsLoader

A `Loader` is `(locale) => Promise<catalog>`. The `-assets` package registers one per plugin; the loader dynamically imports the matching JSON for the requested language:

```typescript
// app bootstrap (e.g. dev/prod/src/platform.ts)
addStringsLoader(trackerId, async (lang: string) =>
  await import(`@hcengineering/tracker-assets/lang/${lang}.json`))
addStringsLoader(contactId, async (lang: string) =>
  await import(`@hcengineering/contact-assets/lang/${lang}.json`))
```

```typescript
// platform/src/i18n.ts
export type Loader = (locale: string) => Promise<Record<string, string | Record<string, string>>>
const loaders = new Map<Plugin, Loader>()
export function addStringsLoader (plugin: Plugin, loader: Loader): void { loaders.set(plugin, loader) }
```

The catalog is keyed by `kind` then `name`, mirroring the id structure (`plugin:string:Issues` → `catalog.string.Issues`):

```json
// plugins/tracker-assets/lang/en.json
{ "string": { "Issues": "Issues", "MyIssues": "My issues", "ViewIssue": "View issue" } }
```

The same `-assets` package also registers icons via `loadMetadata(plugin.icon, …)` — strings and assets are bundled together but use different mechanisms (`addStringsLoader` for text, `loadMetadata`/`Asset` for URLs). See [plugin-architecture](plugin-architecture.md).

### Resolving: translate

`translate(message, params, language?, skipError?)` is the workhorse. It picks the locale, consults a compiled-format cache, parses the id, loads the right plugin catalog (lazily, once), and formats with `intl-messageformat` (ICU):

```typescript
export async function translate<P extends Record<string, any>> (
  message: IntlString<P>, params: P, language?: string, skipError?: boolean
): Promise<string> {
  const locale = language ?? getMetadata(platform.metadata.locale) ?? 'en'
  const localCache = cache.get(locale) ?? new Map()
  const compiled = localCache.get(message)
  if (compiled !== undefined) {
    return compiled instanceof Status ? message : compiled.format(params)
  }
  const id = _parseId(message)                       // { component, kind: 'string', name }
  if (id.component === _EmbeddedId) return id.name   // embedded labels short-circuit
  const translation = getCachedTranslation(id, locale)
      ?? (await getTranslation(id, locale, skipError)) ?? message
  if (translation instanceof Status) { localCache.set(message, translation); return message }
  const compiledNew = new IntlMessageFormat(translation, locale, undefined, { ignoreTag: true })
  localCache.set(message, compiledNew)
  return compiledNew.format(params)
}
```

Two caches keep this fast: `translations` (locale → plugin → raw catalog) and `cache` (locale → message id → compiled `IntlMessageFormat`). The current locale comes from `platform.metadata.locale` (set at startup with `setMetadata(platform.metadata.locale, 'en')`).

### translateCB — synchronous-if-cached

`translateCB(message, params, language, resolve, skipError?)` is the callback variant for UI hot paths: if the message's catalog is already loaded it formats and calls `resolve` synchronously; otherwise it falls through to the async `translate` and resolves later. This avoids a Promise microtask when the string is already cached (common after first render).

### Fallbacks and missing strings

The pipeline degrades gracefully rather than throwing:

| Situation | Behavior |
|-----------|----------|
| No loader registered for the plugin | `Status(NoLoaderForStrings)`; `translate` returns the **raw id** as fallback text. |
| Loader throws for `locale` | retries with `'en'`; if that also fails, returns a `Status` and the raw id. |
| Key missing in the locale catalog | `getTranslation` loads the **English** catalog (`englishTranslationsForMissing`) and uses the English string for that key. |
| Compile/format error | caches the failure, notifies the platform, returns the raw id. |

So an untranslated or misconfigured string surfaces as its id (e.g. `tracker:string:Issues`) in the UI — a visible signal, never a crash.

### Embedded labels

`getEmbeddedLabel(str)` builds an id `embedded:embedded:<str>` so arbitrary literal text can be passed anywhere an `IntlString` is expected; `translate` detects the `_EmbeddedId` component and returns the literal `name` unchanged (no catalog lookup):

```typescript
export function getEmbeddedLabel (str: string): IntlString {
  return (_EmbeddedId + ':' + _EmbeddedId + ':' + str) as IntlString
}
```

### Bulk preload

`loadPluginStrings(locale, force?)` iterates every registered loader and pre-populates the `translations` cache for a locale — used to warm all catalogs up front (e.g. on a language switch, with `force` to clear the compiled-format cache).

### End-to-end flow

```
"tracker:string:Issues" (IntlString, compile-time)
        │ translate(id, params)
        ▼
locale = getMetadata(platform.metadata.locale) ?? 'en'
        │ compiled-format cache hit? ── yes ──► IntlMessageFormat.format(params) ──► text
        │ no
        ▼
_parseId → { component:'tracker', kind:'string', name:'Issues' }
        │ loaders.get('tracker')('en')  →  import('tracker-assets/lang/en.json')   (once)
        ▼
catalog.string.Issues = "Issues"
        │ new IntlMessageFormat("Issues", 'en')  (cache it)
        ▼
"Issues"   (or English fallback / raw id on miss)
```

## Cross-references

- [plugin-architecture](plugin-architecture.md) — `IntlString` is a PRI; `addStringsLoader`/`loadMetadata` parallel `addLocation`/`getResource`.
- [model-layer](model-layer.md) — `@Prop`/`@UX` labels and `pluralLabel` are `IntlString`s baked into the model.
- [transaction-model](transaction-model.md) — `Status`/`StatusCode` returned from operations resolve through `translate`.
- [platform-types](../types/platform-types.md) — `IntlString`, `StatusCode`, `Status` type reference.
- [platform-package](../services/platform-package.md) — package overview.

## Gotchas

- The locale comes from `platform.metadata.locale` via `getMetadata`. If it was never `setMetadata`-d, every `translate` defaults to `'en'` — a silent monolingual fallback.
- A missing **key** falls back to English text, but a missing **loader** falls back to the raw id string. The two failure modes look different in the UI; check that `addStringsLoader` ran for the plugin.
- The catalog JSON must nest under the `kind` (`{ "string": { … } }`). A flat `{ "Issues": … }` will not resolve `tracker:string:Issues`.
- `IntlMessageFormat` is constructed with `{ ignoreTag: true }`, so XML/HTML-like tags in messages are treated as literal text, not ICU markup.
- `translate` returns the raw id (not an error) when resolution fails. Treat an id-looking string in the UI as a localization bug, not valid content.
- Compiled formats are cached per `(locale, message)`. After editing a catalog at runtime you must `loadPluginStrings(locale, true)` to clear the compiled cache; otherwise stale formats persist for the session.
