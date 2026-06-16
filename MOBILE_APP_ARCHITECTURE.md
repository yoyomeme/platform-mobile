# Huly Mobile App — Architecture & Build Guide

> Companion to [ARCHITECTURE_OVERVIEW.md](./ARCHITECTURE_OVERVIEW.md). That doc describes the **server topology** (30+ services). This doc describes everything a **cross-platform mobile client** needs to log into a self-hosted Huly instance and use its features, plus how to match the UI theme.
>
> Goal: a Flutter / React Native client for **self-hosted** Huly where a user logs in and uses the full feature set.

---

## 0. The One Thing To Understand First

Huly is a **plugin-based, transaction-sourced platform**, not a REST app.

- There is **no per-feature REST API**. Every feature (issues, chat, contacts, docs…) is stored as documents (`Doc`) in a workspace, and **all reads go through one method (`findAll`) and all writes go through one method (`tx`)** over a single WebSocket to the **transactor**.
- The data "schema" itself is data: the **model** is a stream of transactions the client loads at startup to build a `Hierarchy` (classes, attributes, mixins). Plugins register their classes into this model.
- So a mobile client implements **one protocol** (account login + transactor WebSocket + file storage), then talks to *every* feature through the same generic `Doc`/`Tx` mechanism. You do **not** write a new API integration per feature — you learn each feature's document classes.

This is great news for "full feature parity": once the protocol layer works, adding a feature = rendering its document classes + issuing the right transactions.

---

## 1. Connection, Auth & Protocol (the foundation)

### 1.1 Startup config discovery

A client first fetches runtime config from the **front** service — this lists every backend URL so nothing is hardcoded:

```
GET {BASE_URL}/config.json
```
Source: `server/front/src/index.ts` (~lines 336–369), consumed in `plugins/workbench-resources/src/connect.ts`.

Key fields returned:

| Field | Example | Use |
|---|---|---|
| `ACCOUNTS_URL` | `http://huly.local:3000` | Login + workspace selection (RPC) |
| `FILES_URL` | `…/blob/:workspace/:blobId/:filename` | File download URL pattern |
| `UPLOAD_URL` | `/files` | File upload |
| `DATALAKE_URL` | `http://huly.local:4030` | Blob storage |
| `HULYLAKE_URL` | `http://huly.local:8096` | S3-compatible storage adapter |
| `COLLABORATOR_URL` | `ws://huly.local:3078` | Real-time doc editing (Y.js CRDT) |
| `PREVIEW_URL` | `http://huly.local:4040` | Thumbnails/previews |
| `PULSE_URL` | `ws://huly.local:8099/ws` | Push notifications (WebSocket) |
| `STREAM_URL` | `http://huly.local:1080/recording` | Video streaming (HLS) |
| `BRANDING_URL` | `…/branding.json` | Logos/colors override |
| `PUSH_PUBLIC_KEY` | (optional) | Web/native push |
| `MODEL_VERSION` / `VERSION` | `0.7.0` | Compatibility check |

**Mobile pattern:** the user enters only their instance base URL (e.g. `https://huly.mycompany.com`); the app fetches `config.json` and derives everything else.

### 1.2 Login & workspace selection (account service, :3000)

The account service is **JSON-RPC over HTTP POST** (not REST). Body shape: `{ method, params }`, response `{ result?, error? }`.
Client reference: `foundations/core/packages/account-client/src/client.ts`. Types: `foundations/core/packages/account-client/src/types.ts`.

Core methods:

| Method | Params | Returns |
|---|---|---|
| `login` | `{ email, password }` | `LoginInfo { account, token?, tfaRequired? }` |
| `loginOtp` / `validateOtp` | email + code | `LoginInfo` (passwordless) |
| `getUserWorkspaces` | (Bearer token) | `WorkspaceInfoWithStatus[]` |
| `selectWorkspace` | `{ workspaceUrl, kind: 'external'\|'internal'\|'byregion' }` | `WorkspaceLoginInfo` |
| `requestPasswordReset`, `changePassword` | … | … |

`WorkspaceLoginInfo` is the payload that unlocks the real-time connection:

```ts
{
  account, token,        // JWT scoped to this workspace — used for the transactor WS
  workspace, workspaceUrl,
  endpoint,              // ← the transactor WebSocket URL to connect to
  role, allowGuestSignUp?
}
```

Headers: `Authorization: Bearer {token}`, `Content-Type: application/json`, optional `x-timezone`.

