# Huly Platform Wiki — Index

> Structured knowledge base for the Huly Platform monorepo.
> Purpose: enable developers and AI agents to understand the whole codebase — core runtime, transaction model, server services, and 190+ feature plugins — and to build/port clients.

## Schema

- [WIKI](WIKI.md) — Wiki schema: three-layer model, page template, maintenance rules, automation

## Overview

- [overview](overview.md) — What Huly is, design goals, technology stack
- [architecture](architecture.md) — Layer diagram, service topology, data flow
- [configuration](configuration.md) — Boot/connection chain (config → login → workspace → transactor)
- [api-reference](api-reference.md) — Condensed lookup for all public APIs

## Concepts (cross-cutting architecture)

- [plugin-architecture](concepts/plugin-architecture.md) — Plugin/resource registry, `@hcengineering/platform`
- [data-model](concepts/data-model.md) — `Doc`/`Class`/`Ref`/`Mixin`/`Hierarchy`/`ModelDb`
- [transaction-model](concepts/transaction-model.md) — `Tx` types, `TxOperations`, apply & broadcast
- [client-protocol](concepts/client-protocol.md) — Transactor WebSocket, RPC framing, live updates
- [live-queries](concepts/live-queries.md) — `LiveQuery`/`createQuery` reactivity
- [model-layer](concepts/model-layer.md) — `models/` builder DSL, decorators, migrations
- [communication](concepts/communication.md) — Messaging/notification subsystem (`foundations/communication`)
- [collaboration-crdt](concepts/collaboration-crdt.md) — Y.js collaborative editing
- [storage-blobs](concepts/storage-blobs.md) — Datalake/hulylake blob storage
- [event-queue](concepts/event-queue.md) — Redpanda/Kafka async events
- [fulltext-search](concepts/fulltext-search.md) — Indexing & search pipeline
- [workspace-multitenancy](concepts/workspace-multitenancy.md) — Workspaces, spaces, domains
- [ui-framework](concepts/ui-framework.md) — Svelte UI, presentation layer, theme
- [localization](concepts/localization.md) — `IntlString` / platform i18n
- [monorepo-build](concepts/monorepo-build.md) — Rush/PNPM, project layout, build

## Services (server runtime + core packages)

- [account](services/account.md) — Auth & user/workspace management (:3000)
- [transactor](services/transactor.md) — Transaction processing pipeline (:3332)
- [workspace](services/workspace.md) — Workspace lifecycle/upgrades
- [fulltext-service](services/fulltext-service.md) — Search indexing (:4702)
- [collaborator](services/collaborator.md) — Real-time doc collaboration (:3078)
- [front](services/front.md) — Web server + `config.json` (:8087)
- [datalake](services/datalake.md) — Blob storage (:4030)
- [backup](services/backup.md) — Backup/restore
- [core-package](services/core-package.md) — `@hcengineering/core`
- [platform-package](services/platform-package.md) — `@hcengineering/platform`
- [client-package](services/client-package.md) — Client + connection
- [query-package](services/query-package.md) — `@hcengineering/query` (LiveQuery)
- [presentation-package](services/presentation-package.md) — `@hcengineering/presentation`
- [ui-package](services/ui-package.md) — `@hcengineering/ui` + theme

## Plugins (feature apps)

- [catalog](plugins/catalog.md) — **All 190+ plugins** grouped by tier (full coverage)
- [workbench](plugins/workbench.md) — App shell / navigation
- [login](plugins/login.md) — Login/onboarding UI
- [tracker](plugins/tracker.md) — Projects & issues (flagship PM)
- [chunter](plugins/chunter.md) — Chat (channels, DMs, threads)
- [notification](plugins/notification.md) — Notifications
- [inbox](plugins/inbox.md) — Unified inbox
- [contact](plugins/contact.md) — Contacts/CRM directory (Person/Employee)
- [document](plugins/document.md) — Collaborative documents
- [calendar](plugins/calendar.md) — Events & reminders
- [time](plugins/time.md) — ToDos & planning
- [drive](plugins/drive.md) — Files
- [board](plugins/board.md) — Kanban
- [lead](plugins/lead.md) — Sales CRM
- [recruit](plugins/recruit.md) — Applicant tracking
- [hr](plugins/hr.md) — HR (departments, leave)
- [activity](plugins/activity.md) — Change feed
- [task](plugins/task.md) — Base work-item substrate
- [view](plugins/view.md) — Viewlets/presenters/filters
- [attachment](plugins/attachment.md) — Attachments
- [tags](plugins/tags.md) — Tags/labels
- [text-editor](plugins/text-editor.md) — Rich text (markup)
- [setting](plugins/setting.md) — Settings/admin
- [card](plugins/card.md) — Generic card system

## Types

- [core-types](types/core-types.md) — `Doc`, `Obj`, `Ref`, `Space`, `Account`, `AttachedDoc`, `Class`, `Mixin`, `Domain`
- [tx-types](types/tx-types.md) — `TxCreateDoc`, `TxUpdateDoc`, `TxRemoveDoc`, `TxMixin`, `TxApplyIf`, …
- [query-types](types/query-types.md) — `DocumentQuery`, `FindOptions`, `FindResult`, operators
- [platform-types](types/platform-types.md) — `Resource`, `Plugin`, `Metadata`, `Asset`, `IntlString`, `Status`
- [communication-types](types/communication-types.md) — Messaging/notification types

## Flows

- [login-flow](flows/login-flow.md) — config → login → selectWorkspace → connect
- [model-load-flow](flows/model-load-flow.md) — loadModel → Hierarchy
- [transaction-flow](flows/transaction-flow.md) — createDoc → tx → persist → broadcast
- [live-query-flow](flows/live-query-flow.md) — createQuery → reactive updates
- [file-upload-flow](flows/file-upload-flow.md) — datalake upload (form + multipart)
- [collaboration-flow](flows/collaboration-flow.md) — collaborative doc editing
- [notification-flow](flows/notification-flow.md) — notification generation & delivery

## API

- [front-config](api/front-config.md) — `config.json` discovery
- [account-api](api/account-api.md) — Account JSON-RPC methods
- [transactor-rpc](api/transactor-rpc.md) — Transactor WebSocket RPC
- [datalake-api](api/datalake-api.md) — Blob storage endpoints

## Security

- [authentication](security/authentication.md) — JWT, tokens, `SERVER_SECRET`
- [authorization](security/authorization.md) — Roles, spaces, permissions
- [token-package](security/token-package.md) — `@hcengineering/server-token`
