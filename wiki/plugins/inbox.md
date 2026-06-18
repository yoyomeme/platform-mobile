# Inbox (`inbox`)

> The unified inbox surface — the workbench app that renders all cross-app notifications. A thin presentation layer over the `notification` engine.

## Where in code
- `plugins/inbox/src/index.ts` -- plugin id (minimal: `Inbox` string + icon only)
- `models/inbox/src/index.ts` -- model: registers the `Inbox` `workbench.class.Application` (alias `inbox`, `InboxApplication` component, top position)
- `models/inbox/src/plugin.ts` -- model plugin (`app.Inbox`, `component.InboxApplication`)
- `plugins/inbox-resources/` -- Svelte UI: `InboxApplication`, `InboxNavigation`, `InboxCard`, `InboxNotification`, `MessageNotification`, `ReactionNotification`, `ModernNotifications`

## Purpose
`inbox` is intentionally small: it owns **no document classes of its own**. It is the workbench *application* (the left-rail entry and the inbox screen) that consumes [notification](notification.md)'s `DocNotifyContext` and `InboxNotification` data through the `InboxNotificationsClient` stores and renders them as a single, app-agnostic activity feed.

Think of the split as: **`notification` = data/engine, `inbox` = the screen.**

## Document classes
None. The inbox renders documents owned by [notification](notification.md):

| Rendered class | Owner | Role in inbox |
|---|---|---|
| `DocNotifyContext` | notification | One inbox "card"/row per tracked document. |
| `InboxNotification` (+ `ActivityInboxNotification`, `CommonInboxNotification`, `MentionInboxNotification`, `ReactionInboxNotification`) | notification | The individual notification entries inside each context. |

The model contribution is a single `workbench.class.Application` doc (`inbox.app.Inbox`) plus a few intl strings — it is wiring, not schema.

## Key relationships / mixins
- Pulls reactive stores from `notification.function.GetInboxNotificationsClient` (`InboxNotificationsClient`): `contexts`, `inboxNotificationsByContext`, plus `readDoc` / `archiveNotifications` actions.
- Per-class rendering of the notified object uses the `notification` presenter mixins (`NotificationObjectPresenter`, `NotificationPreview`, `NotificationContextPresenter`).
- Message/reaction entries route to [chunter](chunter.md) and [activity](activity.md) presenters.

## Spaces
Inherits scope from notification: all data is read from the current user's `contact.PersonSpace`. The inbox itself is a workbench application, not a space.

## Notable actions/flows
- Open a context → mark its doc read (`readDoc`), navigate to the source object via `onClickLocation`/resolvers.
- Pin/read/archive a context (delegated to `notification.action.*`).
- Bulk read-all / archive-all.
- Filtering between activity notifications, mentions, and reactions (`InboxViewSettings`).

## Mobile relevance
**Tier-1 — the recommended mobile home screen.** This is the single most valuable mobile surface: a unified feed of "things that need you" across Chunter, Tracker, comments, mentions, and reactions. Mobile should reimplement `InboxApplication`'s behavior natively: subscribe to the inbox client stores, group by `DocNotifyContext`, render per-type rows, and support tap-to-open + mark-read/archive. Pair with push registration (see [notification](notification.md)).

## Cross-references
- Engine: [notification](notification.md)
- Sources: [chunter](chunter.md), [tracker](tracker.md), [activity](activity.md)
- Concepts: [transaction-model](../concepts/transaction-model.md), [communication](../concepts/communication.md), [plugin-architecture](../concepts/plugin-architecture.md)
- Flows: [notification-flow](../flows/notification-flow.md)

## Gotchas
- Do not look for inbox document classes — there are none. All persistence is in [notification](notification.md); `inbox` is purely the app shell + presenters.
- The workbench `Application` is registered `hidden: true` with `position: 'top'` — it is surfaced specially in navigation, not as an ordinary app entry.
- Read/unread and archive state live on the notification docs, so mobile and web inboxes stay in sync automatically through the same `PersonSpace` data.
