# Backup

> Periodic archival of workspace data to object storage, plus a read API to browse/download backups. The backup **service** runs on an interval backing up every eligible workspace; the backup **API** (port `4039`) serves backup files over HTTP.

## Where in code
- `server/backup/src/service.ts` -- `backupService()` (scheduler loop), `BackupConfig`, `doBackupWorkspace`, `doRestoreWorkspace`.
- `server/backup/src/backup.ts` -- `backup()`: the actual incremental snapshot algorithm.
- `server/backup/src/restore.ts` -- `restore()`: replay a backup into a workspace pipeline.
- `server/backup/src/storage.ts` -- `createStorageBackupStorage`, `createFileBackupStorage` (`BackupStorage`).
- `server/backup-service/src/index.ts` -- `startBackup()`: wires storage/pipeline/token and starts `backupService`.
- `server/backup-service/src/config.ts` -- env-driven `Config` for the worker.
- `services/backup/backup-api-pod/src/server.ts` -- backup-api HTTP server (`GET /api/backup/:workspace/:file`).
- `services/backup/backup-api-pod/src/config.ts` -- backup-api `Config` (port `4039`).

## Purpose
Workspaces must survive data loss and support archive/migration. The backup service periodically snapshots each workspace's transactions and blobs into a backup bucket using an incremental, snapshot-based format (keeping the last N snapshots), and provides restore for recovery, archival, and region migration. The backup-api exposes those stored backup artifacts for inspection/download.

## Responsibilities
### Backup service (`server/backup` + `server/backup-service`)
- **Scheduled loop** (`backupService`): every `INTERVAL` seconds, enumerate workspaces (via account, system token `service: 'backup'`) and back up those due, skipping `SKIP_WORKSPACES`, with `PARALLEL` concurrency and a `COOL_DOWN` between retries.
- **Snapshot backup** (`backup`/`doBackupWorkspace`): incremental snapshots through a `createBackupPipeline` (triggers disabled), retaining `KEEP_SNAPSHOTS` snapshots, writing to a `BackupStorage` over the backup bucket.
- **Restore** (`restore`/`doRestoreWorkspace`): replay a snapshot into a (re)built workspace pipeline.
- Progress reported to account via `updateWorkspaceInfo` (`ping`/`progress`).
- The workspace service can run backup in-process (`WS_OPERATION=all+backup`) reusing the same `doBackupWorkspace`.

### Backup API (`backup-api-pod`)
- Serve backup files: `GET /api/backup/:workspace/:file(*)` streams a file from the backup `BackupStorage` (with conditional `304` support; gzip-aware), used to browse/download snapshot contents.
- Statistics/health endpoint.

## Key endpoints/methods

### Backup API HTTP (`backup-api-pod`, port `4039`)
| Method / Path | Purpose |
|---------------|---------|
| `GET /api/backup/:workspace/:file(*)` | Stream a backup file from storage (etag/`304`, gzip). |
| `GET /api/v1/statistics` | Metrics/health. |
| `GET /` | Service banner. |

### Backup service functions (no inbound HTTP)
| Function | Purpose |
|----------|---------|
| `backupService(ctx, storage, config, pipelineFactory, getConfig, region)` | Start the scheduled backup loop. |
| `doBackupWorkspace(...)` | Back up one workspace (used by service and workspace pod). |
| `doRestoreWorkspace(...)` | Restore one workspace from a backup. |

## Configuration

### Backup service (`server/backup-service/src/config.ts`)
| Env var | Default | Description |
|---------|---------|-------------|
| `ACCOUNTS_URL` | (required) | Account service. |
| `ACCOUNTS_DB_URL` | (required) | Account DB URL. |
| `SECRET` | `secret` | Token signing (`service: 'backup'`). |
| `BUCKET_NAME` | `backups` | Backup bucket. |
| `INTERVAL` | `3600` | Backup interval (seconds). |
| `COOL_DOWN` | `300` | Retry cooldown (seconds). |
| `TIMEOUT` | `3600` | Operation timeout (seconds). |
| `DB_URL` | (required) | Workspace DB to back up. |
| `STORAGE` | (required) | Backup bucket storage config. |
| `WORKSPACE_STORAGE` | (required) | Workspace (source) storage config. |
| `SKIP_WORKSPACES` | `''` | Workspaces to skip. |
| `REGION` | `''` | Region this worker serves. |
| `PARALLEL` | `1` | Concurrent backups. |
| `KEEP_SNAPSHOTS` | `84` | Snapshots retained. |
| `SERVICE_ID` | `backup-service` | Identifier. |

> Compose defaults differ in some deployments (e.g. `INTERVAL=60`, `BUCKET_NAME=backups`); see [ARCHITECTURE_OVERVIEW](../../ARCHITECTURE_OVERVIEW.md).

### Backup API (`backup-api-pod/src/config.ts`)
| Env var | Default | Description |
|---------|---------|-------------|
| `PORT` | `4039` | HTTP listen port (`BACKUP_URL` = `…/api/backup`). |
| `SECRET` | `secret` | Token verification. |
| `ACCOUNTS_URL` | — | Account service. |
| `BUCKET_NAME` | — | Backup bucket. |
| `STORAGE` | — | Backup storage config. |

## Cross-references
- Archive/migrate/restore lifecycle that drives backups: [workspace](workspace.md)
- Backup pipeline (`createBackupPipeline`): [transactor](transactor.md)
- Object storage layer: [datalake](datalake.md), [storage-blobs](../concepts/storage-blobs.md)
- Token issuance: [account](account.md)
- Tenant model: [workspace-multitenancy](../concepts/workspace-multitenancy.md)

## Gotchas
- Backups are **incremental, snapshot-based** and capped at `KEEP_SNAPSHOTS` — old snapshots are pruned, so retention is bounded by that count, not time.
- The backup pipeline disables triggers and security middleware (`createBackupPipeline`); it reads/writes raw domain data, so never point it at live client traffic.
- The same `doBackupWorkspace` runs both standalone (backup-service) and in-process (workspace `all+backup`) — choose one path to avoid double-backing-up a region.
- The backup service is region-scoped (`REGION`); workspaces outside its region are not backed up by that instance.
- Backup-API is read-only (download/inspect); creating backups is exclusively the service's job. The `BACKUP_URL` env points at the `/api/backup` prefix on port `4039`.
