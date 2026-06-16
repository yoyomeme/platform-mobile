# [Service Name]

> One-line summary of what this service does.

## Where in code
- `path/to/ServiceName.{{LANGUAGE}}` -- brief description of the file

## [Class/Actor/Object]: `ServiceName`

## Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| | | | |

## Methods

### `methodName(param1:param2:)`

Brief description of what this method does.

```{{LANGUAGE}}
func methodName(
    param1: Type1,
    param2: Type2
) async throws -> ReturnType
```

- **HTTP**: `METHOD /path` (if applicable)
- **Request**: `RequestType`
- **Success**: condition for success
- **When to call**: when this method should be invoked

<!-- Repeat for each public method -->

## Error codes

| Code | Step | Trigger |
|------|------|---------|
| | | |

## Usage example

```{{LANGUAGE}}
let result = try await {{SINGLETON_ACCESS}}.serviceName.methodName(
    param1: value1,
    param2: value2
)
```

## Cross-references

- [related-flow](../flows/related-flow.md)
- [related-type](../types/related-type.md)
- [related-service](related-service.md)

## Gotchas

- Non-obvious behavior or common pitfalls
- Edge cases that could trip up developers