**Workspace → transactor resolution** (`server/account/src/utils.ts`): the account service holds a list of transactors (`TRANSACTOR_URL` env, format `internal;external;region`), deterministically hashes the workspace UUID to pick one, and returns its URL as `endpoint`. The client just connects to whatever `endpoint` it's handed — region/load routing is server-side. `kind: 'internal'` vs `'external'` selects internal-network vs public URL.

### 1.3 Transactor WebSocket protocol (the live data channel)

Connect: `ws://{endpoint}/{token}?sessionId={uuid}`
Reference: `foundations/core/packages/client-resources/src/connection.ts`, RPC types `foundations/core/packages/rpc/src/rpc.ts`.

**Handshake:** send a `HelloRequest` (`{ binary?, compression? }`), receive `HelloResponse { binary, serverVersion, lastTx, lastHash, account, useCompression, reconnect }`.

**Serialization:** JSON by default; optional **MessagePack** (via `Packr`) for binary; optional **Snappy** compression. A first mobile cut can use plain JSON.

**Request/Response framing:**
```ts
Request  = { id?, method, params: any[], meta?, time? }
Response = { result?, id?, error?, terminate?, chunk?, rateLimit?, time? }
```

**Core RPC methods (this is essentially the whole data API):**

| Method | Purpose |
|---|---|
| `loadModel(lastTx, hash?)` | Load model transactions → build the `Hierarchy` (class/attr definitions). Do this once at startup. |
| `findAll(_class, query, options?)` | **All reads.** Mongo-style query, returns `FindResult<T>` (+ optional `total`, `lookupMap`). |
| `findOne(_class, query, options?)` | Single doc. |
| `tx(tx)` | **All writes.** Submit a transaction. |
| `searchFulltext(query, options)` | Full-text search. |
| `domainRequest(domain, params)` | Low-level domain ops. |

**Live updates:** the server pushes transactions with **no `id`** (server→client broadcast) as `Response<Tx[]>`. The client feeds these to a registered `TxHandler`, applies them to its local cache, and the UI reacts. This is the real-time mechanism — there is no separate subscribe call; connecting to a workspace subscribes you to its tx stream.

**Keep-alive:** client sends `ping` every ~10s, expects `pong!`; hang timeout ~5 min; dial timeout ~30s.

### 1.4 Data model primitives (`foundations/core/packages/core/src/classes.ts`)

| Concept | Meaning |
|---|---|
| `Ref<T>` | Typed string id of a doc/class. |
| `Obj` | Base; carries `_class`. |
| `Doc` | Persisted object: `_id`, `_class`, `space`, `modifiedOn/By`, `createdOn/By`. |
| `Space` | Multitenancy container; **every doc belongs to a space** (a project, a channel, a team, etc.). |
| `AttachedDoc` | Child doc in a parent's collection (`attachedTo`, `attachedToClass`, `collection`) — e.g. a comment on an issue. |
| `Class<T>` / `Mixin` | Schema metadata, loaded from the model. Mixins add attributes at runtime. |
| `Domain` | Storage partition (`DOMAIN_MODEL`, `DOMAIN_TX`, `DOMAIN_BLOB`, …). |
| `Tx` | A transaction; itself a `Doc`. |

**Query operators** (`storage.ts`): `$in,$nin,$ne,$gt,$gte,$lt,$lte,$exists,$like,$regex,$all,$size,$search`. **FindOptions:** `limit, skip, sort, lookup` (populate refs), `total`.

### 1.5 Writes — transactions & `TxOperations`

Transaction types (`models/core/src/tx.ts`): `TxCreateDoc`, `TxUpdateDoc`, `TxRemoveDoc`, `TxMixin`, `TxApplyIf` (conditional/optimistic), `TxWorkspaceEvent`.

`TxOperations` (`foundations/core/packages/core/src/operations.ts`) is the high-level CRUD helper you'll port:
```
createDoc(_class, space, attributes, id?)        → Ref
updateDoc(_class, space, id, operations)         → Ref
removeDoc(_class, space, id)
addCollection(_class, space, attachedTo, attachedToClass, collection, attributes, id?)
updateCollection(...) / removeCollection(...)
```
Each call builds a `Tx` and sends it via `tx()`. The server then broadcasts it back (and to other clients), keeping everyone in sync.

### 1.6 Files (`foundations/core/packages/storage-client/src/upload.ts`)

