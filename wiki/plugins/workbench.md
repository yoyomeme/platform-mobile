# Workbench (`workbench`)

> The app shell: registers feature apps as `Application`s, drives left-nav (spaces/specials/groups), and renders generic views via `SpecialView`.

## Where in code
- `plugins/workbench/src/index.ts` -- plugin id (`workbenchId = 'workbench'`), re-exports types/utils
- `plugins/workbench/src/types.ts` -- core interfaces (`Application`, `NavigatorModel`, `SpecialNavModel`, `SpacesNavModel`, `Widget`, `WorkbenchTab`, `SpaceView`)
- `plugins/workbench/src/plugin.ts` -- class/mixin/component ids (`Application`, `SpaceView` mixin, `SpecialView` component)
- `models/workbench/src/` -- model + helpers (`createNavigateAction`, `SpaceView`)
- `plugins/workbench-resources/` -- UI shell, `connect.ts` (bootstraps the client connection), navigator, `SpecialView` component

## Purpose
`workbench` is the top-level UI frame that hosts every feature app. Each app (Tracker, Drive, Chat, …)
registers an `Application` doc declaring its icon, alias (URL segment), and a `NavigatorModel`
describing its left-hand navigation. The shell renders the app switcher, the per-app navigator (spaces
+ "special" views + groups), the main panel, and sidebar **widgets**. `workbench-resources/connect.ts`
is also the reference client bootstrap (config discovery → account login → transactor connect → model
load).

## Document classes
| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `Application` | `core.Doc` | `label`, `alias`, `icon`, `hidden`, `position?`, `order?`, `navigatorModel?`, `component?`, `locationResolver?`, `accessLevel?` | A registered feature app in the workbench. |
| `ApplicationNavModel` | `core.Doc` | `extends: Ref<Application>`, `spaces?`, `specials?`, `groups?` | Extends another app's navigator (plugin composition). |
| `HiddenApplication` | `preference.Preference` | `attachedTo: Ref<Application>` | Per-user hidden app. |
| `Widget` | `core.Doc` | `label`, `icon`, `type: WidgetType`, `component`, `accessLevel?` | A sidebar widget (fixed/flexible/configurable). |
| `WidgetPreference` | `preference.Preference` | `enabled` | Per-user widget enable. |
| `WorkbenchTab` | `preference.Preference` | `attachedTo: AccountUuid`, `location`, `isPinned`, `name?` | A saved/open browser-style tab. |

Non-doc models: `NavigatorModel` (`spaces`, `specials`, `groups`), `SpacesNavModel`
(`spaceClass`, `createComponent`), `SpecialNavModel` (`id`, `component`, `componentProps`,
`visibleIf`, `notificationsCountProvider`, `queryBuilder`), `GroupsNavModel` (`groupByClass`),
`ViewConfiguration`, `WidgetTab`.

## Key relationships / mixins
- **`SpaceView` mixin** (`Class<Obj>` mixin) declares, for a space class, the `ViewConfiguration`
  (which child class to list, the create dialog) — e.g. a Recruit `Vacancy` space shows `Applicant`s.
- An `Application.navigatorModel` lists **spaces** (grouped by `spaceClass` — Tracker projects, Drive
  drives, …) and **specials** (singleton views like "All Issues", "My Applications") rendered with
  `workbench.component.SpecialView` + `componentProps` (commonly `_class` + `label`).
- `SpecialView` is the generic "list documents of `_class`" panel many apps reuse instead of a custom
  component (see Drive's `browser` special: `{ _class: drive.class.Drive }`).
- `SpecialNavModel.notificationsCountProvider` ties nav badges to [notification](notification.md)/inbox
  contexts; `queryBuilder`/`visibleIf` make nav items dynamic.
- `metadata.DefaultApplication` / `ExcludedApplications` control which apps appear.

## Notable actions/flows
- Boot (`connect.ts`): fetch `config.json` → account login + `selectWorkspace` → connect transactor WS
  → `loadModel` → build `Hierarchy` → render workbench. (See [client-protocol](../concepts/client-protocol.md).)
- App switch sets the location alias; the navigator queries spaces of `spaceClass` and renders
  specials/groups; selecting an item routes to the main panel.
- `createNavigateAction` registers keyboard/menu navigation into specials.

## Mobile relevance
**This is the mobile app's shell blueprint.** Query `workbench.class.Application` to enumerate apps,
build a bottom-tab/drawer from them, and for each app read its `navigatorModel` to build the
spaces/specials nav. `SpecialView`'s `_class`+query pattern maps directly to "list screen for class
X". `WorkbenchTab` is desktop tabbing (skip on mobile). Use the connect flow as the canonical
bootstrap sequence to port.

## Cross-references
- Plugins: every feature app registers an `Application` here; [login](login.md) (precedes workbench), [notification](notification.md)/inbox (nav badges), [preference](preference.md), [view](view.md), [setting](setting.md)
- Concepts: [client-protocol](../concepts/client-protocol.md), [plugin-architecture](../concepts/plugin-architecture.md), [workspace-multitenancy](../concepts/workspace-multitenancy.md), [model-layer](../concepts/model-layer.md)
- Flows: app bootstrap / connection

## Gotchas
- `NavigatorModel` fields hold `AnyComponent` refs and `Resource` callbacks that only resolve in the
  Svelte runtime — read them as a **navigation spec**, reimplement the components natively.
- `Application.alias` is the URL/location key; routing is location-driven, not state-driven.
- "Specials" vs "spaces": specials are singleton views (often `SpecialView` with a `_class`); spaces
  are user-created containers grouped by `spaceClass`. Build both.
- `accessLevel`/`HiddenApplication`/`ExcludedApplications` gate which apps a user sees.
