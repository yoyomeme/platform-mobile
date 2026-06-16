# Wiki Template Setup Instructions

You are setting up a structured wiki for this repository. Follow these steps exactly.

## Step 1: Analyze the codebase

Read the repository to determine:

- **Project name**: The SDK/library name (from package.json, build.gradle, Package.swift, pubspec.yaml, Cargo.toml, go.mod, or the main source directory name)
- **Language**: Primary source language (look at file extensions)
- **Source patterns**: Glob patterns for main source directories (e.g., `src/**/*.kt`, `lib/**/*.dart`)
- **Package name**: Top-level module/namespace (from imports or package declarations)
- **Singleton access**: How the main entry point is accessed (e.g., `MySDK.shared`, `MySDK.getInstance()`, `MySDK()`)

Scan the source tree with `find` or glob to identify:
- Services/modules (classes/objects that encapsulate a domain)
- Public types (data classes, enums, error types)
- API/HTTP endpoints
- Security/crypto modules
- Key user flows (multi-step sequences)
- Cross-cutting concepts (concurrency model, error strategy, architecture patterns)

## Step 2: Copy and rename

```bash
cp -r wiki-template/ wiki/
```

## Step 3: Replace all placeholders

Replace these across ALL files in `wiki/`:

| Placeholder | What to replace with |
|---|---|
| `{{PROJECT_NAME}}` | The project name from Step 1 |
| `{{LANGUAGE}}` | The language file extension (e.g., `kotlin`, `typescript`, `dart`, `swift`, `go`, `rust`, `python`) |
| `{{SOURCE_PATTERNS}}` | Glob patterns for source tracking (e.g., `src/**/*.kt`) |
| `{{PACKAGE_NAME}}` | The top-level package/module name |
| `{{SINGLETON_ACCESS}}` | How to access the main entry point |

## Step 4: Update wiki-hash.sh

Edit the `TRACK_PATTERNS` array in `wiki/wiki-hash.sh` to match the actual source layout. Replace the `{{SOURCE_PATTERNS}}` placeholder with the real glob patterns. Add any additional exclusion patterns needed (e.g., `grep -v '/vendor/'`).

## Step 5: Create .file-wiki-map.tsv

Replace the commented examples in `wiki/.file-wiki-map.tsv` with actual mappings. Format: `source_path_prefix<TAB>wiki_page_path` (tab-separated, one per line).

Map each source file/directory to its corresponding wiki page:
- `src/services/AuthService.kt` → `services/auth-service.md`
- `src/types/` → `types/type-page.md`
- `src/api/` → `api/endpoints.md`

## Step 6: Create wiki pages from templates

For each service, type, flow, API, security module, and concept you found in Step 1:

1. Copy the relevant `_template-*.md` file:
   - `cp wiki/services/_template-service.md wiki/services/auth-service.md`
   - `cp wiki/types/_template-type.md wiki/types/auth-types.md`
   - `cp wiki/flows/_template-flow.md wiki/flows/login-flow.md`
   - etc.

2. Fill in each page by reading the actual source code:
   - **Title**: the actual class/type name
   - **Summary**: one-line description
   - **Where in code**: actual file paths from the repo
   - **Properties/Methods/Fields**: extracted from the source code, with actual types and signatures
   - **Code examples**: real usage from the codebase
   - **Cross-references**: links to related wiki pages
   - **Gotchas**: non-obvious behavior found in the code

3. Delete the `_template-*.md` starter files when done.

## Step 7: Fill the top-level pages

- **overview.md**: Describe the project, design goals, tech stack, quick start
- **architecture.md**: Draw a layer diagram using ASCII box characters, list service responsibilities
- **configuration.md**: Document the init/setup flow
- **api-reference.md**: Create condensed lookup tables for all public APIs
- **index.md**: Add links to every page you created, organized by section

## Step 8: Create the initial hash snapshot

```bash
bash wiki/wiki-hash.sh snapshot
```

## Step 9: Add the initial log entry

Replace the template entry in `wiki/log.md` with the actual date and page count:

```markdown
## [YYYY-MM-DD] ingest | Initial wiki creation

- Created wiki from [PROJECT_NAME] source code
- Pages created: [count] (overview, architecture, configuration, N services, N types, N flows, N api, N security, N concepts)
- Source: [source patterns]
```

## Step 10: Verify

1. Run `bash wiki/wiki-hash.sh status` — should say "UP TO DATE"
2. Check that every page linked in `index.md` exists
3. Check that cross-references in each page point to existing files
4. Report the final file count and structure to the user