- **Download URL:** `{DATALAKE_URL}/blob/{workspace}/{uuid}/{filename}` (token via header or query).
- **Upload:** single `POST` (`{DATALAKE_URL}/upload/form-data/{workspace}`) or **S3-style multipart** in 5 MB chunks (init → PUT parts → complete with ETags). Progress via `{loaded, total, percentage}`.
- **Previews/thumbnails:** `PREVIEW_URL`. **Video:** `STREAM_URL` (HLS).

### 1.7 What you can reuse vs. reimplement

**Reusable as-is (platform-agnostic TS, if you build an RN/TS-bridged client):**
`@hcengineering/core` (model, Tx, hierarchy), `@hcengineering/account-client`, `@hcengineering/rpc`, `@hcengineering/platform`, `@hcengineering/storage-client`. Note `core` must **not** touch DOM/IndexedDB/WebSocket.

**Must implement per platform (Flutter / native):**
WebSocket transport (`web_socket_channel` / native), local persistence instead of IndexedDB (`sqflite`/`Hive` or SQLite), the `ClientConnection` interface, request↔response id matching, model load + `Hierarchy`, optimistic local tx application.

> For a Flutter app you will **reimplement the protocol in Dart** (account RPC client, transactor WS client, a `Doc`/`Tx`/`Hierarchy` runtime, `TxOperations`). The TS packages are the **reference spec**, not a dependency.

---

## 2. Feature Catalog & Mobile Priority

Huly registers user-facing apps in the **workbench** (`plugins/workbench`, navigation in `plugins/workbench-resources`). The full plugin registry is `models/all/src/index.ts`. Shared substrate that nearly every app builds on:

- **task** — base work-item classes (used by Tracker, Recruit, Lead, Board).
- **view** — viewlets/presenters/filters (list, kanban, table renderings).
- **activity** — audit/changelog feed attached to docs.
- **notification + inbox** — cross-app notifications and the unified inbox.
- **attachment**, **tags**, **preference**, **setting**, **contact** (Person/Employee are referenced everywhere).
- **text-editor** — rich text (markup) used by docs, comments, descriptions.

### Tier 1 — MVP (must-have on mobile)

| App | Plugin | Key document classes | Notes |
|---|---|---|---|
| **Tracker** (projects/issues) | `tracker` | `Project`, `Issue`, `IssueStatus`, `Milestone`, `Component`, sub-issues | The flagship PM app; issues are `Task`s. |
| **Chunter** (chat) | `chunter` | `Channel`, `DirectMessage`, `ChatMessage`, threads, reactions | Pairs with `communication`. |
| **Inbox / Notifications** | `notification`, `inbox` | `DocNotifyContext`, `InboxNotification` | The mobile home/activity surface. |
| **Contacts / CRM directory** | `contact` | `Person`, `Organization`, `Employee`, `Channel` (social ids) | Foundational — referenced by all apps. |
| **Documents** | `document` | `Document`, `Teamspace`, versions/snapshots | Read first; collaborative editing later (via Collaborator). |
| **Calendar** | `calendar` | `Event`, `ReccuringEvent`, reminders | |
| **Time / Todos** | `time` | `ToDo`, planned time slots | Personal productivity. |

### Tier 2 — Enhanced

| App | Plugin | Key classes |
|---|---|---|
| **Drive** (files) | `drive` | `Drive`, `Folder`, `File`, versions |
| **Board** (kanban) | `board` | `Board`, `Card` |
| **Lead** (sales CRM) | `lead` | `Funnel`, `Lead`, `Customer` |
| **Recruit** (ATS) | `recruit` | `Vacancy`, `Candidate`, `Applicant`, interviews |
| **HR** | `hr` | `Department`, `Staff`, `Request` (leave) |
| **Activity feed** | `activity` | per-doc change history |

### Tier 3 — Advanced / integrations

`love` (virtual office/video — heavy, needs LiveKit), `gmail`/`mail`/`huly-mail`, `telegram`, `process` (automation), `products`, `inventory`, `survey`, `test-management`, `request`, `controlled-documents` (QMS), `card`, `billing`/`payment`, `bitrix`, `github`, `ai-assistant`/`ai-bot`.

### Likely desktop-only / low mobile value

`process` (workflow builder), `test-management`, `controlled-documents`, advanced `setting`/admin, `devmodel`, `diffview`, `bitrix` import.

