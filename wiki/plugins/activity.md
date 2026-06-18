# Activity (`activity`)

> The per-document change/audit feed: system-generated `DocUpdateMessage`s plus reactions, mentions, and saved messages, attached to any doc.

## Where in code
- `plugins/activity/src/index.ts` -- plugin id (`activityId = 'activity'`), all interfaces + class/mixin ids
- `models/activity/src/index.ts` -- model (`TActivityMessage`, `TDocUpdateMessage`, `TReaction`, viewlets, filters)
- `models/server-activity/`, `server/` -- server triggers that turn `Tx`es into `DocUpdateMessage`s
- `plugins/activity-resources/` -- UI (the activity panel, message presenters, reaction picker)

## Purpose
Activity is the cross-cutting **changelog** substrate. Whenever a document changes, a server trigger
emits a `DocUpdateMessage` describing the create/update/remove. These (plus chat messages, mentions,
and info messages) are all `ActivityMessage`s attached to the target doc, rendered as a chronological
feed. It also owns **reactions**, **mentions**, and **saved/bookmarked** messages. Nearly every app
opts in via the `ActivityDoc` mixin.

## Document classes
| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `ActivityMessage` | `core.AttachedDoc` | `isPinned?`, `replies?`, `reactions?`, `repliedPersons?`, `lastReply?`, `editedOn?` | Abstract base for any feed entry attached to a doc. |
| `DocUpdateMessage` | `ActivityMessage` | `objectId`, `objectClass`, `txId?`, `action: 'create'\|'update'\|'remove'`, `updateCollection?`, `attributeUpdates?` | Auto-generated changelog entry for a doc mutation. |
| `ActivityInfoMessage` | `ActivityMessage` | `title?`, `message: IntlString`, `icon?`, `props?`, `links?` | System info message (templated). |
| `ActivityReference` | `ActivityMessage` | `srcDocId`, `srcDocClass`, `attachedDocId?`, `message` | A mention/back-reference into another doc. |
| `Reaction` | `core.AttachedDoc` | `attachedTo: Ref<ActivityMessage>`, `emoji`, `image?: Ref<Blob>`, `createBy: PersonId` | An emoji reaction on a message. |
| `SavedMessage` | `preference.Preference` | `attachedTo: Ref<ActivityMessage>` | A per-user bookmark of a message. |
| `UserMentionInfo` | `core.AttachedDoc` | `user: Ref<Person>`, `content` | Records a person mention. |
| `ActivityMessageControl` | `core.Doc` | `objectClass`, `skip: DocumentQuery<Tx>[]`, `skipFields?`, `allowedFields?` | Rules to suppress noisy updates from the feed. |
| `ActivityExtension` | `core.Doc` | `ofClass`, `components: { input: {...} }` | Registers the input (e.g. comment box) for a doc's activity. |

## Key relationships / mixins
- **`ActivityDoc` mixin** (`Class<Doc>` mixin) marks a class as activity-tracked; that's the opt-in
  every app (Drive `File`, Recruit `Applicant`, etc.) declares. `IgnoreActivity` opts a class out.
- `ActivityMessage` is an `AttachedDoc`, so a doc's feed = `findAll(ActivityMessage, { attachedTo })`.
- `Reaction`/`SavedMessage` attach to an `ActivityMessage` (reactions on messages, not docs directly).
- `chunter.ChatMessage` extends `ActivityMessage` — comments and the audit feed share the same stream
  and are merged in the panel.
- Presenter mixins: `ActivityMessagePreview`, `ActivityAttributeUpdatesPresenter`; viewlets via
  `DocUpdateMessageViewlet` customize how each action/attribute renders.
- `ActivityMessagesFilter` docs define feed filters (e.g. "All", reactions-only).

## Notable actions/flows
- A write → server-activity trigger inspects the `Tx`, applies `ActivityMessageControl` skip rules,
  and creates a `DocUpdateMessage` (with `attributeUpdates` diff: `set`/`added`/`removed`).
- `Reply` action; reactions add/remove a `Reaction`; bookmarking adds a `SavedMessage`.
- Mentions in markup produce `ActivityReference` / `UserMentionInfo` and feed notifications.

## Mobile relevance
High-value read surface. To show a doc's history/comments: `findAll(activity.ActivityMessage, {
attachedTo: docId })` ordered by `createdOn`. Render `DocUpdateMessage.attributeUpdates` as
"X changed Y from A to B". Reactions and threaded replies are common mobile interactions. The same
stream powers Chunter chat, so a unified message renderer is worth building once.

## Cross-references
- Plugins: [chunter](chunter.md) (ChatMessage extends ActivityMessage), [notification](notification.md), [view](view.md), [preference](preference.md) (SavedMessage), [text-editor](text-editor.md) (mentions)
- Concepts: [transaction-model](../concepts/transaction-model.md), [communication](../concepts/communication.md), [data-model](../concepts/data-model.md)

## Gotchas
- `DocUpdateMessage`s are **server-generated** from transactions — clients don't create them; you
  read them. Don't try to author audit entries from the mobile client.
- The feed merges multiple `ActivityMessage` subclasses (updates, chat, info, references) into one
  list; `DisplayDocUpdateMessage` may combine consecutive updates (`combinedMessagesIds`).
- `attributeUpdates` encodes diffs as `set`/`added`/`removed` arrays — for mixin attributes
  `isMixin` is true and the attr key resolves against the mixin, not the base class.
- `ActivityMessageControl` can suppress updates, so not every `Tx` yields a visible message.
