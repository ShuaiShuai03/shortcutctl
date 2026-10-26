# Architecture and feasibility

## Scope

Version 0.2.0 extends the original `create`, `build`, `inspect`, `decompile`, `lint`, `run`, and `test` commands with signed-container decoding, `discover`, `list`, `view`, typed structural `diff`, and foreground `watch`. Automation planning, a complete installed-action catalog, and Health execution remain outside this release; discovery is not a device-management API.

## Decisions

- Swift 6 and Swift Package Manager produce one macOS executable. Apple Swift Argument Parser handles command parsing and help.
- A reusable `ShortcutCore` library separates the workflow codec/compiler/decompiler, registry, validator, file handling, and native process runner from CLI presentation.
- Schema-versioned JSON contains native workflow dictionaries, including unknown actions and parameters. This avoids a second lossy action language. Explicit tagged values preserve property-list data, dates, and real numbers; unsupported values fail with a diagnostic.
- Compilation means deterministic property-list generation, not proof that Apple will execute an action. Signing and execution are separate, explicit operations.
- `/usr/bin/shortcuts` is the execution/signing boundary. Arguments are passed directly without a shell. Timeouts bound waits; terminating the CLI does not roll back an action or guarantee cancellation inside Shortcuts.
- No reads or writes to the private Shortcuts database. No runtime dependency on shortcuts-toolkit or clean-shortcuts. Third-party code is not copied.
- Files are never overwritten by default. Explicit replacement and dry-run behavior belong on output-producing commands. JSON responses have a versioned envelope and stable error codes. Human diagnostics support English and Chinese.
- Runtime tests target an explicitly selected installed shortcut and assert real output. Static tests never claim runtime acceptance.

## Observed platform

Initial investigation on 2026-10-26: macOS 27.2, Apple Silicon, Xcode 27.0, Apple Swift 6.4, Shortcuts 10.0. These observations are not a cross-version compatibility guarantee.

The installed `/usr/bin/shortcuts --help` and `man shortcuts` expose:

| Capability | Supported interface | Boundary |
| --- | --- | --- |
| List shortcuts/folders | `shortcuts list` | Text output; no native JSON contract |
| Run installed shortcut | `shortcuts run` | May wait for app permissions or UI; cannot execute arbitrary unsigned project files |
| Open editor | `shortcuts view` | Opens UI; not an editing API |
| Sign an existing file | `shortcuts sign` | `anyone` or `people-who-know-me`; no `--unsign` option |
| Create/edit action graphs | Shortcuts UI | No corresponding CLI subcommand |
| Import/export | Shortcuts UI | No import/export CLI subcommand |

The installed `Shortcuts.sdef` exposes read-only shortcut names, identifiers, input support and action counts; shortcut folder assignment and folder names are writable. It does not expose action parameter editing. Dictionary declarations alone do not prove runtime authorization or behavior.

Read-only smoke checks of `shortcuts list --show-identifiers` and `shortcuts list --folders` exited 0 with no entries in this execution context. That does not prove the user's other devices or sessions have no shortcuts.

## Supported APIs versus experimental formats

Apple documents listing, running, viewing and signing. Apple does not promise stability of the serialized `WFWorkflow*` action graph format used by third-party compilers. The compiler's native format compatibility is therefore experimental and fixture-tested, not an Apple public editing API.

Signed archives are distinct from unsigned XML/binary property lists. Recognizing a signed container must never be represented as signature validation, and an unreadable container must never silently produce an empty workflow. Decoding supports unsigned property lists, project JSON, and signed, unencrypted AEA1 profile 0 containers. The signed decoder uses public AppleArchive streams, CryptoKit P-256 keys, and Security certificate parsing. It authenticates the entire archive against an embedded key before parsing its single native workflow entry. It does not validate certificate-chain trust, contact identity, or Apple approval. Encrypted profiles are explicitly rejected.

The decoder accepts exactly one regular `Shortcut.wflow`, optionally preceded by Apple's empty root-directory entry. Archive paths are never extracted. Input and workflow payloads are limited to 16 MiB; the decoded Apple Archive stream and its compression block are limited to 17 MiB, allowing bounded header overhead. Temporary byte streams are closed automatically. Tests generate ephemeral signing keys and synthetic archives; no account-associated signed container is committed.

Discovery separates the small compatibility registry, parameter keys observed in a chosen workflow, and App Intents metadata read from an explicit file/app bundle. Unknown metadata is retained as raw JSON. None of these sources establishes action availability, complete parameter schemas, or permission to run an action. The metadata format is experimental. Discovery does not extend the validator's compatibility registry implicitly.

Diff compares typed values rather than serialized bytes. Dictionary keys use UTF-8 identity, arrays retain their order and compare by index, and UUIDs/unknown metadata remain visible. It does not infer behavioral equivalence or align moved actions. Project name/tests can be excluded explicitly. Watch polls source bytes, debounces changes, validates each new snapshot, and optionally publishes unsigned compilation atomically. It fixes the output parent at startup, rechecks source/output separation, and refuses externally changed output unless replacement was explicitly authorized. It never invokes signing, import, or workflow execution.

App Intents lets an application expose its own actions to system surfaces. It is not a general API for rewriting another application's shortcut graphs. iPhone automation triggers and Health access remain device-controlled; this CLI does not bypass consent or promise remote deployment.

## Primary sources

- Installed `/usr/share/man/man1/shortcuts.1` and command help.
- Installed `/System/Applications/Shortcuts.app/Contents/Resources/Shortcuts.sdef`.
- [Apple command-line guide](https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac).
- [Apple sharing/export guide](https://support.apple.com/guide/shortcuts-mac/apdf01f8c054/mac).
- [Apple import guide](https://support.apple.com/guide/shortcuts-mac/apd02bffbaac/mac).
- [App Intents](https://developer.apple.com/documentation/appintents).
- [Device automations](https://support.apple.com/guide/shortcuts/apd690170742/ios).
