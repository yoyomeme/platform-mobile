# Setting (`setting`)

> Settings & admin: the registry of `SettingsCategory` panels, third-party `Integration`s, workspace config, roles/capabilities, and enums.

## Where in code
- `plugins/setting/src/index.ts` -- plugin id (`settingId = 'setting'`), interfaces, class/mixin/id registry
- `plugins/setting/src/spaceTypeEditor.ts`, `utils.ts` -- space-type editor mixins, helpers
- `models/setting/src/index.ts` -- model (settings categories, integration types, enum setting, editable mixins)
- `plugins/setting-resources/` -- UI (the settings shell, integration cards, class/attribute editors)

## Purpose
The account/workspace settings surface. It registers **settings categories** (Profile, Password,
Integrations, Members, Spaces, Backup, Security/2FA, …) that appear in the settings navigator, models
**integrations** (connect Gmail/Telegram/etc. via the account service), and holds workspace-level
configuration docs (invite settings, role capabilities, office settings, workspace icon). Mostly
desktop/admin; selectively relevant on mobile.

## Document classes
| Class | Extends | Key attributes | Description |
|---|---|---|---|
| `SettingsCategory` | `core.Doc` | `name`, `label`, `icon`, `component`, `role: AccountRole`, `group?`, `order?`, `adminOnly?`, `expandable?` | A panel in the settings navigator. |
| `WorkspaceSettingCategory` | `SettingsCategory` (same class) | (workspace-scoped) | Settings shown under workspace admin. |
| `IntegrationType` | `core.Doc` | `label`, `description`, `icon`, `kind: IntegrationKind`, `allowMultiple`, `createComponent?`, `onDisconnect?` | A connectable third-party integration definition. |
| `Integration` | `core.Doc` | `type: Ref<IntegrationType>`, `disabled`, `value`, `error?`, `shared?` | A user's configured integration instance. |
| `InviteSettings` | `core.Configuration` | `expirationTime`, `emailMask`, `limit`, `defaultInviteRole`, `inviteLinkGeneratorRoles` | Workspace invite policy. |
| `RoleCapabilitySettings` | `core.Configuration` | `roleByCapability: Record<string, AccountRole[]>` | Maps capabilities → allowed roles. |
| `OfficeSettings` | `core.Configuration` | `defaultStartWithTranscription`, `defaultStartWithRecording` | Virtual-office (love) defaults. |
| `WorkspaceSetting` | `core.Doc` | `icon?: Ref<Blob>` | Workspace branding (logo). |

## Key relationships / mixins
- **`Editable` mixin** (`Class<Doc>` mixin, `value: boolean`) marks a class as user-editable in the
  class/attribute admin (many apps set this on their classes). **`UserMixin`** marks custom classes as
  deletable.
- **`SpaceTypeEditor` / `SpaceTypeCreator` mixins** bind editor components to space-type descriptors,
  driving the "Spaces / Space Types" admin (roles, properties, task types).
- Enums are `core.EnumOf` types edited via the `EnumSetting` category (registered in the model) — this
  is the "custom dropdown" admin.
- Integrations connect through the **account service** (`@hcengineering/account-client` `Integration`);
  `RoleCapability`/`HasRoleCapability` gate permission-sensitive UI (invite-link generation, etc.).

## Notable actions/flows
- Settings navigator iterates `SettingsCategory` docs filtered by the user's `role`/`adminOnly`.
- Connecting an integration: pick an `IntegrationType` → run its `createComponent` → an `Integration`
  doc is created/linked via the account service; disconnect runs `onDisconnect`.
- Workspace admin: manage members, space types/roles, invite settings, backup, security (2FA).

## Mobile relevance
Mostly desktop-only admin. Mobile-relevant slices: **Profile** (edit own contact), **Password / 2FA**
(account-service flows), **integrations status**, and **sign out / switch workspace**. Treat
`SettingsCategory` as the menu spec but reimplement only the few panels mobile needs; gate by
`role`/`adminOnly`.

## Cross-references
- Plugins: [contact](contact.md) (Profile = Employee), [login](login.md) (password/2FA via account service), [workbench](workbench.md) (settings entry point), [view](view.md) (editable mixins)
- Concepts: [workspace-multitenancy](../concepts/workspace-multitenancy.md), [plugin-architecture](../concepts/plugin-architecture.md)
- Services: `services/account.md`

## Gotchas
- `SettingsCategory.role` and `adminOnly` gate visibility — don't show admin panels to non-admins.
- Integration auth/state lives partly in the **account service**, not the transactor — connecting
  isn't a pure `tx()` flow.
- `Configuration` subclasses (`InviteSettings`, `RoleCapabilitySettings`, `OfficeSettings`) are
  singletons of workspace policy, not per-user docs.
- `Editable`/`SpaceTypeEditor` are mixins on classes/descriptors (model metadata), not on instances.
