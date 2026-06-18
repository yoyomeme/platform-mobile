# Calendar (`calendar`)

> Events, recurring events, reminders, and scheduling. Supports external (Google/CalDAV) calendar sync.

## Where in code
- `plugins/calendar/src/index.ts` -- plugin id (classes/strings); interfaces `Calendar`, `Event`, `ReccuringEvent`, `ReccuringInstance`, `Schedule`, `RecurringRule`
- `plugins/calendar/src/utils.ts` -- recurrence/date helpers
- `models/calendar/src/index.ts` -- model: `@Model` defs, system `Calendar` space
- `plugins/calendar-resources/` -- Svelte UI (`CreateEvent`, `EditEvent`, `CalendarView`, day/week/month views, `DocReminder`)

## Purpose
Calendar models time-based events. An **`Event`** is an `AttachedDoc` (it can be attached to any host doc — e.g. an issue or a contact) carrying a date range, participants, location, reminders, and visibility. **`ReccuringEvent`** adds RFC-5545 recurrence rules; **`ReccuringInstance`** is a materialized occurrence. **`Calendar`** is the container/identity (personal or external), and **`Schedule`** powers bookable availability slots.

## Document classes

| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `Calendar` | `core.class.Doc` | `name`, `hidden`, `visibility: Visibility`, `user: PersonId`, `access: AccessLevel` | A calendar container owned by a user. |
| `ExternalCalendar` | `calendar.class.Calendar` | `default`, `externalId`, `externalUser` | A synced external (Google/CalDAV) calendar. |
| `Event` | `core.class.AttachedDoc` | `eventId`, `title`, `description: Markup`, `calendar: Ref<Calendar>`, `date`, `dueDate`, `allDay`, `participants: Ref<Contact>[]`, `reminders?: Timestamp[]`, `location?`, `visibility?`, `access`, `user`, `blockTime`, `timeZone?` | A scheduled event; `space` is the system `Calendar` space. |
| `ReccuringEvent` | `calendar.class.Event` | `rules: RecurringRule[]`, `exdate[]`, `rdate[]`, `originalStartTime`, `timeZone` | A recurring event definition (RFC-5545). |
| `ReccuringInstance` | `calendar.class.ReccuringEvent` | `recurringEventId`, `originalStartTime`, `isCancelled?`, `virtual?` | A single occurrence of a recurring event. |
| `Schedule` | `core.class.Doc` | `owner: Ref<Employee>`, `title`, `meetingDuration`, `meetingInterval`, `availability: ScheduleAvailability`, `timeZone`, `calendar?` | Bookable availability (Calendly-style). |
| `PrimaryCalendar` | `preference.class.Preference` | `attachedTo: Ref<Calendar>` | Per-user primary-calendar preference. |

### Enums / types
- `Visibility`: `public` \| `freeBusy` \| `private`.
- `AccessLevel`: FreeBusyReader, Reader, Writer, Owner.
- `RecurringRule`: RFC-5545 fields (`freq`, `interval`, `byDay`, `count`, `endDate`, …).

## Key relationships / mixins
- `Event.participants` are `Ref<Contact>` → resolved via [contact](contact.md).
- `Event` is an `AttachedDoc`, so events can hang off other docs (meetings on an issue, birthdays on a person).
- `calendar.mixin.CalendarEventPresenter` registers per-class event rendering.
- Reminders are a `Timestamp[]` on the event; the `ReminderNotification` type fires inbox/push alerts.
- External sync: `calendarIntegrationKind` (`google-calendar`), `caldavIntegrationKind` (`caldav`), plus `CalendarServiceURL`/`CalDavServerURL` metadata.

## Spaces
Events live in the seeded system `calendar.space.Calendar` (`SystemSpace`); per-user scoping is via the `user`/`calendar` fields and `access`, not a per-user space.

## Notable actions/flows
- `CreateEvent`, `EditEvent`; recurring-event editing (this/all occurrences).
- Reminder delivery via `calendar.ids.ReminderNotification`.
- Meeting scheduling notifications: `MeetingScheduled/Rescheduled/Canceled`.
- External account connect/disconnect (`ConnectApp`, `DisconnectHandler`).

## Mobile relevance
**Tier-1 (productivity tier).** Render: day/week/month views and an agenda list of upcoming `Event`s; event detail (time, participants, location, description). Editable: create/edit events, set reminders, RSVP. Recurrence expansion (`ReccuringInstance`/`virtual`) and timezone handling are the main complexity — reuse `plugins/calendar/src/utils.ts` logic. External sync is a later phase.

## Cross-references
- Participants: [contact](contact.md)
- Related personal-time: [time](time.md) (`WorkSlot extends Event`)
- Notifications: [notification](notification.md), [inbox](inbox.md)
- Concepts: [data-model](../concepts/data-model.md), [event-queue](../concepts/event-queue.md)

## Gotchas
- Recurring events are not pre-expanded in storage — you must compute occurrences from `rules`/`rdate`/`exdate` at read time (`virtual` instances). Don't expect one doc per occurrence.
- `Event.date`/`dueDate` plus `timeZone` define the range; all-day events (`allDay`) need timezone-safe date math.
- Events are `AttachedDoc`s on a shared system space — filter by `user`/`calendar`/`access`, not by space alone.
- [time](time.md)'s `WorkSlot` extends `Event`, so planner time-blocks show up as calendar events too.
