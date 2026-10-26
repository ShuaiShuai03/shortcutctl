# shortcutctl development

Swift 6 macOS CLI. `Sources/ShortcutCore` owns workflow serialization, validation, safe file IO, and process execution. `Sources/shortcutctl` owns Argument Parser commands and output presentation. Keep platform effects outside pure workflow logic.

## Verification

- `swift build`
- `python3 scripts/check-coverage.py` (Swift unit tests, executable CLI tests, 80% first-party line coverage)
- `swift build -c release`
- `xcrun swift-format lint --strict --recursive Sources Tests/ShortcutCoreTests Package.swift`
- CLI and native acceptance instructions: `docs/testing.md`; observed results: `docs/acceptance.md`.

Write focused regression tests for reproducible failures. Use synthetic workflows. Never run, replace, or delete a personal shortcut as a test. Import requires the Shortcuts interface and may require user confirmation. Keep local native-test artifacts in ignored `local-artifacts/`.

## Contracts

Preserve unknown workflow actions, parameters, and property-list types. Reject unrepresentable data explicitly. Do not conflate valid JSON, valid workflow structure, successful signing, successful import, and successful execution.

Do not access the private Shortcuts database. The native serialized workflow format is experimental; Apple CLI signing/running are supported interfaces. Signed-container decoding, device automation management, and Health execution must not be claimed without evidence. See `docs/architecture.md`.

Use direct process argument arrays, bounded waits, stable JSON/error contracts, and no-overwrite output defaults. Keep English source comments and documentation; Chinese is an explicitly requested diagnostic locale. Do not commit credentials, private shortcut content, or machine-specific paths.
