# Contact (`contact`)

> The foundational identity directory: `Person`, `Organization`, `Employee` (mixin), `Contact`, social-id `Channel`s, and avatars. Referenced by nearly every other app.

## Where in code
- `plugins/contact/src/index.ts` -- plugin id (classes/mixin/strings); interfaces `Contact`, `Person`, `Organization`, `Employee`, `Channel`, `SocialIdentity`, `AvatarInfo`
- `plugins/contact/src/{types,avatar,utils,cache,workspaceMemberStatusUtils}.ts` -- types + avatar URL helpers + caches
- `models/contact/src/index.ts` -- model: `@Model`/`@Mixin` defs, `DOMAIN_CONTACT`, `DOMAIN_CHANNEL`
- `plugins/contact-resources/` -- Svelte UI (`Avatar`, `EmployeePresenter`, `ChannelsPresenter`, `AssigneePopup`, person/org editors)

## Purpose
Contact is the identity substrate. Every assignee, message sender, project lead, event participant, and collaborator ultimately resolves to a `Person` (often an `Employee`). It also models external contacts (CRM), organizations, the social handles (`Channel`) a contact can be reached on, and the avatar system.

## Document classes

| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `AvatarInfo` | `core.class.Doc` | `avatarType: AvatarType`, `avatar?: Ref<Blob>`, `avatarProps?` | Mixed into `Contact`; holds avatar source (color/image/gravatar/external). |
| `Contact` | `core.class.Doc` + `AvatarInfo` (`DOMAIN_CONTACT`) | `name`, `city?`, `channels?`, `attachments?`, `comments?` | Abstract base for anyone/anything addressable. |
| `Person` | `contact.class.Contact` + `BasePerson` | `birthday?`, `socialIds?`, `profile?: Ref<Card>` | A human contact. Base for `Employee`. |
| `Organization` | `contact.class.Contact` | `members: number`, `description: MarkupBlobRef` | A company/org contact. |
| `Channel` | `core.class.AttachedDoc` (`DOMAIN_CHANNEL`) | `provider: Ref<ChannelProvider>`, `value`, `lastMessage?` | A social/contact handle (email, phone, Telegram…) attached to a contact. |
| `SocialIdentity` | `core.class.AttachedDoc` (`DOMAIN_CHANNEL`) + `SocialId` | `attachedTo: Ref<Person>`, `type: SocialIdType` | A verified social identity; its `_id` is a `PersonId`. |
| `ChannelProvider` | `core.class.Doc` (`DOMAIN_MODEL`) + `UXObject` | `placeholder`, `presenter?`, `integrationType?` | Defines a channel kind (Email/Phone/Telegram/…). |
| `AvatarProvider` | `core.class.Doc` | `type`, `getUrl: Resource<GetAvatarUrl>` | Resolves an avatar to a URL/srcset. |
| `Member` | `core.class.AttachedDoc` | `contact: Ref<Contact>` | Membership link (e.g. org members). |
| `Status` | `core.class.AttachedDoc` | `attachedTo: Ref<Employee>`, `name`, `dueDate` | An employee availability/status entry. |
| `PersonSpace` | `core.class.Space` | `person: Ref<Person>` | Per-person private space (used by notifications/inbox). |
| `WorkspaceMemberStatus` | `core.class.Doc` | `user: AccountUuid`, `message`, `clearAt?` | Persistent member status note (e.g. vacation). |

## Key relationships / mixins
- **`Employee`** is a **mixin** on `Person` (`contact.mixin.Employee`), not a separate class — it adds `active`, `position?`, `personUuid?`, `role?`. To treat a person as an employee, read through the mixin.
- `SocialIdentity._id` doubles as a `PersonId`; `socialIds` is the collection of a person's verified identities. This is how `PersonId`/`AccountUuid` on other docs resolve back to a `Person`.
- `Person.profile?: Ref<Card>` links to the newer `card` model.
- Avatars: `Contact` carries `AvatarInfo`; the matching `AvatarProvider.getUrl` (Color/Image/Gravatar/External) produces the displayable URL.
- `contact.mention.Everyone` / `.Here` are pseudo-employees used for @-mentions.

## Spaces
Most contacts live in the seeded `contact.space.Contacts` space. `PersonSpace` is a per-person space used as the scope for [notification](notification.md) `DocNotifyContext` / `InboxNotification` documents.

## Notable actions/flows
- Create person/organization; edit social channels (`SocialEditor`).
- Avatar resolution via provider `getUrl` functions.
- Assignee selection (`AssigneePopup`) is reused across Tracker/Recruit/etc.

## Mobile relevance
**Tier-1 foundation.** Rarely a standalone screen first, but its presenters power every other surface: avatars, assignee/participant chips, sender names, mention rendering. Build a robust `Person`/`Employee` resolver + avatar URL helper early. A contacts directory screen is Tier-1 but lower than Inbox/Chunter/Tracker.

## Cross-references
- Referenced by: [tracker](tracker.md) (assignee/lead), [chunter](chunter.md) (senders), [calendar](calendar.md) (participants), [time](time.md) (`ToDo.user`), [notification](notification.md) (`PersonSpace`)
- Concepts: [data-model](../concepts/data-model.md), [workspace-multitenancy](../concepts/workspace-multitenancy.md), [storage-blobs](../concepts/storage-blobs.md) (avatar blobs)

## Gotchas
- `Employee` is a **mixin**, so `findAll(contact.class.Person)` returns persons; you must apply/has the `Employee` mixin to get employee fields. Querying "employees" means querying persons with the mixin.
- Identity is layered: docs reference users by `PersonId` (a social id) or `AccountUuid`, both of which must be resolved through `SocialIdentity` to a `Person`. Do not assume a doc stores a `Ref<Person>` directly.
- Avatar URLs are async and provider-dependent — do not hardcode a path; call the provider's `getUrl`. Color avatars have no image at all.
- `Organization.description` is a `MarkupBlobRef` (blob), while small notes are inline — check the field type before rendering.
