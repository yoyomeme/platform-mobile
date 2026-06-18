# Plugin Catalog

> Complete index of every Huly plugin, grouped by role and mobile tier. The repo's `plugins/` directory holds **192 directories** that collapse into **68 logical plugins** (each typically a `<name>` + `<name>-resources` + `<name>-assets` triad). This page accounts for all 68.

## Where in code

- `plugins/<name>/` — plugin **definitions** (the contract: classes, mixins, refs, the `plugin(...)` id).
- `plugins/<name>-resources/` — **runtime** Svelte UI + logic (components, stores, action implementations).
- `plugins/<name>-assets/` — **assets** (SVG icons, i18n string bundles per locale).
- `models/<name>/` — the **model builder** that registers the plugin's classes/attributes/mixins into the `Hierarchy` at startup. `models/all/src/index.ts` is the master registry that wires every model together. `models/server-<name>/` registers server-side triggers/middleware for that plugin.

A plugin's id (e.g. `export const trackerId = 'tracker' as Plugin`) almost always equals its directory name. One known exception: `plugins/analytics-collector` registers id `'analytics'`.

## The plugin triad

Huly is a **plugin-based, transaction-sourced platform** (see `MOBILE_APP_ARCHITECTURE.md` §0). There is no per-feature REST API: every feature stores `Doc`s read via `findAll` and written via `tx` over one WebSocket. A feature is therefore split across up to four packages so that *definitions* (pure data contracts, importable anywhere) stay decoupled from *UI* and *model registration*:

| Package | Role | Loads where |
|---|---|---|
| `<name>` | **Definitions** — TypeScript interfaces for document classes, mixins, `Ref` ids, the `plugin()` descriptor. No UI, no DOM. | Everywhere (client + server + models) |
| `<name>-resources` | **Resources** — Svelte components, stores, action/presenter implementations. Lazy-loaded by the workbench. | Client UI only |
| `<name>-assets` | **Assets** — icon SVGs + i18n JSON (`en`, `ru`, `es`, `pt`, `cs`, `zh`, …). | Client UI only |
| `models/<name>` | **Model** — builder that registers classes/attributes/mixins/viewlets into the `Hierarchy`; ships seed config. | Model bootstrap (model load) |

Not every plugin has all four. Pure-protocol or server-only plugins (`client`, `openai`, `sign`, `mail`) may have no `-assets`; infra plugins (`presence`, `converter`, `image-cropper`) may skip the model. **For a mobile client you primarily care about the `<name>` definitions (document classes to render) and the `models/<name>` registration (attributes/viewlets) — the `-resources`/`-assets` are web-Svelte and are reimplemented natively.**

---

## Substrate plugins

Shared foundation that almost every user-facing app builds on. A mobile client implements these first.

