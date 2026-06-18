# Board (`board`)

> Trello-style kanban: a `Board` (project) of `Card`s, where cards are `task.Task`s grouped by status.

## Where in code
- `plugins/board/src/index.ts` -- plugin id (`boardId = 'board'`), interfaces, class/action ids
- `models/board/src/index.ts` -- model (`TBoard`, `TCard`, viewlets, kanban config, actions)
- `models/board/src/plugin.ts` -- model-side ids
- `plugins/board-resources/` -- UI (kanban board, card editor, cover/labels/dates popups)

## Purpose
A lightweight kanban app built on the shared **task** substrate. A `Board` is a `task.Project`;
each `Card` is a `task.Task` whose `status` (state) is the kanban column. Cards carry visual
extras (cover color, members, dates). Tier-2 mobile feature.

## Document classes
| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `Board` | `task.Project` | `color?`, `background?` | A kanban board (the project/space). |
| `Card` | `task.Task` | `title`, `description: Markup`, `isArchived?`, `members?: Ref<Employee>[]`, `location?`, `cover?: CardCover \| null`, `startDate` | A kanban card; its `status` is the column. |
| `CardCover` (type) | -- | `color: number`, `size: 'large'\|'small'` | Embedded cover styling on a card. |
| `MenuPage` | `core.Doc` | `component`, `pageId`, `label` | Registers a board side-menu page (main/archive). |
| `CommonBoardPreference` | `preference.Preference` | -- | Per-user board UI preference. |

## Key relationships / mixins
- `Card extends task.Task` → it inherits `assignee`, `status` (a `Ref<Status>`), `rank` (ordering),
  `number`, identifier, etc. from [task](task.md). The kanban grouping is by `status`.
- `Board extends task.Project` → a `ProjectType` / `ProjectTypeDescriptor` (`BoardType`) defines the
  available statuses (columns) and the `Card` `TaskType`.
- `Card.members` are `contact.Employee` refs; `cover` is an embedded `CardCover` (registered as a
  `Type` class so it gets a presenter).
- Activity + chunter comments attach to cards via the activity substrate.

## Notable actions/flows
- Card actions: `Open`, `Cover`, `Dates`, `Labels`, `Move`, `Copy`, `Archive`, `SendToBoard`,
  `Delete`. Move/SendToBoard re-parent a card to another board/status.
- Creating a card = `task` create flow scoped to a `Board` space with a chosen status; dragging
  across columns issues a `TxUpdateDoc` changing `status` (and `rank` for ordering).
- Labels reuse `tags` (`TagReference`/`TagElement`); the `Other` `TagCategory` is registered here.

## Mobile relevance
Tier 2. Reuse the generic task/kanban rendering: query `Card` by space (`Board`), group by
`status`, order by `rank`. Drag-to-column = update `status` + `rank`. Cover color and member
avatars are the main board-specific UI. Shares status-management logic with Tracker.

## Cross-references
- Plugins: [task](task.md) (base classes), [tracker](tracker.md) (same substrate), [view](view.md) (kanban viewlet), [tags](tags.md), [activity](activity.md), [contact](contact.md)
- Concepts: [data-model](../concepts/data-model.md), [ui-framework](../concepts/ui-framework.md)

## Gotchas
- A `Card` is a `Task`, so don't model status as a free string — it's a `Ref<Status>` constrained by
  the board's `ProjectType`. Column order and card order both come from `rank` / status ordering.
- `cover` is nullable (`CardCover | null`) — distinguish "no cover" from "default".
- `Board` is a space; archiving a board ≠ archiving its cards (`Card.isArchived` is separate).
