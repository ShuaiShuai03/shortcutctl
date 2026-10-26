# Development and verification

## Layout

- `Sources/ShortcutCore/`: typed values, deterministic serialization, native templates, validation, safe files, process execution, runtime assertions, signed-container decoding, action discovery, typed diff, and watch state.
- `Sources/shortcutctl/`: Argument Parser commands, human presentation, JSON envelopes, and exit codes.
- `Tests/ShortcutCoreTests/`: Swift Testing unit/integration cases with synthetic process executables and temporary files.
- `Tests/CLI/`: Python standard-library tests that execute the built CLI.
- `examples/`: synthetic JSON projects; regenerate intentionally when template behavior changes.

Swift 6 language mode is required. Argument Parser is pinned in `Package.swift` and `Package.resolved`. No third-party Python packages are needed for tests or coverage.

## Commands

```sh
swift build
swift test
python3 -m unittest discover -s Tests/CLI -v
swift build -c release
```

The CLI tests default to `.build/debug/shortcutctl`. Override with `SHORTCUTCTL_BIN=/absolute/path/to/shortcutctl` for an installed or release binary.

For combined coverage and the 80% first-party line-coverage gate:

```sh
python3 scripts/check-coverage.py
```

The script instruments Swift tests and the CLI, executes the Python contract suite, merges profiles with Apple's LLVM tools, and excludes dependencies/test code. It writes `coverage/report.txt` and `coverage/summary.json`. Native GUI acceptance is **not** included in this automated coverage number. Temporary profiles are removed after reporting.

Use Apple's formatter before committing:

```sh
xcrun swift-format format --in-place --recursive Sources Tests/ShortcutCoreTests Package.swift
xcrun swift-format lint --strict --recursive Sources Tests/ShortcutCoreTests Package.swift
```

The repository's `.swift-format` sets four-space indentation and a 120-column target. Formatter versions can differ between Xcode releases; CI gates executable behavior and coverage rather than a toolchain-specific formatting snapshot.

The [CI workflow](https://github.com/ShuaiShuai03/shortcutctl/blob/main/.github/workflows/ci.yml) verifies Apple Silicon and Intel macOS runners, unit/CLI tests, coverage, release compilation, installation into a temporary prefix, and a create/lint/build/decompile smoke flow. It uses no secrets and performs no signing, import, or successful installed-shortcut execution. The one native failure test uses a deliberately nonexistent unique name and accepts native failure or bounded timeout.

## What the automated tests establish

- Unknown actions/parameters and plist types survive conversion; typed-value collisions and invalid fields fail explicitly.
- XML refuses fractional-date loss; canonical binary passes Foundation decoding and wide-object-reference checks.
- Independent CLI processes produce identical unsigned outputs for repeated inputs.
- Invalid controls, references, UUIDs, token ranges, argument shapes, and file operations report errors.
- No-overwrite, symlink refusal, dry-run, process timeouts/output bounds, and direct argument handling work.
- Runtime assertions compare exact bytes and stop on native errors; mocked signing must produce a nonempty file.
- Every subcommand exposes help/JSON; operational failures and report-producing failures use the documented streams.

Mocked process tests establish the runner's contract, not Apple's runtime compatibility. Never count them as device acceptance.

## Version 0.2.0 regression coverage

The suite creates AEA archives using ephemeral P-256 keys. The certificate-chain case uses system `/usr/bin/openssl` only to generate a temporary self-signed test certificate; this is a test dependency, not a CLI runtime dependency. Private test keys and signed bytes are never committed. Both Apple-style empty-root archives and single-workflow archives are tested.

Tests cover complete typed round trips, sliced `Data`, truncated/tampered/authentication-invalid archives, encrypted profiles, invalid paths, duplicate/link entries, and decompression/block-size bounds. A rejection test constructs its synthetic archive before asserting decoder failure so fixture construction errors cannot count as successful validation. A valid self-signed test certificate establishes decoding only; it does not establish certificate trust.

Diff regressions cover typed values, signed zero, Unicode key representation, escaped paths, tests, ordered arrays, JSON output, human before/after values, and the optional exit-8 gate. Watch executable tests cover initial output safety, dry runs, invalid-input recovery, atomic saves, strict validation, directory-alias retargeting, and refusal to replace external output edits. Native list/view runner tests assert literal argument arrays, native failures, and option validation; CLI view testing uses dry-run rather than opening personal shortcuts.

CI packages both architecture-specific release builds with documentation, licenses, and checksums after the installed executable contract suite passes. Packaging does not imply notarization or native signing/import acceptance.

## Native acceptance procedure

Use a synthetic, uniquely named project for each template. Do not replace a personal shortcut.

```sh
mkdir -p local-artifacts/acceptance
shortcutctl create local-artifacts/acceptance/text.json --name 'shortcutctl Acceptance Text' --template text
shortcutctl build local-artifacts/acceptance/text.json --output 'local-artifacts/acceptance/shortcutctl Acceptance Text.shortcut' --sign anyone
```

Import the signed file through Shortcuts.app, review the visible action graph, confirm the installed name/identifier with `shortcuts list --show-identifiers`, then execute:

```sh
shortcutctl test local-artifacts/acceptance/text.json --shortcut 'Installed identifier' --json
```

Repeat with `dictionary`, `if`, `repeat`, and `http`. For HTTP, run the synthetic localhost fixture server in a separate terminal:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory examples/http-server
```

The HTTP template requests only `http://127.0.0.1:8765/fixture.json`. Stop that server when finished. Review any permission prompt rather than changing global security settings. Keep JSON test reports and inspected screenshots in ignored `local-artifacts/`; signed containers may contain account-associated metadata and are not committed.

A native acceptance report must identify the OS/toolchain, fixture version, signing/import checks, actual assertions, and limitations. The original local run is recorded in [acceptance.md](acceptance.md); new signed decoding/discovery/diff/watch evidence is in [acceptance-0.2.0.md](acceptance-0.2.0.md). Physical-iPhone and Health results require separate device evidence.
