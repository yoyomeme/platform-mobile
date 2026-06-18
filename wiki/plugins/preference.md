# Preference (`preference`)

> Per-user settings: the `Preference` base doc that many plugins extend for stars, saved items, hidden apps, viewlet configs, and more.

## Where in code
- `plugins/preference/src/index.ts` -- plugin id (`preferenceId = 'preference'`), `Preference`/`SpacePreference` interfaces, class ids, `DOMAIN_PREFERENCE`
- `models/preference/src/` -- model (`TPreference`, `TSpacePreference`), stored in the `preference` domain
- `plugins/preference-resources/` -- minimal UI (star toggle helpers)

## Purpose
`preference` is the substrate for **per-user, per-workspace** state. A `Preference` is a simple `Doc`
with an `attachedTo` pointer; the key property is that preference docs are **scoped to the current
account** — each user only sees their own. Dozens of plugins extend `Preference` to store things like
"starred space", "saved message", "hidden application", "viewlet column config", and "favorite card".

## Document classes
| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `Preference` | `core.Doc` | `attachedTo: string` | Base per-user preference; `attachedTo` references the target (doc id, app, etc.). |
| `SpacePreference` | `Preference` | `attachedTo: Ref<Space>` | A preference about a space (e.g. starred/favorited space). |

Stored in `DOMAIN_PREFERENCE`.

## Key relationships / mixins
- **Preferences are private to the account.** The platform automatically filters preference queries to
  the current user, so `findAll(Preference subclass, {...})` returns only the caller's docs — there is
  no per-doc owner field to match on beyond `createdBy`.
- Many plugins subclass `Preference` rather than inventing their own user-state store:
  - [view](view.md) `ViewletPreference` — saved columns/options per viewlet.
  - [activity](activity.md) `SavedMessage` — bookmarked messages.
  - [attachment](attachment.md) `SavedAttachments` — saved files.
  - [workbench](workbench.md) `HiddenApplication`, `WidgetPreference`, `WorkbenchTab` — UI state.
  - [card](card.md) `FavoriteCard`, `FavoriteType` — favorites.
  - [board](board.md) `CommonBoardPreference` — board UI prefs.
- `SpacePreference` powers the generic "star a space" feature (`Starred`/`Star`/`Unstar` strings).

## Notable actions/flows
- Star/favorite a space: create a `SpacePreference` with `attachedTo = spaceId`; unstar = remove it.
- Any per-user toggle = create/remove the relevant `Preference` subclass instance; reads are
  auto-scoped to the user.

## Mobile relevance
Important supporting feature. Use `SpacePreference` to implement starred/favorite spaces in the nav,
and read the various `Preference` subclasses to restore the user's UI state (hidden apps, saved
messages/attachments, viewlet configs). Because reads are account-scoped, you don't filter by user
yourself — just query the subclass. Lightweight: a single domain of small docs.

## Cross-references
- Plugins: [view](view.md) (ViewletPreference), [activity](activity.md) (SavedMessage), [attachment](attachment.md) (SavedAttachments), [workbench](workbench.md) (HiddenApplication/WidgetPreference/WorkbenchTab), [card](card.md) (favorites)
- Concepts: [data-model](../concepts/data-model.md), [workspace-multitenancy](../concepts/workspace-multitenancy.md), [transaction-model](../concepts/transaction-model.md)

## Gotchas
- `Preference` query results are **automatically restricted to the current account** — don't add your
  own user filter, and don't expect to read other users' preferences.
- `attachedTo` is a plain `string` on the base `Preference` (so it can point at a doc, an app alias, or
  anything); `SpacePreference` narrows it to `Ref<Space>`.
- Preferences live in their own `DOMAIN_PREFERENCE`, separate from the docs they reference — they are
  not collection children of the target.
- Removing a target doc does not auto-remove dangling preferences pointing at it; tolerate stale
  `attachedTo`.
