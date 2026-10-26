# CLI reference

Run `shortcutctl <command> --help` for exact options. `--json` and `--language en|zh` follow the subcommand. Help/version are plain text, including when `--json` is present. No config file or environment override changes command behavior. `watch --json` is an NDJSON stream: one compact envelope per event.

## File commands

```sh
shortcutctl create project.json --name 'My Shortcut' --template dictionary --json
shortcutctl build project.json -o unsigned.shortcut --format binary --json
shortcutctl build project.json -o 'My Shortcut.shortcut' --sign anyone --timeout 60 --json
shortcutctl inspect project.json --json
shortcutctl decompile signed.shortcut -o restored.json --json
shortcutctl decompile unsigned.shortcut
shortcutctl lint project.json --strict --json
```

`create` accepts templates `text`, `dictionary`, `if`, `repeat`, and `http`. Without `--name`, the project name comes from its filename. The parent directory must already exist.

File commands accept project JSON, XML/binary workflow plists, and signed, unencrypted AEA1 profile 0 containers. Signed decoding is local, authenticates the whole archive against its embedded key, and never executes the workflow. Certificate-chain trust, contact identity, shortcut safety, importability, and execution are not established. Encrypted profiles and unexpected archive layouts fail explicitly.

`build` accepts any of these inputs. `--format` defaults to `xml`; binary is needed for fractional dates. `--sign` defaults to `none`, with `anyone` and `people-who-know-me` available explicitly. `--strict` rejects warnings as well as errors. The reported SHA-256 hashes the bytes actually produced; signed output is not deterministic. In a dry run, bytes/hash describe the **unsigned** compilation and `signed` remains false even when signing is planned.

`inspect` returns the complete project, action count, diagnostics, and `structurallyValid`. Exit 0 means the inspection completed, not that the graph is valid.

`decompile` emits JSON only. Without `--output`, human mode writes the project itself, suitable for redirection; JSON mode wraps it in `data`. With `--output`, JSON mode returns file metadata. Project tests/name live outside the native workflow and cannot be recovered from a compiled plist unless present in the original project.

`lint` returns diagnostics with `severity`, `code`, `path`, `message`, and `messageZH`. Unknown actions are warnings; `--strict` turns warnings into a failing command. Validation is structural plus selected known parameter checks, not a complete action schema or runtime interpreter.

`create`, `build`, `decompile`, and `watch` accept `--force` and `--dry-run`. Destination symlinks, directories, and special files are refused even with `--force`. Build/decompile never overwrite their own input. File publication is atomic, with no-overwrite as the default and mode 0600 for new outputs.

## Discovery and editor commands

```sh
shortcutctl discover --query 'Dictionary' --json
shortcutctl discover --identifier is.workflow.actions.gettext --json
shortcutctl discover --workflow exported.shortcut --json
shortcutctl discover --metadata extract.actionsdata --json
shortcutctl discover --app /System/Applications/Shortcuts.app --json
shortcutctl list --json
shortcutctl list --folder 'Work' --json
shortcutctl list --folders --json
shortcutctl view 'Installed identifier' --dry-run --json
shortcutctl view 'Installed identifier' --json
```

`discover` defaults to the small compatibility catalog, with human titles and parameter keys observed in bundled templates. `--workflow` enumerates native action identifiers and the union of their observed parameter keys. `--metadata` reads an explicit App Intents `extract.actionsdata` JSON file; `--app` reads `Contents/Resources/Metadata.appintents/extract.actionsdata` within one selected bundle. Only one source selector may be supplied. It does not scan other apps, extensions, or the private Shortcuts database implicitly. Bundles without that metadata return a file error.

Results contain `identifier`, `title`, `kind`, `source`, `parameters`, and optional `metadataJSON`. Kinds are `compatibility`, `observed`, and `app-intent`. `metadataJSON` retains the complete source action object, including unknown fields, nulls, availability annotations, types, and discoverability flags. Titles from metadata are resource keys, not a guaranteed localized display string. App Intent identifiers are not serialized native workflow action identifiers; use actual exported workflows to establish the invocation shape. Parameter lists are evidence, not complete schemas. The result's `complete: false` means no source claims to be the complete installed-action catalog. Discovery does not imply availability, validator coverage, or permissions.

