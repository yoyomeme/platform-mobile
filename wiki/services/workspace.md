# Workspace

> Background worker that drives workspace lifecycle: create/initialize, version upgrade, migration between regions, archive, restore, and delete. It polls the account service for workspaces in pending modes and advances each through a state machine, reporting progress back to account.

## Where in code
- `server/workspace-service/src/index.ts` -- `serveWorkspaceAccount()`: validates `WS_OPERATION`, wires backup storage, constructs the `WorkspaceWorker`.
- `server/workspace-service/src/service.ts` -- `WorkspaceWorker`: the poll loop (`while (!isCanceled())`) and `doWorkspaceOperation` state-machine switch; backup/restore/cleanup helpers.
- `server/workspace-service/src/ws-operations.ts` -- `createWorkspace`, `upgradeWorkspace`, `upgradeWorkspaceWith`: model init and upgrade using `createServerPipeline`.
- `server/workspace-service/src/configuration.ts` -- migration operation set.

## Purpose
Account records a workspace in a `pending-*` mode but does not do the heavy work. The workspace service is the executor: it materializes the database/model for new workspaces, re-runs migrations on version upgrade, performs backup+clean steps when archiving or moving a workspace between regions, restores from backup, and tears down deleted workspaces — all while pushing progress events so the account/UI can reflect status.

## Responsibilities
- **Create / init** (`pending-creation`, `creating`): build the workspace pipeline and apply the model and init migrations.
- **Upgrade** (`upgrading`, `active`): re-apply migrations idempotently when the deployed model version is newer; re-runnable on retry.
- **Archive** (`archiving-pending-backup`/`-backup` then `archiving-pending-clean`/`-clean`): put the transactor into maintenance, run a full backup, then drop the DB (not storages); emits `archived`.
- **Migrate** (`migration-*-backup` → `migration-*-clean`): backup, then clean old DB only when `MIGRATION_CLEANUP=true`.
- **Restore** (`pending-restore`, `restoring`): restore from backup, then upgrade and emit `restored` (triggers fulltext reindex).
- **Delete** (`pending-deletion`, `deleting`): maintenance, clean DB, emit `deleted`.
- **Progress reporting**: `updateWorkspaceInfo(uuid, event, version, progress, message)` to account, with retry; periodic `ping` events while long operations run.
- Optional in-process backup (`all+backup`) using `createBackupPipeline` + `doBackupWorkspace`.

## Key endpoints/methods
This is a worker, not an HTTP server — it has no inbound API. It interacts via the account client (system token) and the message queue.

### Lifecycle state machine (`doWorkspaceOperation`)
| Mode(s) | Action | Emits |
|---------|--------|-------|
| `pending-creation`, `creating` | `_createWorkspace` (model + init) | create progress events |
| `upgrading`, `active` | `_upgradeWorkspace` (re-run migrations) | upgrade progress |
| `archiving-pending-backup`, `archiving-backup` | maintenance + full backup | `archiving-backup-started/done` |
| `archiving-pending-clean`, `archiving-clean` | drop DB | `archiving-clean-*`, `archived` |
| `migration-pending-backup`, `migration-backup` | maintenance + backup | `migrate-backup-*` |
| `migration-pending-clean`, `migration-clean` | clean old DB (if `MIGRATION_CLEANUP`) | `migrate-clean-*` |
| `pending-restore`, `restoring` | restore → upgrade | `restore-*`, `restored` |
| `pending-deletion`, `deleting` | maintenance + clean DB | `delete-*`, `deleted` |

### Operation modes (`WS_OPERATION`)
| Value | Behavior |
|-------|----------|
| `create` | Only create new workspaces. |
| `upgrade` | Only upgrade existing workspaces. |
| `all` | Create + upgrade + lifecycle. |
| `all+backup` | `all` plus in-process backup (requires `BACKUP_STORAGE` + `BACKUP_BUCKET`). |

## Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `WS_OPERATION` | `all` (compose: `all+backup`) | Operation mode (validated; invalid exits). |
| `REGION` | `''` | This worker's region; only handles workspaces in its region. |
| `DB_URL` | (required) | CockroachDB/Postgres connection. |
| `ACCOUNTS_URL` | `http://huly.local:3000` | Account service for polling/progress. |
| `SERVER_SECRET` / `SECRET` | `secret` | System token signing (`service: 'workspace'`). |
| `QUEUE_CONFIG` | `cockroach\|http://redpanda:9092` | Workspace event topic. |
| `STORAGE_CONFIG` | — | Workspace MinIO storage. |
| `BACKUP_STORAGE` | — | Backup bucket storage (required for `all+backup`). |
| `BACKUP_BUCKET` | `backup` | Backup bucket name. |
| `MIGRATION_CLEANUP` | `false` | If `true`, region migration drops the old DB. |
| `MODEL_JSON` | `model.json` | Model/system Tx loaded for init/upgrade. |

## Cross-references
- Records consumed here are created by: [account](account.md)
- Pipelines used for init/upgrade/backup: [transactor](transactor.md)
- Backup mechanics: [backup](backup.md)
- Reindex after restore: [fulltext-service](fulltext-service.md)
- Tenant lifecycle concept: [workspace-multitenancy](../concepts/workspace-multitenancy.md)
- Workspace events on the queue: [event-queue](../concepts/event-queue.md)

## Gotchas
- Region-scoped: a worker only advances workspaces whose `region` matches its `REGION`. A workspace in an unserved region stays pending forever.
- Upgrade is intentionally idempotent and re-runnable — a crashed upgrade is safe to retry, which is why `upgrading` and `active` share the same branch.
- Archive/migrate are two-phase (backup phase then clean phase) so a half-finished archive does not lose data; the clean phase drops the DB but never the object storage.
- `migration-clean` only deletes the source DB when `MIGRATION_CLEANUP=true`; otherwise old data is left behind by design.
- Restore implicitly re-upgrades and requests a fulltext reindex; search will be temporarily incomplete after a restore.
