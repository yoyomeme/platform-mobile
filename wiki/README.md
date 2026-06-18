# Wiki Template

A reusable, schema-first wiki system for SDK/library documentation. Designed for AI-agent maintenance with hash-based change detection.

## Quick Start

### 1. Copy into your repo

```bash
cp -r wiki-template/ your-repo/wiki/
cd your-repo/wiki/
```

### 2. Replace placeholders

Search and replace these across all files:

| Placeholder | Replace with | Example |
|---|---|---|
| `Huly Platform` | Your SDK/library name | `AuthKit`, `PaymentSDK` |
| `typescript` | Primary source language | `kotlin`, `typescript`, `swift` |
| `foundations/**, packages/**, plugins/**, models/**, server/**, services/**, pods/**` | Glob patterns for source tracking | `src/**/*.kt` |
| `@hcengineering` | Top-level package/module | `com.example.sdk` |
| `getClient()` | How to access the singleton | `AuthKit.shared`, `AuthKit.getInstance()` |

```bash
# Example with sed:
find . -name '*.md' -exec sed -i '' 's/Huly Platform/MySDK/g' {} +
find . -name '*.md' -exec sed -i '' 's/typescript/kotlin/g' {} +
find . -name '*.md' -exec sed -i '' 's/foundations/**, packages/**, plugins/**, models/**, server/**, services/**, pods/**/src\/\*\*\/\*.kt/g' {} +
find . -name '*.md' -exec sed -i '' 's/@hcengineering/com.example.sdk/g' {} +
find . -name '*.md' -exec sed -i '' 's/getClient()/MySDK.getInstance()/g' {} +
```

### 3. Update wiki-hash.sh

Edit the `TRACK_PATTERNS` array in `wiki-hash.sh` to match your source layout:

```bash
TRACK_PATTERNS=(
  "src/**/*.kt"        # your source files
  "docs/**/*.md"       # your docs
)
```

### 4. Set up file-to-wiki mapping

Edit `.file-wiki-map.tsv` — each line maps a source path prefix to a wiki page:

```tsv
src/services/AuthService.kt	services/auth-service.md
src/types/	types/auth-types.md
```

### 5. Create the initial snapshot

```bash
bash wiki/wiki-hash.sh snapshot
```

### 6. Create your wiki pages

Use the `_template-*.md` files as starters. For each page:

1. Copy the relevant template: `cp _template-service.md my-service.md`
2. Fill in the sections following the page structure below
3. Add cross-references to related pages
4. Update `index.md` with a link to the new page

### 7. Verify

```bash
bash wiki/wiki-hash.sh status    # should say "UP TO DATE"
```

### 8. Set up daily sync (optional)

Use a scheduled task to run:

```bash
bash wiki/wiki-auto-update.sh detect
# If stale → read affected pages + source → update pages → refresh
bash wiki/wiki-auto-update.sh refresh
```

---

## Page Structure

Every wiki page follows this mandatory section order:

```
# Title

> One-line summary of what this page covers.

## Where in code
- `path/to/source/file.ext` -- brief description

## Purpose
Why this exists and what problem it solves.

## Details
Main content — code, diagrams, tables, sub-sections.

## Cross-references
- Related: [page-name](path/to/page.md)

## Gotchas
Non-obvious behavior or common pitfalls.
```

## Directory Layout

```
wiki/
├── WIKI.md              Schema (this system's rules)
├── index.md             Navigation hub
├── overview.md          One-page synthesis
├── api-reference.md     Condensed public API lookup
├── architecture.md      Layer diagram, service topology
├── configuration.md     Init/setup, singleton pattern
├── log.md               Chronological change log
├── services/            One page per service/module
├── types/               Public types, enums, error types
├── flows/               Sequence diagrams, step-by-step flows
├── api/                 HTTP/API endpoint docs
├── security/            Crypto, key management, storage
├── concepts/            Cross-cutting architectural ideas
├── .file-wiki-map.tsv   Source-to-wiki page mapping
├── .source-hashes.json  Hash baseline (auto-generated)
├── wiki-hash.sh         SHA-256 change detection
├── wiki-sync.sh         File-to-page sync
└── wiki-auto-update.sh  Daily automation driver
```

## Naming Conventions

- **Files**: `kebab-case` matching the source type (e.g., `auth-service.md` for `AuthService.kt`)
- **Directories**: organized by domain
- **One topic per file**
- **Concept pages**: describe the idea (e.g., `concurrency-model.md`, `error-strategy.md`)