| Plugin | Purpose | Key classes / exports | Deep page? |
|---|---|---|---|
| `task` | Base work-item framework (statuses, kanban state, projects-of-tasks) reused by Tracker, Recruit, Lead, Board. | `Task`, `Project` (base), `ProjectType`, `TaskType`, `State` | [✓](task.md) |
| `view` | Viewlets, presenters, filters, actions — declarative renderings (list / table / kanban) for any class. | `Viewlet`, `ViewletDescriptor`, `Action`, `Filter`, `AttributePresenter` | [✓](view.md) |
| `activity` | Per-document audit/changelog feed built from transactions. | `ActivityMessage`, `DocUpdateMessage`, `ActivityReference` | [✓](activity.md) |
| `notification` | Cross-app notification engine (rules, providers, settings). | `DocNotifyContext`, `InboxNotification`, `NotificationType`, `NotificationProvider` | [✓](notification.md) |
| `inbox` | The unified inbox surface aggregating notifications across apps. | inbox view config over `notification` classes | [✓](inbox.md) |
| `attachment` | File attachments on any doc (collection of blobs). | `Attachment`, `Photo`, `SavedAttachments` | [✓](attachment.md) |
| `tags` | Tagging / labels / skills taxonomy reused across apps. | `TagElement`, `TagReference`, `TagCategory` | [✓](tags.md) |
| `preference` | Per-user preferences attached to docs (stars, saved views). | `Preference`, `SpacePreference` | [✓](preference.md) |
| `setting` | Workspace + integration + admin settings surface. | `Integration`, `IntegrationType`, `WorkspaceSetting`, `SettingsCategory` | [✓](setting.md) |
| `contact` | People/orgs directory; `Person`/`Employee` are referenced everywhere. | `Person`, `Employee`, `Organization`, `Contact`, `Channel` (social ids), `PersonAccount` | [✓](contact.md) |
| `text-editor` | Rich text (ProseMirror markup) engine for descriptions, comments, docs. | editor extensions, `RefInputAction`, markup actions | [✓](text-editor.md) |
| `templates` | Reusable text/message templates with field substitution. | `MessageTemplate`, `TemplateField` | planned |
| `communication` | Newer messaging substrate (message actions, card message sections) pairing with Chunter/Card. | `MessageAction`, `CardSection` message bindings | planned |
| `card` | Generic typed-card / master-tag framework (custom doc types with roles & relations). | `Card`, `MasterTag`, `Tag` (mixin), `Role`, `DuplicateSetting` | [✓](card.md) |
| `presence` | Realtime presence / typing / "who's online" over a side channel. | presence client, typing store, `Presence` | planned |
| `emoji` | Emoji picker + custom emoji registry (used by reactions). | emoji data, custom emoji refs | planned |
| `guest` | Public/guest share links with scoped access restrictions. | `Restrictions`, `PublicLink`, guest space access | planned |
| `uploader` | Upload pipeline + UI (drag/drop, progress store) feeding attachment/drive/datalake. | upload store, `FileUploadCallback`, uploader utils | planned |
| `print` | Client-side print/export-to-PDF of docs and views. | print utils, print components | planned |
| `sign` | Document e-signing / digital signature integration (server-assisted). | sign utils, signing service binding | planned |

---

## Tier 1 — MVP apps

Must-have on mobile; deliver ~80% of daily value. (See `MOBILE_APP_ARCHITECTURE.md` §2.)

| App | Plugin | Purpose | Key document classes | Deep page? |
|---|---|---|---|---|
| Tracker | `tracker` | Flagship project/issue tracker; issues are `Task`s. | `Project`, `Issue`, `IssueStatus`, `Milestone`, `Component`, sub-issues | [✓](tracker.md) |
| Chunter | `chunter` | Team chat — channels, DMs, threads, reactions. | `Channel`, `DirectMessage`, `ChatMessage`, `ThreadMessage` | [✓](chunter.md) |
| Notification | `notification` | Cross-app notification engine (substrate + app). | `DocNotifyContext`, `InboxNotification` | [✓](notification.md) |
| Inbox | `inbox` | Unified inbox / mobile home surface. | inbox view over notification classes | [✓](inbox.md) |
| Contacts | `contact` | People & org directory (foundational). | `Person`, `Organization`, `Employee`, `Channel` | [✓](contact.md) |
| Documents | `document` | Collaborative documents in teamspaces. | `Document`, `Teamspace`, versions/snapshots | [✓](document.md) |
| Calendar | `calendar` | Events, recurring events, reminders. | `Event`, `ReccuringEvent`, `Calendar`, `Schedule` | [✓](calendar.md) |
| Time | `time` | Personal to-dos + planned time slots. | `ToDo`, `WorkSlot`, `ProjectToDo` | [✓](time.md) |

---

## Tier 2 — Enhanced apps

| App | Plugin | Purpose | Key document classes | Deep page? |
|---|---|---|---|---|
| Drive | `drive` | File storage with folders and versions. | `Drive`, `Folder`, `File`, `FileVersion` | [✓](drive.md) |
| Board | `board` | Trello-style kanban boards. | `Board`, `Card` | [✓](board.md) |
| Lead | `lead` | Sales CRM (pipelines/funnels). | `Funnel`, `Lead`, `Customer` | [✓](lead.md) |
| Recruit | `recruit` | Applicant tracking system. | `Vacancy`, `Candidate`, `Applicant`, `Review` | [✓](recruit.md) |
| HR | `hr` | Org structure + leave/time-off. | `Department`, `Staff`, `Request`, `TzDate` | [✓](hr.md) |
| Activity | `activity` | Per-doc change history feed (also substrate). | `ActivityMessage`, `DocUpdateMessage` | [✓](activity.md) |
| Products | `products` | Product catalog / product management. | `Product`, `ProductVersion` | planned |
| Inventory | `inventory` | Inventory/asset tracking. | `Product`, `Category`, `Variant` | planned |

