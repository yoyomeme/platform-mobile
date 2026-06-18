# Communication Subsystem

> The `foundations/communication` engine that powers messaging, threads, reactions, notifications, the inbox, and collaborators — built around **cards**, **messages**, and an event-sourced API.

## Where in code

| Component | File | Purpose |
|-----------|------|---------|
| Core type aliases | `foundations/communication/packages/types/src/core.ts` | `CardID`, `BlobID`, `Markdown`, `SocialID`, `AccountUuid` |
| Message model | `foundations/communication/packages/types/src/message.ts` | `Message`, `MessageType`, reactions, attachments, threads |
| Notification model | `foundations/communication/packages/types/src/notification.ts` | `Notification`, `NotificationContext`, `Collaborator` |
| Find client interface | `foundations/communication/packages/sdk-types/src/client.ts` | `FindClient` read + subscribe API |
| Events | `foundations/communication/packages/sdk-types/src/events/` | message / notification / label / card / peer events |
| REST client | `foundations/communication/packages/rest-client/src/rest.ts` | HTTP `event` + `find*` over `/api/v1/...` |
| Server API | `foundations/communication/packages/server/src/index.ts` | `Api` class wiring middlewares + db |
| CockroachDB adapter | `foundations/communication/packages/cockroach/src/` | persistence (schema, adapter) |
| Reactive query | `foundations/communication/packages/query/` | live queries over messages/notifications |

## Purpose

Chat and notifications do not fit cleanly into the generic `Doc`/`Tx` model: a busy channel produces thousands of messages, reactions, and edits per card, and the inbox must aggregate notifications across every app. The **communication** subsystem is a purpose-built engine for this high-write, high-read workload. It is enabled by the `COMMUNICATION_API_ENABLED` flag and runs alongside the transactor, sharing the same CockroachDB and the same Tx event queue.

Its central abstraction is the **card**: any document (a chat channel, an issue, a document, a contact) can be a card that carries a stream of messages. Chunter (chat) is the primary consumer, but threads, activity feeds, and the inbox all build on the same message/notification primitives.

## Details

### Core identifiers

The subsystem uses its own branded id aliases that map onto core platform types:

```typescript
export type BlobID = Ref<Blob>
export type CardID = Ref<any>     // any Doc can be a "card"
export type CardType = Ref<any>   // the card's _class
export type SocialID = PersonId   // who authored an action
export type Markdown = string     // message bodies are Markdown, not Markup
export type ID = string
```

Note messages store **Markdown**, distinct from the ProseMirror **Markup** used by collaborative documents (see [collaboration-crdt](collaboration-crdt.md)).

### The Message model

```typescript
export enum MessageType { Text = 'text', Activity = 'activity' }

export interface Message {
  id: MessageID
  cardId: CardID
  type: MessageType
  content: Markdown
  extra?: MessageExtra
  language?: string

  creator: SocialID
  created: Date
  modified?: Date

  reactions: Record<Emoji, EmojiData[]>
  attachments: Attachment[]
  threads: Thread[]
  translates?: Record<string, Markdown>
}
```

Key sub-structures:

- **Reactions** — `Record<Emoji, EmojiData[]>`, each `EmojiData` carrying `{ count, person, date }`.
- **Attachments** — a union of `BlobAttachment` (a file blob, see [storage-blobs](storage-blobs.md)), `LinkPreviewAttachment` (`application/vnd.huly.link-preview`), and `AppletAttachment` (`application/vnd.huly.applet.*`). All carry `{ id, mimeType, params, creator, created }`.
- **Threads** — a reply chain pointing from a parent `messageId` to a child `threadId` card, with `repliesCount`, `lastReplyDate`, and `repliedPersons`.
- **Translations** — `translates` holds per-language rendered copies.

**Activity messages** are a specialization used for the per-card change feed (the "X changed status to Done" entries):

