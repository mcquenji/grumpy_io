# Grumpy IO

`grumpy_io` provides cross-platform IO services and typed datasource adapters for Grumpy apps.

It covers:
- raw networking
- raw filesystem
- persistent local storage
- typed datasource wrappers in each owning module
- optional Grumpy cache/persistence compatibility adapters

## Design Goals

- Keep public IO contracts backend-agnostic.
- Return typed `IoResult<T>` instead of leaking backend exceptions.
- Keep typed datasources close to their owning module.
- Use compile-time platform selection for platform-specific services.

## Module Layout

### Networking Module

Exports:
- `NetworkService`
- `FileTransferService`
- `TypedNetworkDatasource`

Default implementations:
- `DioNetworkService`
- `DefaultFileTransferService`
- `DefaultTypedNetworkDatasource`

### File System Module

Exports:
- `FileSystemService`
- `TypedFileSystemDatasource`
- `IoPath`, `FsMetadata`, `FsEntityType`

Default implementations:
- `DefaultFileSystemService` (platform-selected)
- `DefaultTypedFileSystemDatasource`

### Local Storage Module

Exports:
- `LocalStorageService`
- `TypedLocalStorageDatasource`
- `LocalStorageKey`, `LocalStorageValue`

Default implementations:
- `DefaultLocalStorageService` (platform-selected)
- `DefaultTypedLocalStorageDatasource`

Persistence behavior:
- Native (`io`): persisted via `FileSystemService` in a JSON file.
- Web: persisted in browser `localStorage` with cookie fallback.

## Typed Datasources

Typed datasources are intentionally colocated with their modules:
- networking typed datasource lives in networking module
- filesystem typed datasource lives in filesystem module
- local-storage typed datasource lives in local-storage module

Shared typed datasource concerns are in `shared_module`.

## Platform-Specific Service Convention

For services with platform-specific implementations:
- platform files live under `<module>/infra/services/<service>/...`
- an entrypoint file performs conditional export
- concrete platform implementations expose the same symbols

Example pattern:

```dart
export 'service_stub.dart'
    if (dart.library.io) 'service_io.dart'
    if (dart.library.js_interop) 'service_web.dart';
```

## Error Model

All public IO surfaces use:
- `IoResult<T>`
- `IoOk<T>`
- `IoErr<T>`
- `IoFailure` with `IoFailureCode`

This keeps consumers on one stable error contract across backends/platforms.

## Grumpy Compatibility Layer

`grumpy_compat` provides optional adapters for:
- memory cache layer
- persistent cache layer
- cache pipeline
- repo snapshot persistence
- root module mixin wiring

## Public Exports

Package root exports:
- `core`
- `networking_module`
- `file_system_module`
- `local_storage_module`
- `grumpy_compat`
- `grumpy_io_module`

## Status

Current focus is V1 core IO and persistence surfaces. Process-management and system-information features remain out of scope for V1.


### Safe file replacement

Use `FileSystemService().replaceBytes(path, bytes)` when updating a document that must survive a failed write. The native implementation flushes a temporary file on the same filesystem, then renames it over the destination without deleting the previous file first. Temporary resources are cleaned up after success or failure. Unsupported backends return `IoErr.unsupported` without touching the destination; custom backends can override the same service contract.