---

## Tier 3 — Advanced / integrations

| App | Plugin | Purpose | Key classes / notes | Deep page? |
|---|---|---|---|---|
| Love | `love` | Virtual office: rooms, audio/video (LiveKit), screen share — heavy. | `Room`, `Office`, `ParticipantInfo`, `Floor` | planned |
| Gmail | `gmail` | Gmail integration (sync mail into workspace). | `Message`, `NewMessage`, `Integration` | planned |
| Mail | `mail` | Generic mail message model (channel/thread for email). | `MailThread`, mail message classes | planned |
| Huly Mail | `huly-mail` | Native Huly mail integration (`huly-mail` integration kind). | `hulyMailIntegrationKind`, mail bindings | planned |
| Telegram | `telegram` | Telegram messaging integration. | `Message`, `NewMessage`, `TelegramMessage` | planned |
| Process | `process` | No-code automation / workflow builder (triggers → actions). | `Process`, `Transition`, `Step`, `Trigger`, `Execution` | planned |
| Survey | `survey` | Surveys/forms with questions & submissions. | `Survey`, `Question`, `SurveySubmission` | planned |
| Test Management | `test-management` | QA test cases, suites, runs. | `TestCase`, `TestSuite`, `TestRun`, `TestProject` | planned |
| Request | `request` | Generic approval/request workflow. | `Request` (approval), approval flows | planned |
| Controlled Documents | `controlled-documents` | QMS — versioned, reviewed, approved controlled docs. | `ControlledDocument`, `DocumentTemplate`, `DocumentReviewRequest` | planned |
| Training | `training` | Training courses + trainee completion tracking. | `Training`, `TrainingRequest`, `TrainingAttempt` | planned |
| Questions | `questions` | Question bank shared by Training / Survey. | `Question`, `Answer`, `QuestionMixin` | planned |
| AI Assistant | `ai-assistant` | In-app AI assistant surface/config. | assistant config, AI commands | planned |
| AI Bot | `ai-bot` | Server-side AI bot account + connection model. | `AIBotTransferEvent`, bot account, connection | planned |
| OpenAI | `openai` | OpenAI provider configuration (LLM backend). | `openaiId`, OpenAI integration config | planned |
| Billing | `billing` | Workspace billing / subscription surface. | billing account, plan/usage classes | planned |
| Recorder | `recorder` | Screen/audio recording capture for messages/docs. | recorder service, recording blobs | planned |
| Support | `support` | In-app support widget / help. | support config, support channel | planned |
| Achievement | `achievement` | Gamification — badges/achievements. | `Achievement`, achievement events | planned |
| Onboard | `onboard` | New-user onboarding flow/state. | onboarding steps/state | planned |
| Global Profile | `global-profile` | Cross-workspace user profile surface. | global profile components/utils | planned |
| Bitrix | `bitrix` | Bitrix24 importer/migration. | `BitrixProfile`, import field maps | planned |
| Diffview | `diffview` | Code/diff viewer (e.g. for GitHub-linked PRs). | `DiffFileId`, diff render config | planned |
| Devmodel | `devmodel` | Developer model inspector / debug tooling. | `devModelId`, model devtools | planned |
| Chat | `chat` | Chat app shell/navigation glue around Chunter + communication. | chat view config, chat nav | planned |
| Image Cropper | `image-cropper` | Avatar/image crop UI utility. | cropper component | planned |
| Desktop Downloads | `desktop-downloads` | Electron desktop download manager. | download list/items | planned |
| Desktop Preferences | `desktop-preferences` | Electron desktop-specific preferences. | desktop pref schema | planned |
| Analytics Collector | `analytics-collector` | Telemetry/event collection (id = `analytics`). | `analyticsCollectorId`, event classes | planned |
| Export | `export` | Export workspace data (docs/views) to files. | export jobs/formats | planned |
| Converter | `converter` | Document/markdown format conversion (import/export, formatters). | markdown/format converters | planned |
| Media | `media` | Media (audio/video) device & stream management (used by Love/Recorder). | media stores, device utils | planned |

