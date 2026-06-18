# Tracker (`tracker`)

> Huly's flagship project-management app: projects, issues, sub-issues, statuses, milestones, components. Issues are `Task`s.

## Where in code
- `plugins/tracker/src/index.ts` -- plugin id (classes/strings/statuses/actions); interfaces `Project`, `Issue`, `IssueStatus`, `Milestone`, `Component`, `IssueTemplate`, `TimeSpendReport`
- `models/tracker/src/types.ts` -- model: `@Model` definitions, `DOMAIN_TRACKER`, default statuses
- `models/tracker/src/{index,actions,viewlets,presenters,permissions}.ts` -- model wiring (viewlets, actions, permissions)
- `plugins/tracker-resources/` -- Svelte UI (`EditIssue`, `CreateIssue`, `ProjectPresenter`, `IssueStatusPresenter`, list/kanban views)

## Purpose
Tracker is the linear-style issue tracker. It specializes the [task](task.md) substrate: a tracker `Project` is a `task.class.Project`, and an `Issue` is a `task.class.Task`. On top of the generic engine it adds issue-specific concepts: priority, components, milestones, estimation/time-reporting, sub-issues, relations (blocks/blocked-by), and issue templates.

## Document classes

| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `Project` | `task.class.Project` (`+ IconProps`) | `identifier`, `sequence`, `defaultIssueStatus?`, `defaultAssignee?`, `defaultTimeReportDay` | A tracker project (typed space). `identifier` is the issue key prefix; `sequence` drives issue numbering. |
| `Issue` | `task.class.Task` | `title`, `description: MarkupBlobRef`, `status: Ref<IssueStatus>`, `priority`, `component`, `milestone?`, `subIssues`, `parents: IssueParentInfo[]`, `childInfo`, `blockedBy?`, `relations?`, `estimation`, `remainingTime`, `reportedTime`, `reports`, `todos?` | The core work item. `attachedTo` points at the parent `Issue` (for sub-issues). |
| `IssueStatus` | `core.class.Status` | (inherits Status: `name`, `color`, `category`, `ofAttribute`) | Workflow state for issues; mapped to a `StatusCategory`. |
| `Milestone` | `core.class.Doc` (`DOMAIN_TRACKER`) | `label`, `description?`, `status: MilestoneStatus`, `space: Ref<Project>`, `targetDate`, `comments`, `attachments?` | A delivery target grouping issues. |
| `Component` | `core.class.Doc` (`DOMAIN_TRACKER`) | `label`, `description?`, `lead: Ref<Employee>`, `space: Ref<Project>` | A sub-area of a project for grouping issues. |
| `IssueTemplate` | `core.class.Doc` (`DOMAIN_TRACKER`) | `title`, `description`, `children: IssueTemplateChild[]`, `space` | Reusable template that spawns issues + sub-issues. |
| `TimeSpendReport` | `core.class.AttachedDoc` (`DOMAIN_TRACKER`) | `attachedTo: Ref<Issue>`, `employee`, `date`, `value` (man-hours) | A logged time entry against an issue. |
| `ProjectTargetPreference` | `preference.class.Preference` | `attachedTo: Ref<Project>`, `usedOn`, `props?` | Per-user project view preferences. |
| `RelatedIssueTarget` | `core.class.Doc` (`DOMAIN_TRACKER`) | `target?`, `rule: classRule \| spaceRule` | Routes related issues of other docs into a default project. |

### Enums
- `IssuePriority`: NoPriority, Urgent, High, Medium, Low.
- `MilestoneStatus`: Planned, InProgress, Completed, Canceled.
- `IssuesGrouping` / `IssuesOrdering`: status, assignee, priority, component, milestone, dueDate, manual (rank).

### Default statuses (`tracker.status.*`)
Backlog, Todo, InProgress, Coding, UnderReview, Done, Canceled — mapped to task status categories.

## Key relationships / mixins
- `Issue.attachedTo: Ref<Issue>` — **sub-issues** are issues attached to a parent issue; `tracker.ids.NoParent` is the sentinel for top-level issues. `parents` / `childInfo` cache the tree for fast rendering.
- `blockedBy` / `relations` — `RelatedDocument[]` cross-issue links.
- `tracker.mixin.IssueTypeData` / `ClassicProjectTypeData` — generated target mixins carrying project-type custom attributes.
- `todos?` — links to [time](time.md) `ToDo`s; `reports` → `TimeSpendReport` collection.
- Collaboration/comments via [chunter](chunter.md) `ChatMessage` and [activity](activity.md).

## Spaces
Issues are scoped by `space: Ref<Project>`. The project's `type` (a `ProjectType` from [task](task.md)) defines available statuses and task types (`tracker.taskTypes.Issue`, `.SubIssue`). `tracker.project.DefaultProject` is the seeded default.

## Notable actions/flows
- `SetStatus`, `SetPriority`, `SetAssignee`, `SetComponent`, `SetMilestone`, `SetDueDate`, `SetLabels`, `SetParent`/`UnsetParent`.
- `NewIssue`, `NewIssueGlobal`, `NewSubIssue`, `MoveToProject`, `Duplicate`, `CopyIssueId/Title/Link`.
- Assignee notification: `tracker.ids.AssigneedNotification` (via task) + `IssueNotification*` strings drive inbox/push.

## Mobile relevance
**Tier-1 MVP.** Render: issue lists grouped by status/assignee/priority; issue detail (title, markup description via blob, status/priority/assignee/component/milestone, sub-issue list, comments). Editable on mobile: status, priority, assignee, due date, comment composer. Kanban and time-reporting are lower priority. Description is a `MarkupBlobRef` — fetch the blob, render markup read-only first.

## Cross-references
- Substrate: [task](task.md)
- Pairs with: [chunter](chunter.md) (comments), [activity](activity.md) (history), [tags](tags.md) (labels), [time](time.md) (todos), [contact](contact.md) (assignee/lead)
- Concepts: [data-model](../concepts/data-model.md), [transaction-model](../concepts/transaction-model.md)
- Flows: [notification-flow](../flows/notification-flow.md)

## Gotchas
- `Issue.description` is a `MarkupBlobRef | null`, **not** inline markup — it is stored as a separate blob and must be fetched/streamed. (Compare: `Milestone.description` is inline `Markup`.)
- Issue `identifier` (e.g. `HULY-123`) is composed from the project's `identifier` + the issue `number`, allocated from the project `sequence`.
- Sub-issues are full `Issue` docs (not a lightweight child type); `subIssues` is a `CollectionSize` count, not the children themselves.
- `IssueStatus` instances are shared per project type — do not assume one status set globally.