**Recommended mobile build order:** Auth → workbench shell + spaces nav → **Inbox/Notifications** + **Chunter** + **Tracker** (these three deliver 80% of daily mobile value) → Contacts → Calendar/Time → Documents (read) → Drive → then Tier 2/3 as needed.

---

## 3. UI Theme / Design System (match Huly exactly)

Source: `packages/theme/styles/_colors.scss`, `_lumia-colors.scss`, `_vars.scss`, `global.scss`, `common.scss`; palette in `packages/ui/src/colors.ts`. Themes are CSS-variable based with `.theme-dark` / `.theme-light`.

### 3.1 Core semantic tokens

| Token | Dark | Light |
|---|---|---|
| App background | `#161719` | `#F1F1F4` |
| Back (deepest) | `#0E0F10` | `#D9D9DD` |
| Surface 01 / 02 | `#0E0F10` / `#161719` | `#F8F9FA` / `#FFFFFF` |
| Popover/panel bg | `#1F2328` | `#FFFFFF` |
| Text primary | `rgba(255,255,255,.8)` / `#FFFFFF` | `rgba(0,0,0,.8)` / `#0F121A` |
| Text secondary | `#C1C9D6` | `#5A667E` |
| Text tertiary | `#8E99AF` | `#7B879E` |
| Text disabled | `#5A667E` | `#A1ABBF` |
| Divider | `rgba(255,255,255,.06)` | `rgba(0,0,0,.06)` |
| Border (ui) | `#A5BDFF1A` | `#1530721A` |
| **Primary button** | `#3364E2` (hover `#6191FE`, active `#2553CF`) | same |
| Accent text | `#4D7FF5` | `#3566E2` |
| Focus ring | `#2A59D6` | `#204DC8` |
| Error | `#EB5757` | `#EB5757` |
| Warning | `#F2994A` | `#F2994A` |
| Success / won | `#34DB80` | `#34DB80` |
| Link | `#377AE6` | `#377AE6` |

**Priority colors:** none `#8E99AF`, low `#6493FF`/`#3566E2`, medium `#FFBD2E`/`#FF9838`, high/urgent `#F6684B`/`#E9403D`.
**Presence:** active `#34DB80`, busy `#FCC500`, dnd `#D95757`, away `#9099A2`.

### 3.2 Avatar / label palette (24 named accent colors, `packages/ui/src/colors.ts`)

Firework `#D15045`, Watermelon `#DB877D`, Pink `#EF86AA`, Fuchsia `#EB5181`, Lavander `#DC85F5`, Mauve `#925CB1`, Heather `#7B86C6`, Orchid `#8458E3`, Blueberry `#6260C2`, Arctic `#8BB0F9`, Sky `#4CA6EE`, Cerulean `#5195D7`, Waterway `#1467B3`, Ocean `#167B82`, Turquoise `#58B99D`, Houseplant `#46A44F`, Crocodile `#709A3F`, Grass `#83AF12`, Sunshine `#D29840`, Orange `#D27540`, Pumpkin `#BF5C24`, Cloud `#A1A1A1`, Coin `#939395`, Porpoise `#758595`. (Each has icon + darker title variant; avatars also have an HSL set with ±sat/±light shifts for dark mode.) Pick by `hash(id) % 24`.

### 3.3 Type, spacing, radius, elevation

- **Fonts:** `IBM Plex Sans` (UI), `IBM Plex Mono` (code). Weights 400/500/600/700. Base body **14px**; sizes 11/12/14/16/18/20. Line-heights tight 1.0, normal 1.25, relaxed 1.5.
- **Spacing** (8px grid): 2,4,6,8,12,16,20,24,28,32,40,48,56,64,80,96,120 px.
- **Element sizes:** xs 24, sm 32, md 40, lg 48, xl 56, max 64 px.
- **Radius:** 2 / 4 / 6 / 8 / 16 px (min→large). Buttons & cards use 8px.
- **Elevation (dark):** popup `0 4px 24px rgba(0,0,0,.5)`, card `0 16px 70px rgba(0,0,0,.5)`, button `0 1px 1px rgba(0,0,0,.15)`. Light: popup `0 4px 24px rgba(0,0,0,.2)`.

### 3.4 Component conventions

