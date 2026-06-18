# Communication types

> The public message/notification/card subsystem types from `@hcengineering/communication-types`. This is a newer subsystem with its own id model (branded `ID` strings, `Date` timestamps) that sits alongside — and references — the core data model.

## Where in code

- `foundations/communication/packages/types/src/core.ts` -- base ids (`ID`, `CardID`, `CardType`, `SocialID`, `BlobID`, `Markdown`)
- `foundations/communication/packages/types/src/message.ts` -- `Message`, `MessageType`, `Attachment`, `Thread`, reactions, activity updates
- `foundations/communication/packages/types/src/notification.ts` -- `Notification`, `NotificationContext`, `Collaborator`
- `foundations/communication/packages/types/src/label.ts` -- `Label`
- `plugins/card/src/index.ts` -- `Card` (a core `Doc`; the entity messages attach to)

## Definition

```typescript
// Base ids. Note: communication ids are bare/branded strings, and CardID/CardType
// bridge to the core model as Ref<...>.
export type ID = string
export type BlobID = Ref<Blob>
export type CardID = Ref<any>   // points at a core Card doc
export type CardType = Ref<any> // points at a MasterTag (the card's class)
export type SocialID = PersonId // the actor; same brand as core PersonId
export type Markdown = string
```

```typescript
export type MessageID = ID & { message: true }
export type Emoji = string & { emoji: true }

export enum MessageType {
  Text = 'text',
  Activity = 'activity'
}

export interface Message {
  id: MessageID
  cardId: CardID
  type: MessageType
  content: Markdown
  extra?: MessageExtra        // Record<string, any>
  language?: string
  creator: SocialID
  created: Date
  modified?: Date
  reactions: Record<Emoji, EmojiData[]>
  attachments: Attachment[]
  threads: Thread[]
  translates?: Record<string, Markdown> // language -> translated content
}

export interface EmojiData {
  count: number
  person: PersonUuid
  date: Date
}

// Activity (system) messages describe a change to the card.
export interface ActivityMessage extends Message {
  type: MessageType.Activity
  extra: ActivityMessageExtra // { action: 'create'|'remove'|'update', update?: ActivityUpdate }
}
```

```typescript
// Attachments are a tagged union keyed by mimeType.
export type Attachment = BlobAttachment | LinkPreviewAttachment | AppletAttachment

export interface AttachmentData<P extends AttachmentParams = AttachmentParams> {
  id: AttachmentID  // string & { __attachmentId: true }
  mimeType: string
  params: P
}
export interface BlobAttachment extends BaseAttachment<BlobParams> {}
export interface LinkPreviewAttachment extends BaseAttachment<LinkPreviewParams> {
  mimeType: typeof linkPreviewType // 'application/vnd.huly.link-preview'
}
export interface AppletAttachment<T extends AppletParams = AppletParams> extends BaseAttachment<T> {
  mimeType: AppletType // `application/vnd.huly.applet.${string}`
}

// A thread hangs off a message and points at a child card.
export interface Thread {
  cardId: CardID
  messageId: MessageID
  threadId: CardID
  threadType: CardType
  repliesCount: number
  lastReplyDate: Date | undefined
  repliedPersons: Record<PersonUuid, number>
}
```

```typescript
export type ContextID = ID & { context: true }
export type NotificationID = ID & { notification: true }

export enum NotificationType {
  Message = 'message',
  Reaction = 'reaction'
}

export interface Notification {
  id: NotificationID
  cardId: CardID
  contextId: ContextID
  account: AccountUuid
  type: NotificationType
  read: boolean
  created: Date
  content: NotificationContent // { title, shortText, senderName } & Record<string,any>
  messageId: MessageID
  creator: SocialID
  blobId: BlobID
  message?: Message            // optionally inlined
}

// A per-account, per-card grouping of notifications with read/seen cursors.
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

export interface Collaborator {
  cardId: CardID
  cardType: CardType
  account: AccountUuid
}
```