> Likely desktop-only / low mobile value: `process`, `test-management`, `controlled-documents`, `devmodel`, `diffview`, `bitrix`, `desktop-downloads`, `desktop-preferences`, advanced `setting`/admin.
>
> Note: `github` and `payment` referenced in early architecture notes are **not** in `plugins/`. GitHub integration lives in `services/github` (a server service, not a plugin); there is no `payment` plugin in this repo.

---

## Full alphabetical index

Every base directory in `plugins/` (the `<name>` definitions package; each also has `-resources` and usually `-assets`). 68 entries.

| Plugin | One-line purpose |
|---|---|
| `achievement` | Gamification badges/achievements. |
| `activity` | Per-document change-history feed built from transactions (substrate + app). |
| `ai-assistant` | In-app AI assistant surface and configuration. |
| `ai-bot` | Server-side AI bot account, connection, and transfer-event model. |
| `analytics-collector` | Telemetry/event collection (plugin id `analytics`). |
| `attachment` | File attachments collection on any document (substrate). |
| `billing` | Workspace billing / subscription surface. |
| `bitrix` | Bitrix24 import/migration integration. |
| `board` | Trello-style kanban boards (`Board`, `Card`). |
| `calendar` | Events, recurring events, reminders (`Event`, `Calendar`). |
| `card` | Generic typed-card / master-tag framework with roles & relations. |
| `chat` | Chat app shell/navigation around Chunter + communication. |
| `chunter` | Team chat: channels, DMs, threads, reactions. |
| `client` | Client/transactor connection plumbing (protocol substrate; no app UI). |
| `communication` | Newer messaging substrate (message actions, card message sections). |
| `contact` | People & org directory; `Person`/`Employee` referenced everywhere (substrate). |
| `controlled-documents` | QMS: versioned, reviewed, approved controlled documents. |
| `converter` | Document/markdown format conversion (import/export, formatters). |
| `desktop-downloads` | Electron desktop download manager. |
| `desktop-preferences` | Electron desktop-specific preferences. |
| `devmodel` | Developer model inspector / debug tooling. |
| `diffview` | Code/diff viewer (e.g. GitHub-linked diffs). |
| `document` | Collaborative documents in teamspaces (`Document`, `Teamspace`). |
| `drive` | File storage with folders and versions (`Drive`, `Folder`, `File`). |
| `emoji` | Emoji picker + custom emoji registry (reactions). |
| `export` | Export workspace data (docs/views) to files. |
| `global-profile` | Cross-workspace user profile surface. |
| `gmail` | Gmail integration (mail sync into workspace). |
| `guest` | Public/guest share links with scoped access restrictions. |
| `hr` | Org structure + leave/time-off (`Department`, `Staff`, `Request`). |
| `huly-mail` | Native Huly mail integration (`huly-mail` integration kind). |
| `image-cropper` | Avatar/image crop UI utility. |
| `inbox` | Unified inbox surface aggregating notifications (substrate + app). |
| `inventory` | Inventory / asset tracking. |
| `lead` | Sales CRM pipelines (`Funnel`, `Lead`, `Customer`). |
| `login` | Login/auth UI flow (account selection, workspace join). |
| `love` | Virtual office: rooms, audio/video via LiveKit, screen share. |
| `mail` | Generic mail message model (channel/thread for email). |
| `media` | Media device & stream management (used by Love/Recorder). |
| `notification` | Cross-app notification engine (substrate + app). |
| `onboard` | New-user onboarding flow/state. |
| `openai` | OpenAI provider configuration (LLM backend). |
| `preference` | Per-user preferences attached to docs (substrate). |
| `presence` | Realtime presence / typing / online status. |
| `print` | Client-side print / export-to-PDF of docs and views. |
| `process` | No-code automation / workflow builder (triggers → actions). |
| `products` | Product catalog / product management. |
| `questions` | Question bank shared by Training and Survey. |
| `rating` | Per-document ratings & reactions (`DocRating`, `DocReaction`, `PersonRating`). |
| `recorder` | Screen/audio recording capture. |
| `recruit` | Applicant tracking system (`Vacancy`, `Candidate`, `Applicant`). |
| `request` | Generic approval/request workflow. |
| `setting` | Workspace + integration + admin settings (substrate). |
| `sign` | Document e-signing / digital signature integration. |
| `support` | In-app support widget / help. |
| `survey` | Surveys/forms with questions & submissions. |
| `tags` | Tagging / labels / skills taxonomy (substrate). |
| `task` | Base work-item framework reused by Tracker/Recruit/Lead/Board (substrate). |
| `telegram` | Telegram messaging integration. |
| `templates` | Reusable text/message templates with field substitution. |
| `test-management` | QA test cases, suites, and runs. |
| `text-editor` | Rich text (ProseMirror markup) engine (substrate). |
| `time` | Personal to-dos + planned time slots (`ToDo`, `WorkSlot`). |
| `tracker` | Flagship project/issue tracker (`Project`, `Issue`, `Milestone`). |
| `training` | Training courses + trainee completion tracking. |
| `uploader` | Upload pipeline + UI feeding attachment/drive/datalake. |
| `view` | Viewlets, presenters, filters, actions (declarative renderings — substrate). |
| `workbench` | App shell: navigation, spaces, the host that lazy-loads all app resources. |

