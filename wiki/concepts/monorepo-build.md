# Monorepo & Build (Rush + PNPM)

> How the Huly platform is structured and built: a **Rush**-orchestrated, **PNPM**-installed monorepo of ~486 projects, organized into `foundations/`, `packages/`, `plugins/`, `models/`, `server/`, `services/`, `pods/`, and the **plugin-triad** convention every feature follows.

## Where in code

| Component | File | Purpose |
|-----------|------|---------|
| Rush config | `rush.json` | project registry (~486 entries), tool versions |
| Custom commands | `common/config/rush/command-line.json` | `build`, `format`, `validate`, phases |
| Shared scripts | `common/scripts/` | docker, versioning, formatting helpers |
| Build rig | `foundations/utils/packages/platform-rig` | the `compile` binary used by every project's `build` |
| Lockfile | `common/config/rush/pnpm-lock.yaml` | PNPM resolution |
| Example plugin triad | `plugins/chunter`, `plugins/chunter-resources`, `plugins/chunter-assets`, `models/chunter` | chat feature |

## Purpose

Huly is hundreds of interdependent TypeScript packages — core runtime, model definitions, ~190 feature plugins, backend services, and deployable pods. A flat `npm` setup would be unmanageable: builds would be unordered, versions would drift, and cross-package links would break. **Rush** (by Microsoft) provides deterministic, dependency-ordered, incremental builds across the whole repo, while **PNPM** provides fast, content-addressed, workspace-aware installs. Every project is registered once in `rush.json` and built through a shared rig.

## Details

### Tooling

```jsonc
// rush.json
{
  "rushVersion": "5.158.1",
  "pnpmVersion": "10.15.1",
  "nodeSupportedVersionRange": ">=20.0.0 <25.0.0"
}
```

Every project is listed explicitly with its package name and folder:

```jsonc
{
  "packageName": "@hcengineering/chunter",
  "projectFolder": "plugins/chunter"
}
```

### Project layout

The ~486 projects group by `projectFolder` prefix:

| Directory | Count | Holds |
|-----------|-------|-------|
| `plugins/` | ~190 | user-facing **feature apps** (tracker, chunter, drive, document, …) and their `-resources`/`-assets` |
| `models/` | ~94 | **model packages** — class/attribute/mixin definitions per feature (`@hcengineering/model-*`) |
| `server-plugins/` | ~63 | server-side logic per feature (triggers, indexing config) |
| `foundations/` | ~50 | the **core platform**: `core`, `rpc`, `platform`, `account-client`, `storage-client`, server packages, `text-*`, `communication` |
| `services/` | ~32 | standalone backend services (datalake, rekoni, mail, …) |
| `packages/` | ~15 | shared cross-cutting libs (`ui`, `theme`, `rekoni`, presenters) |
| `pods/` | ~13 | **deployable processes** (transactor=`pods/server`, `pods/fulltext`, `pods/workspace`, …) |
| `dev/`, `ws-tests/` | small | dev tooling and integration tests |

Conceptually, dependencies flow upward:

```
              pods/        (deployable processes: transactor, fulltext, ...)
                ▲
   services/   │   server/ + server-plugins/   (backend services & per-feature server logic)
        ▲      │        ▲
        └──────┴────────┘
                ▲
   plugins/  +  models/        (feature UI/resources/assets  +  feature data model)
                ▲
   packages/ (ui, theme)  +  foundations/ (core, rpc, platform, communication, text-*)
```

`foundations/core` is the root — it defines `Doc`/`Tx`/`Hierarchy` and must not depend on anything platform-specific (no DOM/WebSocket), so it can be reused by any client.

### The plugin triad (+ model)

A Huly feature is not one package but a coordinated **set**, by convention `<x>` + `<x>-resources` + `<x>-assets` + `models/<x>`:

| Package | Name | Role |
|---------|------|------|
| `plugins/<x>` | `@hcengineering/<x>` | **Plugin definition** — IDs, class refs, plugin contract. Pure, importable anywhere. |
| `plugins/<x>-resources` | `@hcengineering/<x>-resources` | **UI implementation** — Svelte components, presenters, actions (`"build": "compile ui"`). |
| `plugins/<x>-assets` | `@hcengineering/<x>-assets` | **Static assets** — icons, i18n strings. |
| `models/<x>` | `@hcengineering/model-<x>` | **Model** — declares the feature's classes/attributes/mixins as model transactions. |

Concrete example (chat):

