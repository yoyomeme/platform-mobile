# Tags (`tags`)

> Labels & skills: reusable `TagElement` definitions, grouped by `TagCategory`, applied to docs as `TagReference` collection items.

## Where in code
- `plugins/tags/src/index.ts` -- plugin id (`tagsId = 'tags'`), interfaces, class ids, `findTagCategory` helper
- `models/tags/src/index.ts` -- model (`TTagElement`, `TTagReference`, `TTagCategory`, filters)
- `models/server-tags/` -- server triggers (maintains `refCount`, copies title/color to references)
- `plugins/tags-resources/` -- UI (tag editors, category bar, labels presenter)

## Purpose
A generic labeling system used for two things: simple **labels** (e.g. on a Board card or Tracker
issue) and weighted **skills** (e.g. a Recruit candidate's competencies). A `TagElement` is the
reusable label definition (scoped to a `targetClass` and a `TagCategory`); applying it to a doc
creates a `TagReference` in that doc's tag collection.

## Document classes
| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `TagElement` | `core.Doc` | `title`, `targetClass: Ref<Class>`, `description`, `color`, `category: Ref<TagCategory>`, `refCount?` | The reusable label/skill definition. |
| `TagReference` | `core.AttachedDoc` | `tag: Ref<TagElement>`, `title` (copy), `color` (copy), `weight?` | An application of a tag to a host doc. |
| `TagCategory` | `core.Doc` | `icon`, `label`, `targetClass`, `tags: string[]`, `default` | Groups tags; `tags` are template suggestions; `default` catches unmatched. |

## Key relationships / mixins
- `TagReference` is an `AttachedDoc` in the host doc's tag collection (`attachedTo`/`collection`); the
  host declares a `Collection(tags.class.TagReference)` count prop (e.g. `labels?`/`skills?`).
- `TagReference` **denormalizes** `title` and `color` from its `TagElement` (kept in sync by a server
  trigger) so the reference renders and full-text-searches without a join.
- `TagElement.refCount` is maintained server-side as references are added/removed.
- `TagElement.targetClass` scopes which doc class a tag applies to (issue labels vs candidate skills).
- `weight` on a `TagReference` encodes skill level: `1–4` initial, `5–7` meaningful, `8–10` expert
  (`InitialKnowledge`/`MeaningfullKnowledge`/`ExpertKnowledge`).
- Filter modes `FilterTagsIn` / `FilterTagsNin` integrate tags into the [view](view.md) filter bar.

## Notable actions/flows
- Apply a label = `addCollection(TagReference, space, hostId, hostClass, '<collection>', { tag, title,
  color, weight? })`. Remove = `removeCollection`.
- `findTagCategory(title, categories)` resolves a free-typed tag to a category (matching the
  category's `tags` list, falling back to the `default` category).

## Mobile relevance
Tier 2/3 support feature. Shows up as label chips on issues/cards and skill pills on candidates. To
render a doc's tags: `findAll(TagReference, { attachedTo: docId })` — the denormalized `title`/`color`
mean no extra lookup. Skill weight drives the level icon. Reuse one tag-chip component across apps.

## Cross-references
- Plugins: [recruit](recruit.md) (skills), [board](board.md)/[tracker](tracker.md) (labels), [view](view.md) (tag filters), [activity](activity.md) (AddedTag/RemovedTag messages)
- Concepts: [data-model](../concepts/data-model.md) (AttachedDoc/collections), [fulltext-search](../concepts/fulltext-search.md)

## Gotchas
- A `TagReference` carries **copies** of `title`/`color` — if you edit a `TagElement`, references are
  updated by a server trigger; don't read stale copies as authoritative without expecting the sync.
- `weight` is optional and only meaningful for skill-style tags; label tags leave it unset.
- `targetClass` scopes tags — the same label text under different `targetClass`/category is a different
  `TagElement`; `findTagCategory` throws if no category (and no default) matches.
- `refCount` is server-maintained; don't compute it client-side.