> `rating`, `login`, and `workbench` are not in the tier tables above because they are app-shell / infra rather than feature apps. They are listed here for completeness:
> - `workbench` — the navigation shell that loads every other plugin's resources; the mobile equivalent is your app scaffold.
> - `login` — auth/account/workspace-selection UI (mobile reimplements natively against the accounts RPC).
> - `client` — connection plumbing to the transactor (protocol substrate).
> - `rating` — ratings/reactions on docs (lightweight substrate).

---

## Cross-references

- Architecture: [`../../MOBILE_APP_ARCHITECTURE.md`](../../MOBILE_APP_ARCHITECTURE.md) §2 (feature catalog & tiers), §0 (transaction-sourced model).
- Wiki schema: [`../WIKI.md`](../WIKI.md).
- Planned deep pages (to be authored under `wiki/plugins/`): `tracker.md`, `chunter.md`, `contact.md`, `notification.md`, `inbox.md`, `document.md`, `calendar.md`, `time.md`, `task.md`, `view.md`, `activity.md`, `attachment.md`, `text-editor.md`. (None exist yet — this catalog is the entry point until they are written.)

## Gotchas

- **Triad is not universal.** Don't assume every plugin has `-assets` or a model. Protocol/server-only plugins (`client`, `openai`, `sign`, `mail`, `ai-bot`) and some infra (`presence`, `converter`, `image-cropper`, `devmodel`) deviate. Always check `ls plugins/<name>*` before assuming.
- **Id ≠ directory once.** `plugins/analytics-collector` registers the plugin id `'analytics'`, not `'analytics-collector'`. Every other base plugin's id matches its directory name.
- **Definitions vs resources for mobile.** For a native client, the load-bearing packages are `<name>` (document-class contracts) and `models/<name>` (attribute/viewlet registration). `<name>-resources`/`<name>-assets` are web-Svelte UI you reimplement, not consume.
- **Substrate plugins double as apps.** `notification`, `inbox`, `activity` appear both as substrate and as user-facing surfaces — they aren't separable.
- **Two messaging stacks coexist.** `chunter` (established chat) and `communication` (newer messaging substrate) overlap; `chat` is a shell that stitches them. Pick the more recent (`communication`) when they conflict and flag the legacy path.
- **Mail is three plugins.** `gmail`, `mail`, and `huly-mail` are distinct integrations, not duplicates — `mail` is the generic model, `gmail`/`huly-mail` are providers.
- **`github`/`payment` aren't plugins here.** GitHub integration is `services/github`; there is no `payment` plugin in this repo despite older notes mentioning it.
- **`models/server-<name>` is server middleware.** Those directories register triggers/middleware on the transactor side and have no client UI counterpart.