`--query` filters identifiers/titles by case-insensitive substring; `--identifier` filters by exact identifier. Filters combine. No matches is a successful empty result.

`list` calls Apple's CLI with bounded waits. Normal results have `shortcuts: [{name, identifier}]`; `--folders` returns `folders: [name]`. `--folder` accepts a name/identifier or `none` for unfiled shortcuts and cannot combine with `--folders`. Use a folder identifier for names beginning with a hyphen. Native names/identifiers are preserved. Apple's human `name (UUID)` format is parsed conservatively; unfamiliar output fails with `unrecognized_listing` rather than inventing identifiers. Folder names are line-delimited; native CLI limitations apply to names containing newlines.

`view` requests Apple's editor for an explicit installed name/identifier. Apple's `view` command accepts names only, so the wrapper resolves identifiers through `list` and requires a unique name; duplicates fail with `ambiguous_shortcut`. A UUID-shaped name with no matching installed identifier is passed through as a name. For names beginning with a hyphen, place options before the argument separator, for example `shortcutctl view --json -- -Name`. Each native invocation has the specified timeout. `--dry-run` does not open the app. A successful request is not evidence that the user reviewed or changed the workflow. Both commands accept `--timeout` with the existing per-invocation bounds. They do not import/export or edit action parameters.

## Typed structural diff

```sh
shortcutctl diff old.json new.json --json
shortcutctl diff source.json signed.shortcut --workflow-only --json
shortcutctl diff old.shortcut new.shortcut --check --json
```

Diff compares decoded typed values rather than formatting or binary bytes. By default, names, native workflow metadata/actions, and project tests are included; missing tests are equivalent to an empty tests list. `--workflow-only` excludes project-only fields. Arrays compare by index, so insertions or moves can produce several differences; no action alignment or behavioral equivalence is inferred. UUIDs, Unicode representations, signed zero, dates, data, and unknown values are preserved. Dictionary order and JSON whitespace do not create changes.

The result has `equal`, `workflowOnly`, and ordered `changes`. Each change has `kind: added|removed|changed`, an RFC 6901 JSON Pointer `path`, and applicable typed `before`/`after` values. Human output includes minus/plus values. This report is not an executable JSON Patch. `--check` returns 8 when differences exist, keeping the report on stdout with `ok: false`; without it, a completed comparison returns 0 even when different. Apple signing can rewrite workflow metadata, so a source-versus-signed diff may show genuine native changes.

## Foreground watch

```sh
shortcutctl watch project.json --json
shortcutctl watch project.json -o preview.shortcut --format binary --json
shortcutctl watch project.json -o preview.shortcut --dry-run --json
shortcutctl watch project.json --once --strict --json
shortcutctl watch project.json --interval 0.1 --debounce 0.3 --duration 30 --json
```

Watch validates immediately, then polls source bytes. Stable changed content triggers validation and optional unsigned compilation. It detects atomic saves and changes with unchanged modification times. `--interval` defaults to 0.25 seconds (0.01–60); `--debounce` defaults to 0.2 seconds (0–60). The initial snapshot is processed immediately. Repeated identical content or identical consecutive read errors do not produce repeated events. Invalid edits, temporarily missing files, and read errors are reported; watching resumes when the input recovers. The last successful output is preserved.

Output defaults to binary; `--format xml` selects XML and retains the normal loss checks. `--strict` rejects warnings too. Existing output requires `--force`. Without it, subsequent writes replace only this watch process's unchanged last output; external edits produce `output_changed`. The destination's parent is resolved at startup, and source/output separation and file safety are checked for each publication. Output events report the fixed destination path. Watch never signs, imports, or executes shortcuts.

`--dry-run` validates the initial input/destination and reports a `planned` event without writing or watching. `--once` validates/builds once and exits with the result. `--duration` bounds foreground watching to 0–86400 seconds; 0 is the default and watches until interrupted. Stop with Ctrl-C (normal signal exit). Duration mode exits 0 when the monitoring period completes even if some edits failed; inspect events to assess success. This is a foreground tool, with no daemon or installation step.

