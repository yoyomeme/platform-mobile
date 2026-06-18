# Text Editor (`text-editor`)

> Rich-text (markup) editing infrastructure built on TipTap/ProseMirror: extensions, toolbar actions, and reference-input contributions. Defines *how* `Markup` is edited, not a feature app.

## Where in code
- `plugins/text-editor/src/index.ts` -- plugin id (`textEditorId`), re-exports types + plugin registry
- `plugins/text-editor/src/types.ts` -- editor interfaces (`TextEditorHandler`, `RefInputAction`, `RefInputActionItem`, `TextEditorAction`, `TextEditorExtensionFactory`, `TextFormatCategory`, collaboration/awareness types)
- `plugins/text-editor/src/plugin.ts` -- class ids (`RefInputActionItem`, `TextEditorExtensionFactory`, `TextEditorAction`)
- `models/text-editor/src/index.ts` -- model (registers default toolbar actions, extensions)
- `plugins/text-editor-resources/` -- UI (the actual TipTap `StyledTextEditor`, toolbar, popups)

## Purpose
Provides the shared rich-text editor used by document descriptions, comments, chat messages, and any
`Markup` field. It is a thin model layer plus a registry of pluggable **extensions** and **toolbar
actions**; the real editor is TipTap (ProseMirror) in `-resources`. Other plugins contribute editor
features (mention `@`, emoji, templates, tables, code) by registering docs here.

## Document classes
| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `RefInputActionItem` | `core.Doc` | `label`, `icon`, `action: Resource<RefInputAction>`, `order?` | A contribution to the reference-input control (e.g. the `@`-mention / `+`-reference button). |
| `TextEditorExtensionFactory` | `core.Doc` | `index`, `create: Resource<ExtensionCreator>` | Registers a TipTap extension created per editor mode. |
| `TextEditorAction` | `core.Doc` | `action: TogglerDescriptor \| Resource<fn>`, `icon`, `label`, `category`, `index`, `isActive?`, `visibilityTester?`, `tags?` | A toolbar/format action (bold, heading, link, list, …). |

Key supporting types (not docs): `TextEditorHandler` (insertText/Markup/Table/Emoji/…),
`RefInputAction`, `TextFormatCategory` enum (`Heading`/`TextDecoration`/`Link`/`List`/`Quote`/`Code`/`Table`),
`TextEditorMode` (`full`/`compact`), `ActionContext`, and collaboration types (`CollaborationUser`,
`AwarenessState`, `CollaborationIds`).

## Key relationships / mixins
- The editor edits **`core.Markup`** — ProseMirror/HTML-ish JSON serialized to a string. Large/collab
  documents store markup as a **`MarkupBlobRef`** (a `Blob`) rather than inline (see Document, Lead,
  Recruit `fullDescription`).
- Collaborative editing routes through the **collaborator** service over a Y.js CRDT (the
  `CollaborationIds`/`AwarenessState` types describe cursors/presence). Non-collab fields just store
  the markup string on the doc.
- `TextEditorExtensionFactory`/`TextEditorAction`/`RefInputActionItem` are registered by many plugins
  (chunter for mentions, emoji, templates) — the editor composes whatever is registered.
- Mentions produce [activity](activity.md) `ActivityReference`/`UserMentionInfo` records.

## Notable actions/flows
- Toolbar actions toggle marks/nodes via `TogglerDescriptor` (a TipTap command name) or a custom
  `TextActionFunction`; `isActive`/`visibilityTester` drive button state.
- `RefInputAction` opens completion popups (mention people, link docs, insert emoji) and inserts the
  chosen markup through the `TextEditorHandler`.

## Mobile relevance
You will **not** reuse the TipTap editor on mobile. Instead: (1) implement a `Markup`
parser/serializer compatible with Huly's ProseMirror JSON to render and edit rich text; (2) for
collaborative docs, either render read-only from the markup/blob or integrate a Y.js client against
the collaborator service. Use this plugin as the **spec** for which marks/nodes and mention syntax
exist. Comments/descriptions are the most common markup surfaces.

## Cross-references
- Plugins: [document](document.md), [chunter](chunter.md), [activity](activity.md) (mentions), [card](card.md) (Card content is markup)
- Concepts: [collaboration-crdt](../concepts/collaboration-crdt.md), [storage-blobs](../concepts/storage-blobs.md) (MarkupBlobRef), [ui-framework](../concepts/ui-framework.md)
- Services: `services/collaborator.md`

## Gotchas
- `Markup` is ProseMirror JSON, not Markdown/HTML — round-trip through a compatible
  parser/serializer or you'll corrupt documents.
- A `MarkupBlobRef` field stores the content as a **blob**, not inline; fetch it from the datalake,
  don't expect the text on the doc.
- Collaborative fields are CRDT-backed via the collaborator service; the doc's stored markup may lag
  the live Y.js state.
- These registry docs hold `Resource`/`AnyComponent` refs that only resolve in the Svelte runtime —
  port the behavior, not the components.
