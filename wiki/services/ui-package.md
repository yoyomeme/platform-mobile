# @hcengineering/ui

> Huly's Svelte component library and design-system runtime: 230+ reusable components, the popup/panel/tooltip/modal infrastructure, location/navigation stores, and `colors.ts` — the 24-color avatar palette plus color-hashing utilities. The CSS-variable theme tokens live alongside in `packages/theme`.

## Where in code

- `packages/ui/src/index.ts` -- barrel: re-exports every Svelte component (`export { default as X }`) plus stores and helpers.
- `packages/ui/src/colors.ts` -- `ColorDefinition`, the white/dark palettes, avatar palettes, and color-hashing functions.
- `packages/ui/src/popups.ts` -- `showPopup`/`closePopup`/`updatePopup` and positioning.
- `packages/ui/src/panelup.ts` -- `showPanel`/`closePanel`.
- `packages/ui/src/location.ts` -- `getCurrentLocation`, `navigate`, `location`, `locationToUrl`.
- `packages/ui/src/tooltips.ts`, `modals.ts`, `popups.ts` -- overlay infrastructure.
- `packages/theme/styles/{_colors,_lumia-colors,_vars,global,common}.scss` -- the CSS-variable design tokens (consumed by components).

## Purpose

Every Huly feature plugin renders through `@hcengineering/ui`. It provides the visual primitives (buttons, inputs, dialogs, date pickers, tabs, scroll boxes, presenters), the floating-layer system (popups anchored to elements, side panels, tooltips, modals), and the in-app router (`location` store + `navigate`). It also defines the **color system**: a semantic theme (via CSS variables for light/dark) and a fixed 24-entry accent palette used for avatars and labels, addressed deterministically by hashing an id/text.

For a mobile port, this package (with `packages/theme`) is the source of truth for the design tokens summarized below — translate them into a Flutter `ThemeData` / RN design-tokens file rather than depending on the Svelte components.

## Public API

### Components (selected, `index.ts` re-exports ~234)

| Component | Purpose |
|-----------|---------|
| `Button`, `ButtonGroup`, `ButtonWithDropdown`, `HeaderButton` | Action buttons (size + kind variants). |
| `EditBox`, `TextArea`, `PlainTextEditor`, `EditWithIcon`, `SearchEdit`/`SearchInput` | Text input. |
| `Label`, `Icon`, `ActionIcon`, `StateTag`, `StatusBadge` | Inline display primitives. |
| `CheckBox`, `Toggle`, `RadioButton`/`RadioGroup`, `Switcher` | Form controls. |
| `Dialog`, `ModernDialog`, `PopupMenu`, `SelectPopup`, `ColorPopup` | Overlays/menus. |
| `DatePicker`, `DateRangePicker`, `DatePopup`, `DateRangePresenter`, `DueDatePresenter` | Date/time. |
| `Tabs`, `TabsControl`, `ScrollBox`, `Section`, `Grid`, `Row`, `Progress`, `ProgressCircle` | Layout/containers. |
| `Component` | Renders a lazily-loaded `Resource<...>` component by id. |

### Overlay & navigation API

| Export | Signature (abridged) | Notes |
|--------|----------------------|-------|
| `showPopup(component, props, element?, onClose?, onUpdate?, options?)` | `=> PopupResult` | Open a floating popup; `component` may be a Svelte component or a `Resource`/`AnyComponent` id. `element` controls anchoring. |
| `closePopup(category?)` | `(string?) => void` | Close topmost (or by category). `updatePopup(id, props)` patches props. |
| `showPanel(component, _id, _class, element?, ...)` | side panel | `closePanel(shouldRedirect?)` closes it. |
| `getCurrentLocation()` / `navigate(loc, ...)` / `location` | `location.ts` | In-app router: read current `Location`, navigate, subscribe to the `location` store. |
| `themeStore`, `languageStore` | re-exported from `@hcengineering/theme` | Active theme (dark/light) + language. |
| `deviceOptionsStore`, `ticker` | stores | Responsive device info; 1s `ticker` readable. |

### Colors (`colors.ts`)

| Export | Signature | Notes |
|--------|-----------|-------|
| `ColorDefinition` | interface | `{ name, color, icon?, iconText?, title?, number?, background? }`. |
| `whitePalette` / `darkPalette` | `readonly ColorDefinition[]` | The 24 named accent colors (light/dark variants). |
| `avatarWhiteColors` / `avatarDarkColors` | `readonly ColorDefinition[]` | HSL-derived avatar variants per theme. |
| `PaletteColorIndexes` | enum | `Firework`…`Porpoise` (0–23) — index into the palette. |
| `getPlatformColor(hash, dark)` / `getPlatformColorForText(text, dark)` | `=> string` | Deterministic color from a hash/text. |
| `getPlatformAvatarColorForTextDef(text, dark)` / `getPlatformAvatarColorByName(name, dark)` | `=> ColorDefinition` | Avatar color selection. |
| `getColorNumberByText(str)` | `=> number` | `hash % paletteLength` — pick-by-id index. |
| `hexColorToNumber` / `numberToHexColor` / `hexToRgb` / `rgbToHex` / `hslToRgb` / `rgbToHsl` / `defineAlpha` | conversions | Color math used by the palette and presenters. |
| `defaultBackground(dark)` | `=> string` | App background per theme. |

