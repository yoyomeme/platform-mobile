# Notification Flow

> How a write turns into a notification: a CUD `Tx` fires server-side notification triggers, which generate `DocNotifyContext` + `InboxNotification` docs (themselves derived `Tx`es), broadcast them to recipients' clients, and — for offline/background delivery — push to the web-push service. The client's **Inbox** is just a live query over those notification docs.

## Where in code
- `server-plugins/notification-resources/src/index.ts` -- triggers: `createCollabDocInfo`, `getNotificationTxes`, `pushActivityInboxNotifications`, `pushInboxNotifications`, `createNotifyContext`
- `server-plugins/notification-resources/src/push.ts` -- `PushNotificationsHandler`, `createPushNotification`, `sendPushToSubscription` (`POST {pushURL}/web-push`)
- `plugins/notification/src/index.ts` -- `DocNotifyContext`, `InboxNotification`, `PushSubscription`, `BrowserNotification`, `InboxNotificationsClient`

## Sequence

```
 Author Client      Transactor (triggers)              Recipient Client        Push Service
     |                    |                                  |                       |
     | tx(TxCreateDoc)    |                                  |                       |
     |------------------->| persist + run notification       |                       |
     |                    | triggers:                        |                       |
     |                    |  - resolve collaborators          |                       |
     |                    |  - getNotificationTxes →          |                       |
     |                    |    TxCreateDoc<DocNotifyContext>  |                       |
     |                    |    TxCreateDoc<InboxNotification> |                       |
     |                    |                                  |                       |
     |                    | broadcast Tx[] (original+derived)|                       |
     |                    |--------------------------------->| live query over        |
     |                    |                                  | InboxNotification fires|
     |                    |                                  | → Inbox badge/list     |
     |                    |                                  |                       |
     |                    | PushNotificationsHandler: find    |                       |
     |                    | recipient PushSubscriptions →     |                       |
     |                    | POST {pushURL}/web-push  ---------------------------------->| FCM/APns/WebPush
     |                    |                                  |  (background delivery)  |
```

## Steps

| Step | Action | Error code on failure |
|------|--------|----------------------|
| 1 | A client commits a CUD tx (create issue, post message, mention, react...). See [transaction-flow](transaction-flow.md). | |
| 2 | Transactor persists it and runs notification triggers; collaborators of the target doc are resolved. | |
| 3 | For each recipient with no existing context, `createNotifyContext` emits `TxCreateDoc<DocNotifyContext>` (keyed by `objectId` + recipient account, in the recipient's `PersonSpace`). | |
| 4 | `pushInboxNotifications` / `pushActivityInboxNotifications` emit `TxCreateDoc<InboxNotification>` (`user`, `isViewed:false`, `docNotifyContext`, `objectId`, `objectClass`, `types`). | |
| 5 | These derived txes are **broadcast** alongside the original tx to all affected sessions. | |
| 6 | The recipient's client receives them; its **Inbox** live query over `InboxNotification` re-fires, updating the unread badge and list. | |
| 7 | `PushNotificationsHandler` looks up the recipient's `PushSubscription` docs and `POST {pushURL}/web-push` for background/offline delivery (skipped if `WebPushUrl` is unset). | push 4xx/5xx |
| 8 | User opens Inbox; reading marks notifications via `readNotifications` (a tx setting `isViewed`/archived) — which itself broadcasts and clears the badge. | |

## Code

```typescript
// CLIENT SIDE: the Inbox is a live query — no special notification API.
import notification from '@hcengineering/notification'

const unsubscribe = lq.query(
  notification.class.InboxNotification,
  { user: me.uuid, isViewed: false, archived: false },
  (items) => updateInboxBadge(items.length) // re-fires on every new/changed notification tx
)

// Mark as read (a normal tx, broadcast back like any write):
await ops.updateDoc(
  notification.class.InboxNotification, n.space, n._id, { isViewed: true }
)

// To receive BACKGROUND push, register a PushSubscription doc once:
await ops.createDoc(notification.class.PushSubscription, mySpace, {
  user: me.uuid,
  endpoint: subscription.endpoint,
  keys: { p256dh, auth }
})
```

## Prerequisites

- A ready client + Inbox live query (see [model-load-flow](model-load-flow.md), [live-query-flow](live-query-flow.md)).
- The user is a **collaborator** of the target doc (notifications are generated per resolved collaborator).
- For background push: a registered `PushSubscription`, plus the server configured with a web-push URL (`WebPushUrl`) and `PUSH_PUBLIC_KEY` exposed in `config.json`.

## Error handling

```typescript
// Server-side: if WebPushUrl is unset/empty, createPushNotification returns early —
// in-app (broadcast) notifications still work; only background push is skipped.
//
// Failed/expired subscriptions: sendPushToSubscription collects the PushSubscription refs
// that the push service reports as gone, and the trigger removes those stale docs.

// Client-side: foreground delivery is just the live query — guard the Inbox UI for an
// empty/loading state until the first callback fires.
```

## Cross-references

- [transaction-flow](transaction-flow.md) -- the originating write + how derived txes broadcast
- [live-query-flow](live-query-flow.md) -- the Inbox surface is a live query
- [communication](../concepts/communication.md) -- chat messages are a common notification source
- Service: [transactor](../services/transactor.md)
- Types: [tx-types](../types/tx-types.md), [core-types](../types/core-types.md)

## Gotchas

- **Notifications are just docs.** `DocNotifyContext` and `InboxNotification` are ordinary `Doc`s created by derived txes; there is no separate notification protocol. The Inbox is a live query — implement it like any other reactive view.
- **Generation is server-side.** The client does not create its own notifications for others; the transactor's triggers do, based on collaborators of the target doc. A `createDoc` may therefore broadcast extra notification txes you didn't issue.
- **Two delivery paths.** Foreground = broadcast `Tx[]` over the existing WS (instant, no push service). Background = `POST /web-push` to hulypulse/the push service. A mobile client gets in-app updates from the WS while connected and needs FCM/APNs for background.
- **`DocNotifyContext` groups by doc + user.** One context per `(objectId, recipient)`; multiple `InboxNotification`s hang off it. The context is reused (not recreated) on subsequent activity.
- **Recipient space.** Notification docs live in the recipient's `PersonSpace` (`Doc<PersonSpace>`), so a client only ever queries its own notifications.
- **Reading is a write.** Marking read/archived is a tx (`isViewed`/archived), broadcast back — so unread counts stay consistent across the user's devices.
- **Push config is optional.** If `WebPushUrl`/`PUSH_PUBLIC_KEY` aren't configured, in-app notifications still function; only background push is disabled.
```