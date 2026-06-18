# Time (`time`)

> Personal productivity: `ToDo`s and the planner that schedules them into calendar time slots (`WorkSlot`).

## Where in code
- `plugins/time/src/index.ts` -- plugin id (classes/strings); interfaces `ToDo`, `WorkSlot`, `ProjectToDo`, `Todoable`
- `plugins/time/src/analytics.ts` -- analytics events
- `models/time/src/index.ts` -- model: `@Model` defs, `ToDos` space
- `plugins/time-resources/` -- Svelte UI (`Me` planner, `Team`, `EditToDo`, `ToDoPresenter`)

## Purpose
Time is Huly's personal task/planner layer ("My Planner"). A **`ToDo`** is a personal action item — it can be free-standing or attached to any doc (e.g. an issue you plan to work on). The planner schedules a todo into one or more **`WorkSlot`**s, which are calendar `Event`s, so planned work appears on your calendar. This is the "what am I doing today" view, distinct from the shared work items in [tracker](tracker.md).

## Document classes

| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `ToDo` | `core.class.AttachedDoc` | `attachedTo: Ref<Doc>`, `attachedToClass`, `title`, `description: Markup`, `dueDate?`, `priority: ToDoPriority`, `visibility`, `doneOn: Timestamp \| null`, `user: Ref<Employee>`, `workslots`, `attachedSpace?`, `rank`, `labels?` | A personal to-do; `doneOn` set when completed. |
| `WorkSlot` | `calendar.class.Event` | `attachedTo: Ref<ToDo>`, `attachedToClass` | A scheduled block of time for a todo — it *is* a calendar event. |
| `ProjectToDo` | `time.class.ToDo` | `attachedSpace: Ref<Space>` (required) | A todo bound to a project space (classic project automation). |

### Enum / helper types
- `ToDoPriority`: High, Medium, Low, NoPriority, Urgent.
- `Todoable` — interface marking a class that can own todos (`todos?: CollectionSize<ToDo>`); e.g. tracker `Issue` is todoable.
- `TodoAutomationHelper` / `TodoDoneTester` — resources letting a project type auto-complete a todo (e.g. moving an issue to Done marks its todo done).

## Key relationships / mixins
- **`ToDo.attachedTo`** can point at any doc — a todo created from a tracker `Issue` attaches to that issue (so finishing it can sync back via `TodoDoneTester`).
- **`WorkSlot extends Event`** — scheduling a todo creates calendar events; planner and [calendar](calendar.md) share the same timeline. `workslots` counts a todo's slots.
- `ToDo.user: Ref<Employee>` ties the todo to a person (via [contact](contact.md)'s Employee mixin).
- `time.mixin.ItemPresenter` registers per-class todo rendering.

## Spaces
Todos live in the `time.space.ToDos` space (personal). `ProjectToDo` additionally references a project space via `attachedSpace`.

## Notable actions/flows
- `AddToDo` / `NewToDo`, `EditToDo`, mark done (`doneOn`), reassign/unassign.
- Planner drag-to-schedule → creates `WorkSlot` calendar events.
- Auto-done via `TodoAutomationHelper` when the source doc reaches a done state.

## Mobile relevance
**Tier-1 (personal productivity).** Render: today/agenda planner list of `ToDo`s (grouped by date/priority), with quick-complete (set `doneOn`) and create. WorkSlots overlay onto the [calendar](calendar.md) view. Editing todos and toggling done are the core mobile interactions; full drag-to-plan scheduling is lower priority.

## Cross-references
- Scheduling: [calendar](calendar.md) (`WorkSlot extends Event`)
- Source docs: [tracker](tracker.md) (`Issue` is `Todoable`; `Issue.todos`)
- People: [contact](contact.md) (`ToDo.user`)
- Notifications: [notification](notification.md), [inbox](inbox.md) (`TimeNotificationGroup`)
- Concepts: [data-model](../concepts/data-model.md)

## Gotchas
- "Done" is `doneOn !== null` (a timestamp), not a boolean — render completion from that field.
- A `WorkSlot` is a real calendar `Event`; deleting/moving planner blocks affects the calendar timeline. Don't treat slots as pure metadata.
- `ToDo` is an `AttachedDoc` on any doc — a todo attached to an issue is *not* the issue; syncing completion back is the job of `TodoDoneTester`, handled server-side.
- `ProjectToDo` vs `ToDo`: only `ProjectToDo` guarantees `attachedSpace`; plain todos may be project-less personal items.