The 24 accent names: Firework, Watermelon, Pink, Fuchsia, Lavander, Mauve, Heather, Orchid, Blueberry, Arctic, Sky, Cerulean, Waterway, Ocean, Turquoise, Houseplant, Crocodile, Grass, Sunshine, Orange, Pumpkin, Cloud, Coin, Porpoise. Pick with `hash(id) % 24`.

## Design tokens (summary)

From `MOBILE_APP_ARCHITECTURE.md §3` and `packages/theme/styles/*.scss` — CSS-variable based, `.theme-dark` / `.theme-light`:

- **Semantic colors** — App bg `#161719` (dark) / `#F1F1F4` (light); primary button `#3364E2` (hover `#6191FE`, active `#2553CF`); accent text `#4D7FF5` / `#3566E2`; error `#EB5757`, warning `#F2994A`, success `#34DB80`, link `#377AE6`. Focus ring `#2A59D6` / `#204DC8`.
- **Priority** — none `#8E99AF`, low `#6493FF`/`#3566E2`, medium `#FFBD2E`/`#FF9838`, high/urgent `#F6684B`/`#E9403D`. **Presence** — active `#34DB80`, busy `#FCC500`, dnd `#D95757`, away `#9099A2`.
- **Type** — `IBM Plex Sans` (UI), `IBM Plex Mono` (code); weights 400/500/600/700; base body 14px; sizes 11/12/14/16/18/20; line-heights 1.0 / 1.25 / 1.5.
- **Spacing** (8px grid) — 2,4,6,8,12,16,20,24,28,32,40,48,56,64,80,96,120 px. **Element sizes** — xs 24, sm 32, md 40, lg 48, xl 56, max 64.
- **Radius** — 2 / 4 / 6 / 8 / 16; buttons & cards use 8 (6 for sm/xs).
- **Elevation (dark)** — popup `0 4px 24px rgba(0,0,0,.5)`, card `0 16px 70px rgba(0,0,0,.5)`, button `0 1px 1px rgba(0,0,0,.15)`.
- **Components** — Buttons heights 48/40/32/24, padding 16 (8 sm), gap 8. Inputs translucent bg (`#a5bdff0d` dark / `#1530720d` light), error border `#FB6863`, placeholder `#8B97AD`. Cards (`.hulyComponent`) 1px divider border, radius 8. Nav element height 32, padding 12, radius 6, icon 20 + 8px gap.

## Usage

```typescript
import { showPopup, closePopup, navigate, getCurrentLocation } from '@hcengineering/ui'
import { getPlatformAvatarColorForTextDef, getColorNumberByText } from '@hcengineering/ui'
import { get } from 'svelte/store'
import { themeStore } from '@hcengineering/ui'

// Open a popup anchored to a click target.
showPopup(SomeMenu, { items }, eventTarget, (result) => { /* handle */ })

// Deterministic avatar color from a person id/name.
const dark = get(themeStore).dark
const def = getPlatformAvatarColorForTextDef(personName, dark)   // ColorDefinition
const idx = getColorNumberByText(personId)                       // 0..23

// In-app navigation.
const loc = getCurrentLocation()
navigate({ ...loc, path: [...loc.path.slice(0, 2), 'tracker', projectId] })
```

## Cross-references

- [presentation-package](presentation-package.md) -- supplies the data (`getClient`/`createQuery`) these components render.
- [platform-package](platform-package.md) -- `showPopup`/`Component` resolve `Resource<...>` component ids via `getResource`; labels are `IntlString`.
- Concepts: [ui-framework](../concepts/ui-framework.md), [localization](../concepts/localization.md).
- `MOBILE_APP_ARCHITECTURE.md` §3 -- full theme token reference for porting.

## Gotchas

- **Two color systems coexist.** The *semantic theme* (backgrounds, buttons, status) is CSS variables in `packages/theme`; the *accent palette* (avatars/labels) is the 24-entry `whitePalette`/`darkPalette` in `colors.ts`. Don't conflate them — a port needs both a `ColorScheme` and a palette table.
- **Colors are theme-paired.** Every palette/avatar helper takes a `dark: boolean`; resolve it from `themeStore`, not by guessing — light and dark are different arrays (`avatarWhiteColors` vs `avatarDarkColors`).
- **`showPopup` accepts a component *or* a resource id.** Passing an `AnyComponent`/`Resource` string triggers a lazy `getResource` load; passing the Svelte component renders synchronously.
- **Navigation is store-based, not a framework router.** `location`/`navigate` drive a custom `Location` (path segments + query + fragment); a mobile port maps these segments onto native navigation rather than reusing the web router.
- **Heavy package.** It re-exports 230+ components plus overlay infra and color math — for a mobile/native client, port the tokens (above), not the Svelte components.
