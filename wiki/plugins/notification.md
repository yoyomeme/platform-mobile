# Notification (`notification`)

> The cross-app notification engine: `DocNotifyContext`, `InboxNotification`, notification types/groups, and delivery providers (inbox, push, sound). Powers the unified inbox.

## Where in code
- `plugins/notification/src/index.ts` -- plugin id (classes/mixins/providers/strings); interfaces `DocNotifyContext`, `InboxNotification` (+ subtypes), `NotificationType`, `NotificationProvider`, `Collaborators`
- `plugins/notification/src/{types,serviceWorker}.ts` -- store types + push service worker
- `models/notification/src/index.ts` -- model: `@Model` defs, domains `notification`, `notification-dnc`, `notification-user`
- `plugins/notification-resources/` -- Svelte UI (`Inbox`, `NotificationPresenter`, preference editors)

## Purpose
Notification is the fan-out layer that turns transactions (a comment added, an issue assigned, a collaborator added) into per-user, per-document notifications. It models:

- **What** can notify: `NotificationType` (rules matched against transactions), grouped by `NotificationGroup`.
- **Where** a user is notified: `NotificationProvider` (Inbox, Push, Sound) with per-user `NotificationProviderSetting` / `NotificationTypeSetting` preferences.
- **Per-document context**: `DocNotifyContext` (one per user+doc) tracking pinned/hidden/last-viewed.
- **Per-user notifications**: `InboxNotification` and its subtypes, scoped to a `PersonSpace`.

## Document classes

| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `DocNotifyContext` | `core.class.Doc<PersonSpace>` | `user: AccountUuid`, `objectId`, `objectClass`, `objectSpace`, `isPinned`, `hidden`, `lastViewedTimestamp?`, `lastUpdateTimestamp?` | One per user+tracked-doc; the inbox "row" for a document. |
| `InboxNotification` | `core.class.Doc<PersonSpace>` | `user`, `isViewed`, `archived`, `docNotifyContext`, `objectId`, `objectClass`, `types?` | Base per-user notification. |
| `ActivityInboxNotification` | `InboxNotification` | `attachedTo: Ref<ActivityMessage>` | Notification triggered by an activity message (comment/chat). |
| `CommonInboxNotification` | `InboxNotification` | `header?`, `message?`, `icon?`, `props?` | Generic notification with custom presentation. |
| `MentionInboxNotification` | `CommonInboxNotification` | `mentionedIn`, `mentionedInClass` | An @-mention. |
| `ReactionInboxNotification` | `CommonInboxNotification` | `emoji`, `ref: Ref<Reaction>`, `attachedTo` | Someone reacted to your message. |
| `NotificationType` | `core.class.Doc` | `label`, `group`, `txClasses`, `objectClass`, `field?`, `txMatch?`, `defaultEnabled`, `allowedForAuthor?` | A rule that turns matching txes into notifications. |
| `NotificationProvider` | `core.class.Doc` | `label`, `defaultEnabled`, `canDisable`, `order`, `depends?` | A delivery channel (inbox/push/sound). |
| `NotificationGroup` | `core.class.Doc` | `label`, `icon`, `objectClass?` | Groups notification types for settings UI. |
| `BrowserNotification` | `core.class.Doc` | `user`, `title`, `body`, `objectId`, `onClickLocation?`, `soundAlert` | A queued browser/OS notification. |
| `PushSubscription` | `core.class.Doc` | `user`, `endpoint`, `keys` | Web-push subscription endpoint. |

### Mixins
| Mixin | On | Purpose |
|---|---|---|
| `Collaborators` | any `Doc` | Holds `collaborators: CollectionSize<Collaborator>` — who follows a doc. |
| `NotificationObjectPresenter` / `NotificationPreview` / `NotificationContextPresenter` | `Class<Doc>` | Register how a notified object renders in the inbox. |

### Providers (`notification.providers.*`)
`InboxNotificationProvider`, `PushNotificationProvider`, `SoundNotificationProvider`. `notification.integrationType.MobileApp` exists for registering a mobile push integration.

## Key relationships / mixins
- The **`Collaborators` mixin** is the subscription mechanism: a user becomes a collaborator on a doc, then matching txes generate `InboxNotification`s for them.
- `InboxNotification` → `DocNotifyContext` (`docNotifyContext`) → the tracked doc (`objectId`/`objectClass`).
- `InboxNotificationsClient` (a Resource factory) exposes reactive stores + `readDoc`, `readNotifications`, `archiveNotifications`, etc.
- Both `DocNotifyContext` and `InboxNotification` are scoped to a `contact.PersonSpace` (per-user private space).

## Spaces
Lives in the user's `PersonSpace`. The three domains (`notification`, `notification-dnc`, `notification-user`) separate browser notifications, doc-notify contexts, and user notifications for storage/perf.

## Notable actions/flows
- Context actions: `PinDocNotifyContext`, `ReadNotifyContext`, `ArchiveContextNotifications`.
- Bulk: `readAllNotifications`, `archiveAllNotifications`, `unreadAllNotifications`.
- Push delivery via `serviceWorker.ts` + `PushSubscription` + `notification.metadata.PushPublicKey`.

## Mobile relevance
**Tier-1 — the engine behind the mobile home surface.** Mobile must: subscribe to the `InboxNotificationsClient` stores, render notifications grouped by `DocNotifyContext`, mark read/unread/archive, and register a `PushSubscription` for OS push (the `MobileApp` integration type is the hook). The actual list UI is [inbox](inbox.md).

## Cross-references
- Surface: [inbox](inbox.md)
- Sources: [chunter](chunter.md), [tracker](tracker.md), [activity](activity.md) (messages/reactions), [contact](contact.md) (`PersonSpace`, collaborators)
- Concepts: [transaction-model](../concepts/transaction-model.md), [collaboration-crdt](../concepts/collaboration-crdt.md), [communication](../concepts/communication.md)
- Flows: [notification-flow](../flows/notification-flow.md), [collaboration-flow](../flows/collaboration-flow.md)

## Gotchas
- `InboxNotification` / `DocNotifyContext` live in the **`PersonSpace`** of the recipient — query by your own person space, not the source doc's space.
- A user only gets notifications for docs they **collaborate** on (via the `Collaborators` mixin) and for types they haven't disabled — both must be checked.
- `NotificationType.txMatch`/`txClasses`/`field` describe how server triggers match transactions; mobile consumes the resulting `InboxNotification`s, it does not re-evaluate the rules.
- Read state is split: `DocNotifyContext.lastViewedTimestamp` (doc-level) vs `InboxNotification.isViewed`/`archived` (per-notification).
