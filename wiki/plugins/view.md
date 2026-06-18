# View (`view`)

> The rendering substrate: viewlets (list/table/kanban), presenters, editors, filters, and actions — how any document class is displayed and acted on.

## Where in code
- `plugins/view/src/index.ts` -- plugin id (`viewId`), the `view` registry (mixins, classes, viewlet descriptors, action ids)
- `plugins/view/src/types.ts` -- all interfaces (`Viewlet`, `ViewletDescriptor`, `Action`, `Filter`, `FilterMode`, presenter/editor mixins)
- `plugins/view/src/utils.ts` -- model-building helpers
- `models/view/src/` -- model (base viewlet descriptors: Table/List/Grid, core actions, filter modes)
- `plugins/view-resources/` -- UI (the actual List/Table/Kanban Svelte components, filter bar, action menu)

## Purpose
`view` decouples **what** a document is (its class/attributes) from **how** it's shown and edited. It
provides: viewlet descriptors (a rendering style), `Viewlet` configs (which fields, options per class),
a large set of `Class<Doc>` **mixins** that bind a class to UI components (presenter, editor, panel,
title, icon, link provider), a declarative **Action** system, and a **Filter** framework. Every
feature app builds its screens by registering viewlets and mixins against `view`.

## Document classes
| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `ViewletDescriptor` | `core.Doc`, `UXObject` | `component: AnyComponent` | A rendering style (Table, List, Kanban, Grid, …). |
| `Viewlet` | `core.Doc` | `attachTo: Ref<Class>`, `descriptor`, `config: (BuildModelKey\|string)[]`, `options?: FindOptions`, `viewOptions?`, `baseQuery?`, `variant?` | A concrete view of a class: which fields/columns, sort, grouping. |
| `Action<T,P>` | `core.Doc`, `UXObject` | `action: Resource<fn>`, `target: Ref<Class>`, `input`, `context: ViewContext`, `query?`, `visibilityTester?`, `override?`, `keyBinding?` | A declarative menu/context/keyboard action. |
| `ActionCategory` | `core.Doc`, `UXObject` | `visible` | Groups actions in the UI. |
| `FilterMode` | `core.Doc` | `label`, `result: FilterFunction` | A filter operator (in/nin/contains/…) producing a query. |
| `Filter` (type) | -- | `key: KeyFilter`, `mode`, `value[]`, `nested?` | A runtime filter instance. |
| `FilteredView` | `core.Doc` | `name`, `filters`, `viewOptions?`, `users`, `sharable?` | A saved filter+view configuration. |
| `ViewletPreference` | `preference.Preference` | (per-user viewlet config) | User's saved columns/options for a viewlet. |
| `LinkPresenter` | `core.Doc` | `pattern`, `component` | Renders matched URLs/refs in text. |

## Key relationships / mixins
- The power is in **`Class<Doc>` mixins** bound per feature class:
  `ObjectPresenter`, `ListItemPresenter`, `AttributePresenter`, `CollectionPresenter`,
  `ObjectEditor`, `AttributeEditor`, `CollectionEditor`, `ArrayEditor`,
  `ObjectPanel`, `ObjectTitle`, `ObjectIcon`, `ObjectIdentifier`, `LinkProvider`, `SpacePresenter`,
  `IgnoreActions`, `ClassFilters`, `AttributeFilter`. Each binds a class+role to an `AnyComponent`.
- `Viewlet.attachTo` ties a config to a class; `descriptor` picks the renderer; `config` lists keys
  (with `$lookup.x` joins) and `BuildModelKey` overrides per column.
- `Action.target`/`query`/`visibilityTester`/`context` decide where an action appears and whether it's
  enabled; `override` lets a class-specific action replace a global one.
- `Groupping`/`Aggregation`/`ClassSortFuncs` mixins customize how list grouping and sorting work
  (e.g. grouping issues by status with proper ordering).

## Notable actions/flows
- `createAction(builder, {...}, id)` and `classPresenter(...)` are the model helpers apps call.
- Standard actions: `Open`, `OpenInNewTab`, `Delete`, `ShowPopup`, plus `actionTemplates` (move, etc.).
- Filtering: a `Filter` picks a `KeyFilter` (attribute) + a `FilterMode` whose `result` function turns
  the chosen values into a Mongo-style query merged into `findAll`.

## Mobile relevance
Foundational but **not directly portable** — the registry is built around Svelte `AnyComponent`s. On
mobile you reimplement the renderers (list/kanban/table) natively, but you should **read** the
`Viewlet` configs and presenter mixins as the source of truth for *which fields to show, default sort,
grouping, and which actions exist per class*. Treat `view` as the spec for your feature screens.

## Cross-references
- Plugins: every feature app (e.g. [tracker](tracker.md), [drive](drive.md), [board](board.md)) registers viewlets/mixins here; [activity](activity.md), [preference](preference.md) (ViewletPreference)
- Concepts: [ui-framework](../concepts/ui-framework.md), [plugin-architecture](../concepts/plugin-architecture.md), [data-model](../concepts/data-model.md), [live-queries](../concepts/live-queries.md)

## Gotchas
- `Viewlet.config` strings can use `$lookup.field` to pull joined data — the corresponding `options.lookup`
  must be set or the field is empty.
- Presenter/editor/panel bindings are **mixins on the class**, not properties of the doc; to know how a
  class renders you query its mixins in the `Hierarchy`, not the doc instance.
- `Action.input` (`focus`/`selection`/`any`/`none`) and `context.mode` gate visibility — an action can
  silently not appear if input/mode/`visibilityTester` don't match.
- `view` is UI metadata; none of its `AnyComponent` refs resolve on a non-Svelte client — port behavior,
  not components.