- **Buttons:** heights 48/40/32/24 (lg/md/sm/xs), radius 8 (6 for sm/xs), horizontal padding 16 (8 sm), gap 8; primary = `#3364E2` on white text; secondary = subtle `#d1d5de0d` translucent; tertiary = transparent. Focus = 2px outline `#2A59D6`, 2px offset.
- **Inputs:** translucent bg (`#a5bdff0d` dark / `#1530720d` light), error border `#FB6863`, placeholder `#8B97AD`.
- **Cards/panels (`.hulyComponent`):** 1px divider border, radius 8, panel bg `#161719`/`#FFFFFF`. Panel header 18px/700.
- **Nav element:** height 32, padding 12, radius 6, icon 20 + 8px gap.

Translate to a **Flutter `ThemeData`** (two `ColorScheme`s + `TextTheme` IBM Plex + a tokens file for spacing/radius), or a **design-tokens JSON** for RN. The two agent reports included ready-to-paste Flutter/RN starters.

---

## 4. Self-Hosting — what the mobile app must reach

Minimal public surface for a **fully functional** client:

| Service | Port | Required for | Public |
|---|---|---|---|
| **front** | 8087 | `config.json` discovery, static/branding | ✅ |
| **account** | 3000 | login, workspace selection | ✅ |
| **transactor** | 3332 | real-time data (findAll/tx/live) | ✅ |
| **collaborator** | 3078 | collaborative doc editing | ✅ (docs) |
| **datalake** (or hulylake) | 4030 / 8096 | file up/download | ✅ |
| **preview** | 4040 | image/doc thumbnails | ✅ |
| **stream** | 1080 | video playback | ✅ (recordings/love) |
| **hulypulse** | 8099 | push notifications | ✅ (notifications) |
| fulltext, workspace, media, stats | — | internal only (reached via transactor) | ❌ |

Auth is **JWT bearer tokens** end-to-end (no session cookies needed for mobile). CORS with credentials is enabled on account/front. Production: front these with a reverse proxy for TLS. The app only needs the **base URL**; `config.json` supplies the rest.

---

## 5. Recommended mobile architecture

1. **Transport layer (Dart/native):** account RPC client (HTTP) + transactor client (WebSocket) + datalake file client. Mirror `account-client` and `connection.ts`.
2. **Model runtime:** load model via `loadModel`, build a `Hierarchy` (classes/attributes/mixins) and a local `ModelDb`. Cache the model (keyed by `lastHash`) so startup is fast.
3. **Local store + reactivity:** apply incoming `Tx[]` to a local cache (SQLite/Hive); expose reactive queries so screens auto-update. Implement optimistic `TxOperations` (apply locally, send, reconcile on broadcast).
4. **Feature modules:** one module per app (Tracker, Chunter, …) that knows its document classes and renders/edits them via the generic layer. Start with Inbox+Chunter+Tracker.
5. **Theme:** port the tokens in §3 into a shared design system; support light/dark + branding.json overrides.
6. **Files/media:** datalake up/download, preview for thumbnails, HLS for video.
7. **Push:** hulypulse WS while foregrounded; native push (FCM/APNs) using `PUSH_PUBLIC_KEY` for background.

**Build order:** protocol layer → model/hierarchy → reactive store → auth+workspace UI → workbench shell → Inbox/Chunter/Tracker → expand.

---

## 6. Key file reference

| Area | Path |
|---|---|
| Core model (Doc/Class/Ref/Tx) | `foundations/core/packages/core/src/classes.ts`, `.../operations.ts`, `.../storage.ts` |
| Transaction classes | `models/core/src/tx.ts` |
| Account RPC client + types | `foundations/core/packages/account-client/src/{client,types}.ts` |
| Transactor WS connection | `foundations/core/packages/client-resources/src/connection.ts` |
| RPC framing | `foundations/core/packages/rpc/src/rpc.ts` |
| File upload/storage | `foundations/core/packages/storage-client/src/upload.ts` |
| Front config.json | `server/front/src/index.ts`, `server/front/src/starter.ts` |
| Account service / workspace→transactor | `server/account-service/src/index.ts`, `server/account/src/utils.ts` |
| Web client bootstrap (reference flow) | `plugins/workbench-resources/src/connect.ts`, `plugins/login-resources/src/utils.ts` |
| App registry | `models/all/src/index.ts`; per-app `plugins/<app>/src/index.ts` + `models/<app>/src/index.ts` |
| Theme tokens | `packages/theme/styles/{_colors,_lumia-colors,_vars,global,common}.scss` |
| Color palette | `packages/ui/src/colors.ts` |

---

*Generated via `/understand` (scoped deep-dive instead of a full 10k-file graph). Verify exact field names against the cited files before implementing — the protocol layer is the highest-risk area to get right.*
