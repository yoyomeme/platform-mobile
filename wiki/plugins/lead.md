# Lead (`lead`)

> Sales CRM: `Funnel`s (pipelines) of `Lead`s attached to `Customer`s, built on the task substrate.

## Where in code
- `plugins/lead/src/index.ts` -- plugin id (`leadId = 'lead'`), interfaces, class/mixin ids
- `models/lead/src/index.ts` -- model (`TFunnel`, `TLead`, `Customer` mixin, viewlets, kanban)
- `models/lead/src/types.ts`, `models/lead/src/spaceType.ts` -- model classes + funnel project type
- `models/lead/src/permissions.ts` -- `ForbidCreateFunnel` permission
- `plugins/lead-resources/` -- UI

## Purpose
A simple sales pipeline. A `Funnel` is a `task.Project` (the pipeline/space); a `Lead` is a
`task.Task` whose `status` is the pipeline stage; each `Lead` is attached to a `Customer`, which is
a **mixin on `contact.Contact`** (so any Person/Organization can be marked a customer). Tier-2
mobile feature.

## Document classes
| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `Funnel` | `task.Project` | `fullDescription?: Markup`, `attachments?` | A sales pipeline (the space). |
| `Lead` | `task.Task` | `space: Ref<Funnel>`, `attachedTo: Ref<Customer>`, `status: Ref<Status>`, `startDate`, `title` | A deal/opportunity card; `status` = pipeline stage. |
| `Customer` (mixin) | `contact.Contact` | `leads?: number`, `customerDescription: MarkupBlobRef \| null` | Marks a contact as a customer; counts attached leads. |

## Key relationships / mixins
- `Customer` is a **`Mixin<Customer>` on `contact.Contact`**, not a standalone class — a Person or
  Organization becomes a customer by acquiring this mixin. `Lead.attachedTo` references it.
- `Lead extends task.Task` → inherits `assignee`, `status`, `rank`, `number`, identifier from
  [task](task.md). `Funnel extends task.Project` → its `ProjectType` (`DefaultFunnel`) defines the
  stages and the `Lead` `TaskType`.
- `DefaultFunnelTypeData` / `LeadTypeData` mixins carry project-type-specific attribute data.
- `customerDescription` is a `MarkupBlobRef` (collaborative rich text stored as a blob).

## Notable actions/flows
- Kanban over `Lead` grouped by `status` within a `Funnel`; standard task create/move flows.
- Creating a customer = apply the `Customer` mixin to a contact (`CreateCustomer` icon/flow).
- `ForbidCreateFunnel` permission gates pipeline creation.

## Mobile relevance
Tier 2. Render leads as a kanban/list grouped by pipeline stage (`status`). Note the customer
indirection: to show a lead's customer you resolve `attachedTo` to a `contact.Contact` that has the
`Customer` mixin. Pipeline value/forecast is derived client-side.

## Cross-references
- Plugins: [task](task.md), [contact](contact.md) (Customer mixin target), [tracker](tracker.md)/[board](board.md) (same substrate), [view](view.md), [activity](activity.md)
- Concepts: [data-model](../concepts/data-model.md) (mixins), [transaction-model](../concepts/transaction-model.md)

## Gotchas
- `Customer` is a mixin — querying customers means `findAll(contact.Contact, { ... })` filtered by
  the mixin, or querying the mixin class directly; there is no `Customer` collection table.
- `Lead.attachedTo` points at a `Customer` (mixed-in contact), so resolve through contact.
- `Funnel` is a space; lead visibility follows funnel membership.