```typescript
export interface ActivityMessage extends Message {
  type: MessageType.Activity
  extra: ActivityMessageExtra   // { action: 'create'|'remove'|'update', update?: ActivityUpdate }
}
```

`ActivityUpdate` is a discriminated union (`Attribute`, `Tag`, `Collaborators`, `Type`, `Process`, `CollaborativeChange`) describing exactly what changed — this is how the activity plugin renders structured diffs rather than free text.

### Messages are grouped into blobs

To avoid keeping every message as an individual row forever, older messages are rolled up:

```typescript
export interface MessagesGroup {
  cardId: CardID
  blobId: BlobID     // a blob holding a batch of messages
  fromDate: Date
  toDate: Date
  count: number
}
```

`findMessagesGroups` returns these archive windows; `findMessagesMeta` returns lightweight `MessageMeta` (`id, cardId, created, creator, blobId`). Clients page through recent live messages, then fetch grouped blobs for history.

### The Notification / Inbox model

```typescript
export interface Notification {
  id: NotificationID
  cardId: CardID
  contextId: ContextID
  account: AccountUuid
  type: NotificationType        // 'message' | 'reaction'
  read: boolean
  created: Date
  content: NotificationContent  // { title, shortText, senderName, ... }
  messageId: MessageID
  creator: SocialID
  blobId: BlobID
  message?: Message
}

export interface NotificationContext {
  id: ContextID
  cardId: CardID
  account: AccountUuid
  lastUpdate: Date
  lastView: Date
  lastNotify?: Date
  notifications?: Notification[]
  totalNotifications?: number
}
```

A **`NotificationContext`** is the per-(account, card) inbox row: it tracks `lastView` vs `lastUpdate` (unread state) and aggregates the notifications for that card. The inbox UI lists contexts; opening one shows its notifications. **`Collaborator`** (`{ cardId, cardType, account }`) records who follows a card and therefore receives notifications.

### Read API — `FindClient`

Reads and subscriptions go through `FindClient`:

```typescript
export interface FindClient {
  onEvent: (event: Event) => void
  onRequest: (event: Event, promise: Promise<EventResult>) => void

  findMessagesMeta: (params: FindMessagesMetaParams) => Promise<MessageMeta[]>
  findNotificationContexts: (params: FindNotificationContextParams, queryId?: number) => Promise<NotificationContext[]>
  findNotifications: (params: FindNotificationsParams, queryId?: number) => Promise<WithTotal<Notification>>
  findLabels: (params: FindLabelsParams, queryId?: number) => Promise<Label[]>
  findCollaborators: (params: FindCollaboratorsParams, queryId?: number) => Promise<Collaborator[]>

  subscribeCard: (cardId: CardID, subscription: string | number) => Promise<void>
  unsubscribeCard: (cardId: CardID, subscription: string | number) => Promise<void>
}
```

`subscribeCard` registers interest in a card so that subsequent events for it are delivered via `onEvent` — this is the live-update mechanism for chat.

### Write API — events

All mutations are **events**, not direct CRUD. The union of every event type:

```typescript
export type Event = MessageEvent | NotificationEvent | LabelEvent | CardEvent | PeerEvent
export type EventResult = MessageEventResult | NotificationEventResult | {}
```

Message events:

```typescript
export enum MessageEventType {
  CreateMessage   = 'createMessage',
  UpdatePatch     = 'updatePatch',
  RemovePatch     = 'removePatch',
  ReactionPatch   = 'reactionPatch',
  BlobPatch       = 'blobPatch',       // @deprecated → AttachmentPatch
  AttachmentPatch = 'attachmentPatch',
  ThreadPatch     = 'threadPatch',
  TranslateMessage = 'translateMessage'
}
```

Editing a message, adding a reaction, attaching a file, or adding a thread reply are all **patch** events against an existing message. Notification events cover the inbox side:

