# [Flow Name]

> One-line summary of what this flow accomplishes.

## Where in code
- `path/to/Service.{{LANGUAGE}}` -- method that implements this flow
- `path/to/Request.{{LANGUAGE}}` -- request types used
- `path/to/API.{{LANGUAGE}}` -- API endpoint definitions

## Sequence

```
 Host App                    Service                     Server/API
    |                          |                            |
    |  methodCall(params)      |                            |
    |------------------------->|                            |
    |                          |  HTTP REQUEST              |
    |                          |  { request body }          |
    |                          |--------------------------->|
    |                          |                            |
    |                          |  { response body }         |
    |                          |<---------------------------|
    |                          |                            |
    |  Result                  |                            |
    |<-------------------------|                            |
```

## Steps

| Step | Action | Error code on failure |
|------|--------|----------------------|
| 1 | First step | `STEP-001` |
| 2 | Second step | `STEP-002` |
| 3 | Third step | |
| N | Complete | |

## Code

```{{LANGUAGE}}
// Full usage example showing the calling pattern
let result = try await {{SINGLETON_ACCESS}}.service.method(
    // parameters
)

guard result.isSuccess else {
    // handle failure
    return
}
// handle success
```

## Prerequisites

- SDK must be configured: `{{SINGLETON_ACCESS}}.configure()`
- Other prerequisites

## Error handling

```{{LANGUAGE}}
do {
    let result = try await {{SINGLETON_ACCESS}}.service.method(...)
    // check result
} catch {
    // handle error
}
```

## Cross-references

- [related-service](../services/related-service.md)
- [related-flow](related-flow.md)
- [error-types](../types/error-types.md)

## Gotchas

- Non-obvious behavior in this flow
- Common mistakes when implementing this flow
