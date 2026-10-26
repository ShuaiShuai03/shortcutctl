# Changelog

## 0.2.0 — 2026-10-26

- Decode signed, unencrypted AEA1 shortcuts through Apple's public AppleArchive, CryptoKit, and Security frameworks. Preserve the complete native workflow and unknown values in project JSON. Accept certificate-chain and embedded-public-key authentication metadata; refuse encrypted profiles, corrupt signatures, oversized content, and unexpected archive entries.
- Add `discover` for searchable compatibility actions, observed workflow parameter keys, and App Intents metadata from an explicit file or app bundle. Preserve raw action metadata and identify each result's provenance.
- Add `list` for installed shortcuts/identifiers and folders, and `view` for explicitly opening an installed shortcut in Apple's editor.
- Add `diff` for typed structural comparison across JSON, plist, and signed inputs, with JSON Pointer paths, human before/after values, workflow-only comparison, and an optional exit-code gate.
- Add foreground `watch` for debounced validation and unsigned rebuilding, atomic-save detection, last-successful-output preservation, NDJSON events, dry-run/once/duration controls, and protection against external output edits and retargeted directory aliases.
- Package verified Apple Silicon and Intel executables with documentation, licenses, and SHA-256 checksums in CI.

Archive integrity against an embedded key does not establish certificate trust, shortcut safety, importability, or execution. Discovery is partial evidence rather than a complete installed-action API. Native workflow and App Intents metadata formats remain experimental.

## 0.1.0 — 2026-10-26

Initial standalone CLI: create, compile, inspect, unsigned decompilation, structural lint, explicit installed-shortcut execution, and runtime assertions. See the [original acceptance record](docs/acceptance.md).
