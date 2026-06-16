# Architecture

## Where in code

- Multiple files — this is a cross-cutting overview
- `path/to/entry-point.{{LANGUAGE}}` — Singleton/main entry point
- `path/to/services/` — All service implementations

> Full stack diagram showing how the host app, SDK services, transport layer, and platform security connect.

## Layer diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        HOST APPLICATION                             │
│                                                                     │
│   import {{PACKAGE_NAME}}                                           │
│   {{SINGLETON_ACCESS}}.configure(...)                               │
│   let result = await {{SINGLETON_ACCESS}}.someService.someMethod()  │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           │ Public API
                           │
┌──────────────────────────▼──────────────────────────────────────────┐
│                    SDK Client (Singleton)                            │
│                                                                     │
│   {{SINGLETON_ACCESS}}                                              │
│   ├── serviceA: ServiceA                                            │
│   ├── serviceB: ServiceB                                            │
│   ├── serviceC: ServiceC                                            │
│   └── ...                                                           │
│                                                                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
              ┌────────────┼────────────────┐
              │            │                │
              ▼            ▼                ▼
┌──────────────────┐ ┌──────────────┐ ┌──────────────────┐
│  HTTP Client     │ │  Local ops   │ │  Crypto/Security │
│  (networking)    │ │  (no network)│ │  (platform API)  │
└────────┬─────────┘ └──────┬───────┘ └──────────────────┘
         │                  │
         ▼                  ▼
┌──────────────────┐ ┌──────────────────┐
│  Server API      │ │  Platform Store  │
│  (HTTPS REST)    │ │  (secure storage)│
└──────────────────┘ └──────────────────┘
```

## Service responsibilities

| Service | Network | Crypto | Storage |
|---------|---------|--------|---------|
| ServiceA | | | |
| ServiceB | | | |
| ServiceC | | | |

## Data flow for [primary operation]

<!-- Replace with your most complex flow -->

```
Host App
  │
  │ methodCall(parameters)
  ▼
ServiceA
  │
  │ 1. step one
  │ 2. step two
  │ 3. step three
  │ N. return result
  ▼
Host App receives result
```

## Key design decisions

### Why [pattern A]?

<!-- Explain the reasoning behind a key architectural choice -->

### Why singleton?

<!-- Explain why the SDK uses a singleton pattern -->

## Cross-references

- [overview](overview.md) — High-level SDK description
- [configuration](configuration.md) — How to set up the singleton
- [flows](flows/) — Detailed flow walkthroughs

## Gotchas

<!-- Non-obvious architectural behavior -->
