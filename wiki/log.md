# Wiki Change Log

## [2026-06-17] ingest | Initial wiki creation

- Created comprehensive wiki from the **Huly Platform** monorepo source code.
- **81 markdown pages** total:
  - Top-level (8): WIKI, index, overview, architecture, configuration, api-reference, log, README
  - concepts/ (15): plugin-architecture, data-model, transaction-model, model-layer, localization, client-protocol, live-queries, workspace-multitenancy, ui-framework, storage-blobs, communication, collaboration-crdt, event-queue, fulltext-search, monorepo-build
  - services/ (14): account, transactor, workspace, fulltext-service, collaborator, front, datalake, backup + core-package, platform-package, client-package, query-package, presentation-package, ui-package
  - plugins/ (25): catalog (all ~68 logical plugins / 192 dirs) + tracker, chunter, contact, notification, inbox, document, calendar, time, task, drive, board, lead, recruit, hr, activity, view, attachment, tags, text-editor, setting, card, workbench, login, preference
  - types/ (5): core-types, tx-types, query-types, platform-types, communication-types
  - flows/ (7): login-flow, model-load-flow, transaction-flow, live-query-flow, file-upload-flow, collaboration-flow, notification-flow
  - api/ (4): front-config, account-api, transactor-rpc, datalake-api
  - security/ (3): authentication, authorization, token-package
- Source tracked: foundations/, packages/, plugins/, models/, server/, services/, pods/ (2,339 files hashed into `.source-hashes.json`).
- All internal cross-links verified; hash baseline snapshotted.
