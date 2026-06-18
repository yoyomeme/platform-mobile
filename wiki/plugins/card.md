# Card (`card`)

> A generic, user-extensible document type: `Card` instances typed by dynamic `MasterTag` classes, with `Tag` mixins, sections, and rich content.

## Where in code
- `plugins/card/src/index.ts` -- plugin id (`cardId = 'card'`), interfaces, class/mixin/section registry
- `models/card/src/index.ts` -- model (`TCard`, `TMasterTag`, `TTag`, `TCardSpace`, sections, roles)
- `models/card/src/{actions,permissions}.ts` -- actions and permissions
- `plugins/card-resources/` -- UI (card editor, sections, master-tag admin, feed/grid views)

## Purpose
`card` is Huly's flexible "make your own object" system. A **`MasterTag`** is a *dynamically defined
document class* (it extends `Class<Card>`); a **`Card`** is an instance of some MasterTag. Users
create MasterTags (e.g. "Project", "Asset", "Wiki Page") and add **`Tag`** mixins to layer extra
attributes onto existing cards. Cards have rich `content` (markup blob), child cards (tree),
attachments, and configurable **sections**. It underpins the no-code/CRM-ish extensibility and newer
apps. Tier 3.

## Document classes
| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `Card` | `core.Doc`, `IconProps`, `VersionableDoc` | `_class: Ref<MasterTag>`, `title`, `content: MarkupBlobRef`, `blobs`, `parent?`, `parentInfo[]`, `rank`, `children?`, `attachments?`, `readonlySections?`, `readonlyFields?` | A card instance; its `_class` is a MasterTag. |
| `MasterTag` | `core.Class<Card>` | `background?`, `removed?`, `roles?`, `singleColumn?` | A **dynamically defined class** of card. |
| `Tag` | `core.Mixin<Card>` (and `MasterTag`) | (same) | A mixin layering extra attributes onto cards. |
| `CardSpace` | `core.TypedSpace` | `types: Ref<MasterTag>[]` | A space holding cards of allowed types. |
| `Role` | `core.Role` | `types: Ref<MasterTag\|Tag>[]` | A role scoped to card types. |
| `CardSection` | `core.Doc` | `label`, `component`, `order`, `navigation[]`, `checkVisibility?` | A configurable section of the card detail view. |
| `MasterTagEditorSection` | `core.Doc` | `id`, `label`, `component`, `masterOnly?` | A section of the MasterTag admin editor. |
| `FavoriteCard` / `FavoriteType` | `preference.Preference` | `attachedTo` | Per-user favorited card / master-tag. |

Mixins: `CardViewDefaults` (default section), `CreateCardExtension` (create-flow hooks),
`DuplicateSetting` (clone rules). Built-in master tags: `File`, `Document`.

## Key relationships / mixins
- **`MasterTag extends Class<Card>`** — MasterTags are stored as *class* definitions in the model
  hierarchy. So a `Card`'s `_class` points at a MasterTag, and querying cards of a type =
  `findAll(<masterTagRef>, ...)`. Subtype MasterTags inherit from parent MasterTags.
- **`Tag extends Mixin<Card>`** — applying a Tag mixes extra attributes onto a specific card (like any
  Huly mixin), enabling per-card extension without changing its base type.
- Cards form a tree via `parent`/`parentInfo` (denormalized ancestor titles), ordered by `rank`.
- `content` is a `MarkupBlobRef` (rich text stored as a blob); cards also have `blobs` and an
  `attachments` collection.
- `CardSpace.types` constrains which MasterTags are allowed in a space; `Role.types` scopes roles.
- Sections (`CardSection`) drive the detail view: Content, Properties, Children, Attachments,
  Relations, Communication messages.

## Notable actions/flows
- Admin defines a `MasterTag` (a new class) and optional `Tag`s; users create `Card`s of that type in
  a `CardSpace`.
- Card detail renders ordered `CardSection`s; `readonlySections`/`readonlyFields` lock parts.
- Versioning via `VersionableDoc`; favorites via `FavoriteCard`/`FavoriteType`.

## Mobile relevance
Tier 3 / advanced. Important to understand because cards are **schema-flexible**: you can't hardcode
attributes — read the MasterTag (class) definition from the `Hierarchy` to know a card's fields, and
check applied `Tag` mixins for extras. Render `content` from its markup blob. A generic card renderer
driven by the hierarchy is the right approach; defer until core apps work.

## Cross-references
- Plugins: [tags](tags.md) (different system — labels, not card types), [text-editor](text-editor.md) (card content), [attachment](attachment.md), [activity](activity.md), [preference](preference.md) (favorites), [view](view.md)
- Concepts: [data-model](../concepts/data-model.md) (classes/mixins are data), [model-layer](../concepts/model-layer.md), [storage-blobs](../concepts/storage-blobs.md), [transaction-model](../concepts/transaction-model.md)

## Gotchas
- **`MasterTag` ≠ `tags.TagElement`.** A MasterTag is a dynamic *document class*; a tags `TagElement`
  is a label. Naming collides — keep them separate.
- A `Card`'s attributes are not fixed — resolve `_class` (a MasterTag) and applied `Tag` mixins in the
  `Hierarchy` to know what fields exist. Generic, not per-class, handling is required.
- `content` is a `MarkupBlobRef` (blob), not inline markup.
- `parentInfo` is denormalized ancestor data; keep consistent when re-parenting.