Each JSON event has the normal envelope with command `watch` and data containing `sequence`, `dryRun`, `event: planned|validated|built|failed`, `source`, optional `output`/`bytes`, diagnostics, and optional bilingual `error`. Events are one compact JSON object per line and flush immediately. Failed events have `ok: false` and remain on stdout, including `--once` failures. Argument/destination preflight errors use stderr. Successful snapshots after a failure have `ok: true`. Human mode emits one status line per event.

## Runtime commands

```sh
shortcutctl run 'Installed name or identifier' -i input.txt --json
shortcutctl run 'Installed identifier' -o result.txt --output-type public.plain-text --json
shortcutctl run 'Installed identifier' --dry-run --json
shortcutctl test project.json --shortcut 'Installed identifier' --json
shortcutctl test project.json --shortcut 'Installed identifier' --case echo --json
shortcutctl test project.json --shortcut 'Installed identifier' --dry-run --json
```

`run` never imports or executes project files. It calls `/usr/bin/shortcuts run` using direct argument arrays. Input is an explicit regular file; stdin is not read implicitly. Default output type is `public.plain-text`. Native output is captured as bytes; JSON embeds UTF-8 when valid and base64 otherwise. `--output` writes those raw bytes and returns their path. Human output adds a terminal newline; use `--output` for byte-exact capture.

`test` requires an explicit installed shortcut and nonempty selected tests. Each case has optional UTF-8 input and exact expected UTF-8 output. A mismatch continues to the next case; a native command error halts the remaining cases. Its report includes planned count, executed cases, expected/actual output, errors, and `halted`. A dry run has `executed: false` and `passed: false`; a successful plan is not a passed runtime test.

`run` and `build` default to a 60-second timeout per native invocation; `test` applies the same timeout separately to each case. Valid values are greater than 0 and at most 86400 seconds. Native failure messages retain Apple's localized stderr. No retry is performed. A timeout does not undo side effects or guarantee cancellation inside Shortcuts.app.

Inputs, metadata files, compiled files, signed files, and combined captured native stdout/stderr are limited to 16 MiB. Decoded Apple Archive bytes and compression blocks have a separate 17 MiB cap; the native workflow payload remains limited to 16 MiB. Inputs must be regular files and cannot be symlinks. Nesting is limited to 128 levels. Output conversion of multiple items depends on Apple's CLI: the repeat template explicitly combines its result list into text.

## JSON and exit status

Successful operations emit one JSON envelope to stdout:

```json
{"schemaVersion":1,"command":"lint","ok":true,"data":{"valid":true,"strict":false,"diagnostics":[]}}
```

Operational/argument errors emit one envelope to stderr and leave stdout empty:

```json
{"schemaVersion":1,"command":"decompile","ok":false,"error":{"code":"encrypted_container_unsupported","message":"Only signed, unencrypted AEA1 profile 0 is supported.","messageZH":"仅支持已签名且未加密的 AEA1 profile 0。","exitCode":4}}
```

Optional fields, including `hint`, are omitted when absent. JSON field ordering and whitespace are presentation details. Parse `schemaVersion`, `ok`, stable diagnostic `code`, and process status; do not parse localized text.

**Report-producing failures use stdout:** lint rejection (exit 3), failed runtime assertions/native test cases (exit 7), `diff --check` differences (exit 8), and failed watch events retain their report in `data` with `ok: false`. These do not emit a second error envelope. `watch --once` and `watch --dry-run` fail with the event's error exit code; duration watching continues after failed edits. Inspection diagnostics do not change its successful inspection status.

| Exit | Meaning |
| --- | --- |
| 0 | Successful operation or dry-run plan |
| 1 | Unexpected operation failure |
| 2 | Invalid arguments, template, or runtime options |
| 3 | Invalid project/value/graph, strict-lint failure, or lossy serialization |
| 4 | Unsupported file/container or unavailable native executable |
| 5 | File/output safety or size-limit failure |
| 6 | Native command/list parsing failure or missing signed artifact |
| 7 | Runtime test report contains failed cases |
| 8 | `diff --check` found differences |
| 124 | Native invocation timed out; inside `test`, reported as a case error with command exit 7 |

Build errors suggest `lint --json` for all structural diagnostics. `--language zh` affects human diagnostics; JSON always contains both English and Chinese diagnostic strings. Human success summaries and help may remain English.