```typescript
// Label: an account's subscription/tag on a card (e.g. SubscriptionLabelID).
export interface Label {
  labelId: LabelID  // string & { __label: true }
  cardId: CardID
  cardType: CardType
  account: AccountUuid
  created: Date
}
```

```typescript
// Card (from @hcengineering/card) — a core Doc; messages/notifications attach to it.
export interface Card extends Doc, IconProps, VersionableDoc {
  _class: Ref<MasterTag>
  title: string
  content: MarkupBlobRef  // ref to a blob holding collaborative content
  blobs: Blobs
  children?: number
  attachments?: number
  parentInfo: ParentInfo[]
  parent?: Ref<Card> | null
  rank: Rank
  readonlySections?: Ref<MasterTag>[]
  readonlyFields?: string[]
}
```

## Fields / Cases

### `Message`

| Field | Type | Description |
|-------|------|-------------|
| `id` | `MessageID` | Branded message id. |
| `cardId` | `CardID` | The card this message belongs to. |
| `type` | `MessageType` | `Text` or `Activity`. |
| `content` | `Markdown` | Message body. |
| `creator` | `SocialID` | Author (= `PersonId`). |
| `created` / `modified?` | `Date` | Timestamps (JS `Date`, not epoch ms). |
| `reactions` | `Record<Emoji, EmojiData[]>` | Per-emoji reactor list. |
| `attachments` | `Attachment[]` | Blob / link-preview / applet attachments. |
| `threads` | `Thread[]` | Reply threads on this message. |

### `Notification`

| Field | Type | Description |
|-------|------|-------------|
| `id` | `NotificationID` | Branded id. |
| `cardId` / `contextId` | `CardID` / `ContextID` | Card and grouping context. |
| `account` | `AccountUuid` | Recipient account. |
| `type` | `NotificationType` | `Message` or `Reaction`. |
| `read` | `boolean` | Read state. |
| `messageId` | `MessageID` | Source message. |
| `message?` | `Message` | Optionally inlined source message. |

## Usage

```typescript
import { type Message, MessageType, type Notification } from '@hcengineering/communication-types'

// Activity messages narrow on `type` and `extra.action`:
function isActivity (m: Message): boolean {
  return m.type === MessageType.Activity
}

// Attachments are a union — narrow by mimeType:
for (const att of message.attachments) {
  if (att.mimeType === 'application/vnd.huly.link-preview') {
    // att is LinkPreviewAttachment, att.params is LinkPreviewParams
  }
}
```

## Related types

- Cards are core docs: [core-types](core-types.md) (`Doc`, `Ref`, `MarkupBlobRef`, `Blob`).
- `SocialID` / `AccountUuid` / `PersonUuid` come from core identity: [core-types](core-types.md).

## Cross-references

- [communication concept](../concepts/communication.md)
- [collaboration-crdt concept](../concepts/collaboration-crdt.md)
- [data-model concept](../concepts/data-model.md)
- [collaborator service](../services/collaborator.md)

## Gotchas

- The communication subsystem is **not** the core tx/doc model. Its objects use branded `ID` strings (`MessageID`, `NotificationID`, `ContextID`) and JavaScript `Date` timestamps — NOT core `Ref`/`Timestamp` epoch-ms. It has its own storage (`@hcengineering/communication-cockroach`) and query layer.
- The two models bridge through ids: `CardID`/`CardType` are `Ref<...>` into the core `Card`/`MasterTag` docs, and `SocialID` is the core `PersonId`. A `Card` itself is an ordinary core `Doc`.
- `Attachment` is a discriminated union over `mimeType` (blob / `link-preview` / `applet.*`). Always narrow before reading `params`.
- `CardID` and `CardType` are typed as `Ref<any>` in `core.ts` — the precise target (`Card`, `MasterTag`) is known only by convention, so the compiler won't catch mismatches here.
- `reactions` is keyed by `Emoji` (a branded string), value is a list of `EmojiData` (who reacted + when) — it is not a simple count.