```
plugins/chunter            → @hcengineering/chunter           (definition)
plugins/chunter-resources  → @hcengineering/chunter-resources (Svelte UI)
plugins/chunter-assets     → @hcengineering/chunter-assets    (icons/i18n)
models/chunter             → @hcengineering/model-chunter     (Channel, ChatMessage, ...)
```

This split is what makes the platform pluggable: the **definition** is a lightweight contract everything can import; the **model** is loaded into the workspace via `loadModel` to extend the `Hierarchy`; the **resources** are lazy-loaded UI; the **assets** are bundled separately. The full registry of features is assembled in `models/all/src/index.ts`.

> **Why the split matters for a mobile client:** you depend on the `<x>` *definition* (class refs) and read the *model* at startup to learn the classes — you do **not** depend on `-resources` (Svelte) or `-assets`. A native client re-implements the UI from the definition + model.

### Build via the rig

Each project's `package.json` delegates `build` to a shared `compile` binary from `platform-rig`:

```jsonc
// plugins/chunter/package.json
"scripts": { "build": "compile" },
"devDependencies": { "@hcengineering/platform-rig": "workspace:^0.7.21" }

// plugins/chunter-resources/package.json
"scripts": { "build": "compile ui" }   // 'ui' variant bundles Svelte
```

`compile` lives at `foundations/utils/packages/platform-rig/bin/compile.js` and standardizes TypeScript/bundling so individual projects don't each carry build config. The `workspace:^` protocol is PNPM workspace linking — packages resolve to sibling source, not the registry.

### Building the repo

Rush drives everything in dependency order with caching:

```bash
# install all dependencies (PNPM workspace) — run from repo root
node common/scripts/install-run-rush.js install

# build every project in topological order (incremental/cached)
node common/scripts/install-run-rush.js build

# build one project and its dependencies
node common/scripts/install-run-rush.js build --to @hcengineering/chunter

# format / validate (custom commands in command-line.json)
node common/scripts/install-run-rush.js format
node common/scripts/install-run-rush.js validate

# run a project's own script
node common/scripts/install-run-rushx.js test
```

`command-line.json` defines the phased `build`/`rebuild`/`validate`/`svelte-check` commands and bulk `format`. Cobuild/build-cache config lives under `common/config/rush/`. Deployable **pods** are then packaged into Docker images via `common/scripts/docker*.sh`.

```
rush install            rush build                 docker.sh
─────────────           ──────────                 ─────────
PNPM workspace   ──▶    topo-sorted, cached  ──▶   per-pod images
install (lockfile)      `compile` per project       (transactor, fulltext, ...)
```

### Key properties

| Property | Value | Description |
|----------|-------|-------------|
| Orchestrator | Rush 5.158.1 | dependency-ordered builds, caching |
| Package manager | PNPM 10.15.1 | workspace install, lockfile |
| Node | `>=20 <25` | enforced range |
| Projects | ~486 | all listed in `rush.json` |
| Per-project build | `compile` (platform-rig) | shared rig binary |
| Feature unit | triad + model | `<x>` / `-resources` / `-assets` / `model-<x>` |

## Cross-references

- [collaboration-crdt](collaboration-crdt.md) — uses the `foundations/.../text-*` packages
- [communication](communication.md) — lives under `foundations/communication`
- [storage-blobs](storage-blobs.md) — `foundations/core/packages/storage-client`
- Service: [transactor](../services/transactor.md) (the `pods/server` process)
- Plugins: [chunter](../plugins/chunter.md), [document](../plugins/document.md), [drive](../plugins/drive.md)

## Gotchas

- **Always build from the repo root via Rush.** Sub-repos like `foundations/communication` are submodules with no independent build; `cd`-ing in and running `npm` won't work (see its README).
- **Add new projects to `rush.json`.** A package that isn't registered there is invisible to install/build.
- **`workspace:^` links to sibling source.** Bumping a shared package needs a rebuild of dependents; Rush orders this, ad-hoc `tsc` does not.
- **The triad is a convention, not enforced.** Most features follow `<x>`/`-resources`/`-assets`/`model-<x>`, but a few deviate — confirm by checking `rush.json` rather than assuming all four exist.
- **Mobile clients consume definition + model only.** Don't pull `-resources`/`-assets` into a native client — they're Svelte/asset bundles, not portable logic.
- **Node version is range-pinned.** Outside `>=20 <25`, install/build can fail in non-obvious ways.
