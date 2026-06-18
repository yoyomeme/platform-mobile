# Wiki Schema

This wiki is a structured, agent-maintained knowledge base for the **Huly Platform monorepo** (the whole codebase, not a single SDK). It sits between the raw source code (Layer 1) and agent memory (context). Agents read the wiki to gain full project context without re-reading all source files.

## Layers

1. **Raw sources** — the codebase. Immutable. Agents read but never modify.
2. **Wiki** — this directory of markdown pages. Agents own this layer. Humans read it.
3. **Schema** — this file. Tells agents how to maintain the wiki.

## Directory Structure

```
wiki/
├── WIKI.md              (this file)
├── index.md             (navigation hub)
├── overview.md          (one-page SDK synthesis)
├── api-reference.md     (condensed public API lookup)
├── architecture.md      (layer diagram, service topology)
├── configuration.md     (SDK init, singleton, identity values)
├── log.md               (chronological change log)
├── services/            (server runtime services + core packages)
├── plugins/             (feature apps; catalog.md lists all 190+)
├── types/               (pages for important public types)
├── flows/               (sequence diagrams and step-by-step flows)
├── api/                 (HTTP client and endpoint docs)
├── security/            (crypto, key management, secure storage)
└── concepts/            (cross-cutting architectural concepts)
```

> **Note**: this wiki extends the base template with a `plugins/` directory because feature
> plugins are the bulk of the Huly codebase. `services/` holds backend services and the core
> `@hcengineering/*` packages; `plugins/` holds the user-facing feature apps.

## Naming Conventions

- Files use `kebab-case` matching the source type name (e.g., `auth-service.md` for `AuthService.typescript`).
- Organized by domain: `services/`, `types/`, `flows/`, `api/`, `security/`, `concepts/`.
- One topic per file.
- Concept pages describe the idea (e.g., `concurrency-model.md`, `error-strategy.md`).

## Page Template

Every page follows this structure:

```markdown
# Title

> One-line summary of what this page covers.

## Where in code
- `path/to/File.typescript` -- brief description

## Purpose
Why this exists and what problem it solves.

## Details
The main content — can include code, diagrams, tables.

## Cross-references
- Related: [page-name](path/to/page.md)

## Gotchas
Non-obvious behavior or common pitfalls.
```

## Content Patterns

### Code examples
- Use fenced code blocks with language tag (````typescript`)
- Show full method signatures with parameter names and return types
- Include usage examples showing the calling pattern

### Tables
- Method signatures and descriptions
- Type field descriptions
- Error code tables with Code/Step/Trigger columns
- Comparison tables for equivalent mappings

### Diagrams
- ASCII art using box-drawing characters
- Sequence diagrams with message arrows for multi-actor flows
- Layer diagrams for architecture
- State machines for lifecycle documentation

### Error references
- Standardized error code format (e.g., `AUTH-001`, `CERT-001`)
- Each error code maps to a specific failure step and recovery action
- Group by service/phase in error-types page

## Maintenance Triggers

Update the wiki when:
- A new **public type** is added to any service
- A **protocol/interface** changes signature
- A new **service** is created
- An **architectural decision** is made (update concepts/ and log it)
- A **breaking change** is introduced
- A **flow** changes sequence or adds/removes steps

After every update, append an entry to `log.md`.

## What NOT to Wiki

- Private/internal types (they change too often)
- Test implementation details beyond mock patterns
- Generated files (build artifacts)
- Exact line numbers (they shift; use function/type names instead)
- UI/view layer details (unless they expose SDK behavior)

## Operations

### Ingest
When the codebase changes, read the affected files and update the relevant wiki pages. A single change may touch multiple pages (e.g., adding a new error case updates `types/error-types.md`, the relevant service page, and `index.md`).

### Query
When answering questions about the SDK, start by reading `index.md` to find relevant pages, then drill into them. Good answers can be filed back as new pages.

### Lint
Periodically check for: broken cross-links, stale claims that code changes have superseded, orphan pages with no inbound links, concepts mentioned but lacking their own page.

## Automation

The wiki uses SHA-256 hash-based change detection to stay synchronized with the source code.

### How It Works

1. **`wiki/wiki-hash.sh`** hashes all tracked source files and stores them in `wiki/.source-hashes.json`
   - `snapshot` — hash all files, write baseline
   - `diff` — compare current files vs baseline, output JSON with changed/added/removed lists
   - `status` — human-readable summary ("Wiki is UP TO DATE" or "Wiki is STALE")
2. **`wiki/wiki-sync.sh`** maps changed source files to affected wiki pages
   - `check` — detect stale pages and list them with the source files that changed
   - `update` — refresh the hash baseline after wiki pages are updated
   - `report` — generate a `log.md` entry
3. **`wiki/.file-wiki-map.tsv`** maps source directories/files to wiki pages (tab-separated)
4. **`wiki/wiki-auto-update.sh`** ties it all together for daily automation

### Daily Automation

A scheduled task can run daily:
1. Run `wiki-auto-update.sh detect` to detect changes
2. If changes found → read affected wiki pages + changed source files → update pages → refresh hash baseline → append to `log.md`
3. If no changes → log "all current" to `log.md`

### Manual Update

When making significant changes:
1. Run `./wiki/wiki-sync.sh check` to see what's stale
2. Update the affected wiki pages
3. Run `./wiki/wiki-sync.sh update` to refresh the baseline
4. Append an entry to `log.md`
