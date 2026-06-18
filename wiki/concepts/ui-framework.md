# UI Framework & Design System

> The Svelte UI stack: `packages/ui` (components + the 24-color palette), `packages/presentation` (`getClient`/`createQuery` data wrappers), and `packages/theme` (CSS-variable light/dark themes). Plus the design tokens — colors, type, spacing, radius, elevation — a mobile client should mirror.

## Where in code

- `packages/ui/src/colors.ts` -- the named accent palette (`whitePalette`/`darkPalette`), `ColorDefinition`, `PaletteColorIndexes`, and the `getPlatformColor*` / `getPlatformColorForText` / `hashCode` helpers.
- `packages/ui/src/components/` -- the shared Svelte widgets (Button, Label, EditBox, panels, popups, tooltips, …) consumed by every plugin.
- `packages/presentation/src/utils.ts` -- `getClient()`, `createQuery()`, the Svelte `LiveQuery` wrapper, `setClient`.
- `packages/theme/styles/_colors.scss`, `_lumia-colors.scss`, `_vars.scss`, `global.scss`, `common.scss` -- CSS-variable definitions under `.theme-dark` / `.theme-light`, plus spacing/radius/font vars.
- `packages/theme/src/index.ts` -- `Theme`/`InvertedTheme` components, `themeStore`, `getCurrentTheme`, `isThemeDark`.

## Purpose

Huly's UI is a single Svelte design system shared by ~190 plugins. Three packages compose it:
- **`ui`** — presentation-agnostic components and the color math (avatar/label colors, theme-aware hex).
- **`presentation`** — the data layer Svelte components talk to: one `getClient()` for reads/writes, `createQuery()` for reactive subscriptions.
- **`theme`** — the visual tokens, expressed as CSS variables that flip between light and dark.

A native mobile client doesn't run Svelte, but it must **reproduce these tokens** so it looks like Huly. This page documents the structure and the concrete token values to port.

## Details

### `packages/presentation` — the data wrappers

Svelte components never touch the transactor directly. They use:

```typescript
// One shared, hooked client (TxOperations + Client) for the whole UI session
export function getClient (): TxOperations & Client

// A reactive query handle; auto-unsubscribes on component destroy
export function createQuery (dontDestroy?: boolean): LiveQuery
```

`getClient()` returns a `UIClient` (a `TxOperations` over the live pipeline) — use it for `findOne`/`findAll` one-offs and for writes (`createDoc`, `updateDoc`, `addCollection`, …). `createQuery()` returns a thin Svelte-lifecycle wrapper around `@hcengineering/query`'s `LiveQuery`:

```svelte
<script lang="ts">
  import { createQuery } from '@hcengineering/presentation'
  import tracker from '@hcengineering/tracker'

  const query = createQuery()           // registers onDestroy → unsubscribe
  let issues = []
  $: query.query(tracker.class.Issue, { space }, (res) => { issues = res })
</script>
```

The wrapper's `query()` short-circuits when `_class`/`query`/`options`/`callback` are deep-equal to the previous call (`needUpdate`), and tears down the previous subscription before starting a new one. On client recreation it re-subscribes (`refreshClient`). `setClient` wires the `LiveQuery` instances and registers the connection's `notify` handler so broadcasts flow to subscriptions. See [live-queries](live-queries.md).

### `packages/ui` — components and the color palette

`ui` provides the building-block Svelte components and the **color system** in `colors.ts`. The palette is 24 named accent colors, each a `ColorDefinition`:

```typescript
interface ColorDefinition {
  name: string
  color: string        // base hex
  icon?: string        // icon-tint variant
  iconText?: string
  title?: string       // darker title variant
  number?: string
  background?: string  // solid or gradient
}
```

There are paired `whitePalette` (light) and `darkPalette` (dark, HSL-shifted) arrays, indexed by `PaletteColorIndexes`. Pick a stable color for any entity by hashing its id/text:

```typescript
getPlatformColorForText(text: string, darkTheme: boolean): string
getPlatformColorDef(hash: number | number[], darkTheme: boolean): ColorDefinition
hashCode(text: string): number   // -> index into the 24-color palette
```

The 24 names (order = `PaletteColorIndexes`): Firework, Watermelon, Pink, Fuchsia, Lavander, Mauve, Heather, Orchid, Blueberry, Arctic, Sky, Cerulean, Waterway, Ocean, Turquoise, Houseplant, Crocodile, Grass, Sunshine, Orange, Pumpkin, Cloud, Coin, Porpoise. Base light hexes: `D15045, DB877D, EF86AA, EB5181, DC85F5, 925CB1, 7B86C6, 8458E3, 6260C2, 8BB0F9, 4CA6EE, 5195D7, 1467B3, 167B82, 58B99D, 46A44F, 709A3F, 83AF12, D29840, D27540, BF5C24, A1A1A1, 939395, 758595`. **Avatar/label rule:** `hash(id) % 24`.

### `packages/theme` — CSS-variable themes

