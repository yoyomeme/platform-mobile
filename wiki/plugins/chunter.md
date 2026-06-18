# Chunter (`chunter`)

> Huly's chat app: channels, direct messages, threaded `ChatMessage`s, reactions. Pairs with `activity` and `communication`.

## Where in code
- `plugins/chunter/src/index.ts` -- plugin id (classes/strings/actions); interfaces `Channel`, `DirectMessage`, `ChunterSpace`, `ChatMessage`, `ThreadMessage`
- `plugins/chunter/src/{utils,analytics}.ts` -- helpers
- `models/chunter/src/types.ts` -- model: `@Model` defs, `DOMAIN_CHUNTER`
- `models/chunter/src/{index,notifications,actions}.ts` -- notification types and actions
- `plugins/chunter-resources/` -- Svelte UI (`ChatMessageInput`, `ChatMessagePresenter`, `ThreadView`, `Reactions`)

## Purpose
Chunter is the messaging surface. A **`ChatMessage`** is an `activity.class.ActivityMessage`, so chat reuses the activity engine: a comment on an issue and a message in a channel are the same underlying message type. Channels and DMs are **spaces** (`ChunterSpace`), so membership and access control flow through the standard space model.

## Document classes

| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `ChunterSpace` | `core.class.Space` | `messages?`, `__migratedToCard?` | Abstract base for chat spaces. |
| `Channel` | `chunter.class.ChunterSpace` | `topic?` | A named (public or private) chat channel. |
| `DirectMessage` | `chunter.class.ChunterSpace` | (members only) | A 1:1 / small-group direct conversation. |
| `ChatMessage` | `activity.class.ActivityMessage` | `message: Markup`, `attachments?`, `editedOn?`, `provider?` | A chat message / comment. `attachedTo` is the host doc (channel or any doc). |
| `ThreadMessage` | `chunter.class.ChatMessage` | `attachedTo: Ref<ActivityMessage>`, `objectId`, `objectClass` | A reply inside a thread; attached to a parent message. |
| `ChatMessageViewlet` | `activity.class.ActivityMessageViewlet` | `messageClass`, `label?` | Registers how a message class renders in activity. |
| `ChatSyncInfo` | `core.class.Doc` | `user`, `timestamp` | Per-user read/sync bookkeeping. |

## Key relationships / mixins
- `ChatMessage` is `attachedTo` **any** doc (an issue, a document, or a channel) — chat and inline comments share one type. In a channel, `attachedTo` is the channel space.
- `ThreadMessage.attachedTo` → the parent `ActivityMessage`, with `objectId`/`objectClass` pointing at the root host doc.
- `message: Markup` is **inline** markup (not a blob ref) — render directly.
- Reactions are `activity.class.Reaction` docs (see [activity](activity.md)); presented via `chunter.component.Reactions`.
- `mixin.ObjectChatPanel` — marks a class as having a default chat/comment panel.
- `provider?: Ref<contact.ChannelProvider>` — links a message to an external social channel (Telegram, etc.) for bridged messages.

## Spaces
Each `Channel` / `DirectMessage` **is** a space; messages are scoped by `space`. Membership controls visibility (public channels vs private/DM). Inline comments on non-chunter docs are scoped by that doc's own space.

## Notable actions/flows
- `DeleteChatMessage`, `LeaveChannel`, `RemoveChannel`, `CloseConversation`.
- AI helpers: `TranslateMessage`, `SummarizeMessages`, `ShowOriginalMessage`.
- Sidebar opening: `OpenThreadInSidebar`, `OpenChannelInSidebar` (desktop widget flow).
- Notification types: `DMNotification`, `ThreadNotification`, `ChannelNotification`, `JoinChannelNotification` → feed [inbox](inbox.md).

## Mobile relevance
**Tier-1 MVP** — one of the three highest-value mobile surfaces. Render: channel/DM list, message timeline (markup body, sender avatar via [contact](contact.md), reactions, attachments), thread view, and a composer. Editable: send/edit/delete message, react, reply in thread. New-message delivery and unread counts come through [notification](notification.md)/inbox and `communication`.

## Cross-references
- Built on: [activity](activity.md) (`ActivityMessage`), [communication](../concepts/communication.md)
- Pairs with: [notification](notification.md), [inbox](inbox.md), [contact](contact.md) (senders/avatars), [attachment](attachment.md)
- Concepts: [communication](../concepts/communication.md), [transaction-model](../concepts/transaction-model.md)
- Flows: [notification-flow](../flows/notification-flow.md)

## Gotchas
- `ChatMessage` is an activity message — message history, edits, and reactions ride the activity/transaction pipeline, not a bespoke chat store. Comments on issues/docs are the *same* class.
- Channels/DMs are spaces; "joining" a channel = becoming a space member. Archived channels are read-only (`ViewingArchivedChannel`).
- High-volume message streams are typically delivered through the `communication` channel rather than naïve full re-queries — see [communication](../concepts/communication.md) before building the mobile message feed.
- `editedOn` distinguishes edited messages; `__migratedToCard`/`__migratedUntil` are migration bookkeeping toward the newer `card` model — ignore for rendering.
