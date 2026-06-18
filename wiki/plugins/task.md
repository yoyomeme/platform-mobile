# Task (`task`)

> The base work-item substrate. Defines `Task`, `TaskType`, `ProjectType`, and the status/state machine that Tracker, Recruit, Lead, and Board all build on.

## Where in code
- `plugins/task/src/index.ts` -- plugin id (classes, mixins, statusCategory, viewlets, strings); core interfaces `Task`, `TaskType`, `ProjectType`, `ProjectTypeDescriptor`, `TaskTypeDescriptor`, `Project`
- `models/task/src/index.ts` -- model: `@Model` definitions, `DOMAIN_TASK`, the five `StatusCategory` seed docs
- `plugins/task-resources/` -- Svelte UI (kanban, status editors, project-type management, `ProjectTypeSelector`, `CreateStatePopup`)

## Purpose
Huly does not hardcode "issue" or "candidate" workflows. Instead it provides a generic, user-customizable work-item engine:

- A **`ProjectType`** (a kind of `SpaceType`) defines a reusable workflow template: which task types it allows, which statuses exist, and their colors.
- A **`TaskType`** defines one category of work item inside a project type (e.g. "Issue", "Sub-issue", "Candidate"), pointing at a base class and a target mixin class that holds user-defined attributes.
- A **`Task`** is the actual work item — an `AttachedDoc` with `status`, `assignee`, `number`, `identifier`, `rank`, `dueDate`.
- **Statuses** (`core.class.Status`) are grouped by **`StatusCategory`** so different apps can map their own state names onto a shared lifecycle (backlog → active → done/won/lost).

Apps like Tracker subclass these: `tracker.class.Issue extends task.class.Task`, `tracker.class.Project extends task.class.Project`.

## Document classes

| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `Task` | `core.class.AttachedDoc` (`DOMAIN_TASK`) | `kind: Ref<TaskType>`, `status: Ref<Status>`, `assignee: Ref<Person> \| null`, `number`, `identifier`, `dueDate`, `rank`, `isDone?` | Abstract base work item. Apps subclass it. |
| `TaskType` | `core.class.Doc` (`DOMAIN_MODEL`) | `parent: Ref<ProjectType>`, `descriptor`, `kind: 'task'\|'subtask'\|'both'`, `ofClass`, `targetClass`, `statuses: Ref<Status>[]`, `statusCategories` | One work-item category within a project type. |
| `TaskTypeDescriptor` | `core.class.Doc` (`DOMAIN_MODEL`) | `name`, `description`, `icon`, `baseClass`, `allowCreate`, `statusCategoriesFunc?` | Template/blueprint for a `TaskType`. |
| `ProjectType` | `core.class.SpaceType` | `descriptor`, `tasks: Ref<TaskType>[]`, `statuses: ProjectStatus[]`, `targetClass`, `classic: boolean` | User-defined workflow template scoping a family of projects. |
| `ProjectTypeDescriptor` | `core.class.SpaceTypeDescriptor` | `baseClass`, `allowedClassic?`, `allowedTaskTypeDescriptors?`, `editor?` | Blueprint for project types. |
| `Project` | `core.class.TypedSpace` | `type: Ref<ProjectType>` | Base space holding tasks; apps extend (Tracker's `Project` adds `identifier`, `sequence`). |

### Status categories (seeded in `models/task/src/index.ts`)
`task.statusCategory.UnStarted`, `.ToDo`, `.Active`, `.Won`, `.Lost`. Each is a `core.class.StatusCategory`. Apps map their concrete statuses (e.g. Tracker's Backlog/Todo/InProgress/Done/Cancelled) into these categories for cross-app ordering and "done" detection.

## Key relationships / mixins
- `task.mixin.TaskTypeClass` / `task.mixin.ProjectTypeClass` — mixins on a `Class` that bind it to a specific `TaskType` / `ProjectType`. This is how a generated target mixin class knows which task type owns it.
- `task.mixin.KanbanCard` — registers the component used to render a class on a kanban board.
- `task.attribute.State` — the canonical `Attribute<Status>` that status fields reference via `ofAttribute`.
- `createStatesData()` (exported from index) builds `Status` seed data from `TaskStatusFactory[]`.

## Spaces
A `Task` lives in a `Project` (a `TypedSpace`). The space's `type` points at a `ProjectType`, which determines the available task types and statuses. `task.space.Statuses` and `task.space.Sequence` are system spaces holding shared status docs and per-project number sequences.

## Notable actions/flows
- `task.action.Move` — move a task between statuses/projects.
- Project-type management: `ProjectTypeSelector`, `CreateStatePopup`, editing workflow statuses.
- Number/identifier assignment is sequence-driven per project (see Tracker's `sequence`).

## Mobile relevance
Substrate, not a directly-rendered app. Mobile mostly consumes the **derived** classes (Tracker `Issue`, etc.). It must, however, resolve a task's `status` → `StatusCategory` (for "done" state, colors, grouping) and read `ProjectType.statuses` for the status picker. Treat task-type/project-type editing as desktop-only.

## Cross-references
- Built on by: [tracker](tracker.md) (Tier-1), plus Recruit/Lead/Board (Tier-2)
- Concepts: [data-model](../concepts/data-model.md), [model-layer](../concepts/model-layer.md)
- UI substrate: [view](view.md) (viewlets/kanban), [activity](activity.md)
- Notifications: [notification](notification.md)

## Gotchas
- Statuses are **shared docs** in a dedicated status space, referenced by `Ref<Status>`; they are not embedded per-task. Two projects of the same type can share status instances.
- `ProjectType` is a `SpaceType`, so a "project" is fundamentally a typed space — querying tasks means querying by `space`.
- `targetClass` on a `TaskType`/`ProjectType` is a generated **mixin** that carries user-defined custom fields; the base `Task`/`Project` class will not show those attributes unless you read through the mixin.
- `isDone` on `Task` is a cached flag; the source of truth for "done" is the status's `StatusCategory` (`Won`/`Lost` for classic types).
