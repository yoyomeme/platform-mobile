# HR (`hr`)

> Human Resources: org-chart `Department`s of `Staff`, with time-off `Request`s (PTO/sick/leave) and `PublicHoliday`s.

## Where in code
- `plugins/hr/src/index.ts` -- plugin id (`hrId = 'hr'`), interfaces, class/mixin/id definitions
- `plugins/hr/src/utils.ts` -- `TzDate` helpers
- `models/hr/src/index.ts` -- model (`TDepartment`, `TRequest`, `TRequestType`, `TPublicHoliday`, `Staff` mixin, viewlets, default request types)
- `plugins/hr-resources/` -- UI (department tree, schedule/calendar, request popups)

## Purpose
Models an organization's people structure and leave tracking. `Department`s form a tree; `Staff` is
a **mixin on `contact.Employee`** assigning a person to a department; `Request`s are dated time-off
entries (vacation, sick, PTO, leave, remote, overtime) attached to a staff member. Tier-2 mobile
feature.

## Document classes
| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `Department` | `core.Doc` | `name`, `description`, `parent?: Ref<Department>`, `teamLead`, `members: Ref<Employee>[]`, `managers`, `subscribers?`, `avatar?` | An org-chart node (tree via `parent`). |
| `Staff` (mixin) | `contact.Employee` | `department: Ref<Department>` | Assigns an employee to a department. |
| `Request` | `core.AttachedDoc` | `attachedTo: Ref<Staff>`, `department`, `type: Ref<RequestType>`, `description: Markup`, `tzDate`, `tzDueDate`, `comments?`, `attachments?` | A time-off request spanning `tzDate`→`tzDueDate`. |
| `RequestType` | `core.Doc` | `label`, `icon`, `value`, `color` | A kind of leave (Vacation, Sick, PTO, Leave, Remote, Overtime); `value` weights the balance. |
| `PublicHoliday` | `core.Doc` | `title`, `description`, `date: TzDate`, `department` | A holiday for a department. |
| `TzDate` (type) | -- | `year`, `month`, `day`, `offset` | Timezone-anchored date (UTC offset) used by requests/holidays. |

## Key relationships / mixins
- `Staff` is a **`Mixin` on `contact.Employee`** — an employee joins HR by acquiring this mixin with
  a `department`. There is no separate "staff" collection.
- `Department` is a tree (`parent`); `members`/`managers` are `Employee` refs. The root department is
  `hr.ids.Head`.
- `Request` is an `AttachedDoc` on a `Staff` (so it's a collection on the employee) and also carries a
  `department` for rollups; `type` references a `RequestType`.
- Default `RequestType`s (`Vacation`, `Leave`, `Sick`, `PTO`, `PTO2`, `Remote`, `Overtime`,
  `Overtime2`) are seeded by the model with fixed `value`/`color`.
- Notifications: create/update/remove-request and create-public-holiday `NotificationType`s.

## Notable actions/flows
- Schedule view: per-department calendar of requests + public holidays; `StaffStats`/`TableMember`
  viewlets show balances per employee.
- Creating leave = add a `Request` (collection on the `Staff`) with a `type` and `tzDate`/`tzDueDate`;
  balances are computed from `RequestType.value` across requests.

## Mobile relevance
Tier 2. Useful read-only mobile surface: my requests, team schedule, who's off today, public
holidays. Submitting a request = one `addCollection` on the `Staff`. **All dates are `TzDate`
(year/month/day + UTC offset), not JS timestamps** — convert carefully on mobile.

## Cross-references
- Plugins: [contact](contact.md) (Staff mixin target / Employee), [calendar](calendar.md), [activity](activity.md), [attachment](attachment.md)
- Concepts: [data-model](../concepts/data-model.md) (mixins), [transaction-model](../concepts/transaction-model.md)

## Gotchas
- `TzDate` is a custom date triple with an `offset`, stored "always in UTC" — do not treat it as a
  millisecond timestamp; off-by-a-day timezone bugs are the classic failure here.
- `Staff` is a mixin on `Employee`; query employees filtered by the mixin to list a department's staff.
- `Request.department` is denormalized alongside `attachedTo` — keep consistent if a staff member moves.
- Leave balances aren't stored; they're derived from `RequestType.value` summed over `Request`s.