```typescript
export enum NotificationEventType {
  AddCollaborators = 'addCollaborators',
  RemoveCollaborators = 'removeCollaborators',
  CreateNotification = 'createNotification',
  RemoveNotifications = 'removeNotifications',
  UpdateNotification = 'updateNotification',
  CreateNotificationContext = 'createNotificationContext',
  RemoveNotificationContext = 'removeNotificationContext',
  UpdateNotificationContext = 'updateNotificationContext'
}
```

`UpdateNotificationContext` is how "mark as read" works — it advances `lastView`.

### Transport: REST client

The `RestClient` sends events as wrapped transactions and exposes the same `find*` reads over HTTP:

```typescript
async event (event: Event, socialId: SocialID): Promise<EventResult> {
  const response = await fetch(concatLink(this.endpoint, `/api/v1/tx/${this.workspace}`), {
    method: 'POST',
    body: JSON.stringify(this.wrapEvent(event, socialId))  // → TxDomainEvent
  })
  // ...
}
```

Reads hit `/api/v1/request/communication/{operation}/{workspace}?...`. An event is wrapped into a **`TxDomainEvent`** — so a communication mutation is carried on the very same `DOMAIN_TX` / Tx queue as ordinary platform transactions. That is why the fulltext indexer can consume `TxDomainEvent<QueueSourced<Event>>` off the Tx topic to index chat messages (see [fulltext-search](fulltext-search.md)).

### Server side

```typescript
export class Api implements ServerApi {
  static async create (ctx, workspace, dbUrl, callbacks): Promise<Api> {
    const db = await createDbAdapter(dbUrl, workspace, ctx, { withLogs: ... })
    const blob = new Blob(ctx, workspace, metadata)
    const client = new LowLevelClient(db, blob, metadata, workspace)
    const middleware = await buildMiddlewares(ctx, workspace, metadata, client, callbacks)
    return new Api(ctx, middleware)
  }
  // findMessagesMeta / findNotifications / findCollaborators / subscribeCard ... delegate to middlewares
}
```

The server is a **middleware pipeline** over a CockroachDB adapter (`packages/cockroach`). Each `find*` and `subscribeCard` delegates through `Middlewares`, which apply access control, materialize groups, and fan out subscriptions.

```
client (chunter UI)
  │ event(CreateMessage)            find*(...) / subscribeCard
  ▼                                       ▼
RestClient ── POST /api/v1/tx/ws ──▶ communication server Api
                                          │
                                  Middlewares pipeline
                                          │
                                  CockroachDB adapter ──▶ CockroachDB
                                          │
                                  TxDomainEvent ──▶ Tx queue ──▶ fulltext / inbox
```

## Cross-references

- [storage-blobs](storage-blobs.md) — `BlobAttachment` and message-group archives reference blob IDs
- [collaboration-crdt](collaboration-crdt.md) — messages are Markdown; rich docs use CRDT Markup
- [fulltext-search](fulltext-search.md) — chat messages are indexed via `TxDomainEvent` on the Tx topic
- [event-queue](event-queue.md) — communication events ride the shared `tx` topic
- Plugins: [chunter](../plugins/chunter.md), [notification](../plugins/notification.md), [inbox](../plugins/inbox.md)
- Flow: [notification-flow](../flows/notification-flow.md)

## Gotchas

- **`COMMUNICATION_API_ENABLED` gates the whole subsystem.** When off, chat/inbox features fall back or are unavailable.
- **Messages are Markdown, documents are Markup.** Don't run a chat body through the collaborator/Y.js path — they are different text representations.
- **Edits are patches, not replacements.** To change a message you emit `UpdatePatch`/`ReactionPatch`/`AttachmentPatch` against its `MessageID`; there is no "overwrite the message" operation.
- **`BlobPatch` is deprecated** — use `AttachmentPatch` for new code.
- **History lives in blobs.** Old messages are rolled into `MessagesGroup` blobs; a client that only reads live rows will miss history until it fetches the grouped blobs.
- **`CardID`/`CardType` are `Ref<any>`.** Any platform `Doc` can be a card, so the type system won't constrain which document you attach messages to — validate at the application layer.