Themes are CSS variables scoped under `.theme-dark` / `.theme-light` (defined in `_colors.scss`; a `lumia` variant in `_lumia-colors.scss`). The `Theme` Svelte component sets the body class; `themeStore`/`getCurrentTheme`/`isThemeDark` drive selection (with a `theme-system` option following `prefers-color-scheme`). Spacing, radius, and font vars live in `_vars.scss` (e.g. `--spacing-1: 0.5rem … --spacing-10: 7.5rem`, an 8px-derived `rem` scale).

A component references `var(--theme-bg-color)`, `var(--theme-content-color)`, `var(--primary-button-default)`, etc.; flipping the body class re-themes the entire app with no component changes.

### Design tokens to port (from MOBILE_APP_ARCHITECTURE.md §3)

**Semantic colors:**

| Token | Dark | Light |
|-------|------|-------|
| App background | `#161719` | `#F1F1F4` |
| Surface 01 / 02 | `#0E0F10` / `#161719` | `#F8F9FA` / `#FFFFFF` |
| Popover/panel bg | `#1F2328` | `#FFFFFF` |
| Text primary | `rgba(255,255,255,.8)` | `rgba(0,0,0,.8)` |
| Text secondary | `#C1C9D6` | `#5A667E` |
| Text tertiary | `#8E99AF` | `#7B879E` |
| Divider | `rgba(255,255,255,.06)` | `rgba(0,0,0,.06)` |
| Primary button | `#3364E2` (hover `#6191FE`, active `#2553CF`) | same |
| Accent text | `#4D7FF5` | `#3566E2` |
| Error / Warning / Success | `#EB5757` / `#F2994A` / `#34DB80` | same |
| Link | `#377AE6` | `#377AE6` |

**Priority:** none `#8E99AF`, low `#6493FF`/`#3566E2`, medium `#FFBD2E`/`#FF9838`, high/urgent `#F6684B`/`#E9403D`. **Presence:** active `#34DB80`, busy `#FCC500`, dnd `#D95757`, away `#9099A2`.

**Type:** `IBM Plex Sans` (UI), `IBM Plex Mono` (code); weights 400/500/600/700; base body **14px**; scale 11/12/14/16/18/20; line-heights 1.0 / 1.25 / 1.5.

**Spacing (8px grid):** 2, 4, 6, 8, 12, 16, 20, 24, 28, 32, 40, 48, 56, 64, 80, 96, 120 px.

**Element sizes:** xs 24, sm 32, md 40, lg 48, xl 56, max 64 px.

**Radius:** 2 / 4 / 6 / 8 / 16 px — buttons & cards use **8px** (6 for sm/xs).

**Elevation (dark):** popup `0 4px 24px rgba(0,0,0,.5)`, card `0 16px 70px rgba(0,0,0,.5)`, button `0 1px 1px rgba(0,0,0,.15)`. Light popup `0 4px 24px rgba(0,0,0,.2)`.

**Component conventions:** buttons heights 48/40/32/24 (lg/md/sm/xs), h-padding 16 (8 sm), gap 8, focus = 2px outline `#2A59D6`; inputs translucent bg (`#a5bdff0d` dark / `#1530720d` light), error border `#FB6863`, placeholder `#8B97AD`; nav element height 32, padding 12, radius 6, icon 20 + 8px gap.

### Porting map

| Huly (web) | Native equivalent |
|------------|-------------------|
| `.theme-dark`/`.theme-light` CSS vars | two `ColorScheme`s (Flutter) / two token sets (RN) |
| `_vars.scss` spacing/radius | a spacing/radius tokens file |
| IBM Plex font stack | bundle IBM Plex Sans/Mono, `TextTheme` |
| `getPlatformColorForText(text, dark)` | reimplement `hashCode(text) % 24` over the palette table |
| `getClient()` / `createQuery()` | your transport client + a reactive-query layer ([live-queries](live-queries.md)) |

## Cross-references

- [live-queries](live-queries.md) -- what `createQuery()` wraps.
- [client-protocol](client-protocol.md) -- what `getClient()` ultimately talks to.
- [plugin-architecture](plugin-architecture.md) -- how plugins register UI components/presenters.
- [data-model](data-model.md) -- the `Doc` classes these components render.
- Service: [ui-package](../services/ui-package.md), [presentation-package](../services/presentation-package.md)
- Types: [core-types](../types/core-types.md)

## Gotchas

- A native client must **reproduce** these tokens — it cannot import the SCSS/Svelte. Treat `colors.ts` + the §3 tables as the spec, and verify hexes against `_colors.scss` for any token the table doesn't list.
- Avatar/label colors are **content-hashed** (`hashCode(id) % 24`), not random — the same entity must always get the same palette index across light/dark, or avatars will flicker color between sessions.
- The dark palette is **HSL-shifted**, not the light hexes dimmed — use the dark-theme variant, don't recolor the light one.
- `createQuery()` auto-unsubscribes via Svelte `onDestroy`; a native reimplementation has no equivalent lifecycle, so you must explicitly dispose subscriptions (call the `LiveQuery` unsubscribe).
- `getClient()` returns a **session singleton** rebuilt by `setClient` on (re)connect — don't cache the instance across a workspace switch.
- `theme-system` follows the OS via `prefers-color-scheme`; honor an explicit user override before falling back to the system value (`getCurrentTheme`).
