# Configuration

## Where in code

- `path/to/SDKClient.{{LANGUAGE}}` — `configure()` method, singleton init, state guards

> How to initialize the {{PROJECT_NAME}} SDK and what happens internally.

## The one required call

```{{LANGUAGE}}
import {{PACKAGE_NAME}}

// Call once at app launch
{{SINGLETON_ACCESS}}.configure(
    // List required and optional parameters
)
```

## What `configure()` does internally

```
{{SINGLETON_ACCESS}}.configure()
    │
    ├── 1. Validates parameters
    ├── 2. Initializes service dependencies
    ├── 3. Sets up networking/transport
    ├── 4. Creates service instances
    └── 5. Marks as configured
            └── All subsequent service calls work
```

## Singleton pattern

<!-- Describe how the singleton is accessed -->

## Identity values

| Value | Set by | Used by |
|-------|--------|---------|
| | | |

## Cross-references

- [overview](overview.md) — SDK description
- [architecture](architecture.md) — Layer diagram

## Gotchas

<!-- Non-obvious configuration behavior -->
