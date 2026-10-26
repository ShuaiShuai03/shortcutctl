# Acceptance record — 2026-10-26

Version: `shortcutctl 0.1.0`. Platform: Apple Silicon, macOS 27.2 (26B118), Xcode 27.0 (27A5252f), Swift 6.4, Shortcuts 10.0. These are observed local versions, not a claim that every macOS release behaves identically.

## Automated and installed-binary checks

- `python3 scripts/check-coverage.py`: **29 Swift test functions passed**, including two parameterized tests with 22 and 8 cases; **9 executable CLI tests passed**.
- Combined first-party coverage: **1,380 / 1,498 lines (92.12%)**, **693 / 809 regions (85.66%)**. Dependencies and test code are excluded. This number does not include manual GUI acceptance.
- `xcrun swift-format lint --strict --recursive Sources Tests/ShortcutCoreTests Package.swift`: passed.
- Ruff checks for the Python CLI suite and coverage helper: passed.
- `swift build -c release`: passed.
- The release executable was installed outside the repository in a user binary directory. `--version` and all nine CLI tests passed against that installed copy. `otool -L` showed system frameworks/libraries only, with no checkout/build-directory runtime dependency.
- All five committed example projects passed strict linting.

CI separately runs unit/CLI coverage and release/installation checks on Apple Silicon and Intel macOS runners. Its current result is available in the repository's [Actions page](https://github.com/ShuaiShuai03/shortcutctl/actions/workflows/ci.yml); hosted CI does not perform GUI import or successful native workflow execution.

## Real Shortcuts execution

Each final fixture was compiled, signed with `/usr/bin/shortcuts sign --mode anyone`, imported through Shortcuts.app, and executed by the installed release binary. Successful reports and fixture hashes are in [acceptance-results.json](acceptance-results.json).

| Template | Assertions | Observed result |
| --- | --- | --- |
| Text | ASCII echo and `Hello 世界 🧪` | Both exact UTF-8 outputs passed |
| Dictionary | Dictionary → named variable → key lookup | `Dictionary passed` |
| If | Input `yes` and input `no` | `matched` and `not matched` |
| Repeat | Repeat Text three times, then Combine Text | `item\nitem\nitem` |
| HTTP | GET synthetic localhost JSON → dictionary → key lookup | `HTTP passed` |

The HTTP server bound only to `127.0.0.1:8765` and served `{"message":"HTTP passed"}`. No external account or private data was used. Runtime tests selected explicit synthetic installed names; identifiers were inspected through Apple's list command. Screenshots of the imported library/editor and raw local logs were inspected and retained outside version control. Signed files are not published because their containers can include account-associated metadata.

The test library contains synthetic acceptance shortcuts, including earlier diagnostic versions. None of the user's pre-existing shortcuts was modified or deleted.

## Corrections established through native acceptance

1. Text and Stop and Output accepted incorrectly shaped standalone attachments during import but displayed empty parameters. Both require `WFTextTokenString` in these fields. HTTP URL uses the same text-envelope convention.
2. On this system, Apple's `public.utf8-plain-text` conversion returned empty output for a valid Text result. `public.plain-text` returned the expected bytes and is now the default. The option remains configurable.
3. If requires a `Type: Variable` operand wrapper. Generic shortcut input still lacked a usable comparison type; an initial Text action established it, and both branches then passed.
4. Repeat produced three items in the editor, but the native CLI did not serialize that list as the expected text. The template now explicitly combines the result list with newlines.
5. Foundation XML serialization loses fractional dates and the sign of negative zero. Compilation now detects those differences and refuses the lossy output; binary round trips preserve both.

Regression tests cover the corresponding encoding, output-type, and loss-detection contracts. Successful signing/import was not treated as execution success during diagnosis.

## Unverified or unsupported

- macOS 13 is the package deployment floor; full native template execution was verified only on the local platform above. CI build/test results are a separate compatibility check.
- No physical iPhone, iPad, Health read/write, personal automation trigger, App Intents companion app, or cross-device sync acceptance.
- No complete installed-action catalog or complete action-parameter/type checker.
- No signed AEA1 decryption, signature verification, Swift-source decompilation, automatic GUI import, or private-database editing.
- Timeouts bound the command's wait; they cannot guarantee cancellation of an already-running action or reverse side effects.
