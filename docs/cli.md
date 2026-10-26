# CLI reference

Run `shortcutctl <command> --help` for exact options. `--json` and `--language en|zh` follow the subcommand. Help/version are plain text, including when `--json` is present. No config file or environment override changes command behavior.

## File commands

```sh
shortcutctl create project.json --name 'My Shortcut' --template dictionary --json
shortcutctl build project.json -o unsigned.shortcut --format binary --json
shortcutctl build project.json -o 'My Shortcut.shortcut' --sign anyone --timeout 60 --json
shortcutctl inspect project.json --json
shortcutctl decompile unsigned.shortcut -o restored.json --json
shortcutctl decompile unsigned.shortcut
shortcutctl lint project.json --strict --json
```

`create` accepts templates `text`, `dictionary`, `if`, `repeat`, and `http`. Without `--name`, the project name comes from its filename. The parent directory must already exist.

`build` accepts project JSON or unsigned XML/binary plist. `--format` defaults to `xml`; binary is needed for fractional dates. `--sign` defaults to `none`, with `anyone` and `people-who-know-me` available explicitly. `--strict` rejects warnings as well as errors. The reported SHA-256 hashes the bytes actually produced; signed output is not deterministic. In a dry run, bytes/hash describe the **unsigned** compilation and `signed` remains false even when signing is planned.

`inspect` returns the complete project, action count, diagnostics, and `structurallyValid`. Exit 0 means the inspection completed, not that the graph is valid.

`decompile` emits JSON only. Without `--output`, human mode writes the project itself, suitable for redirection; JSON mode wraps it in `data`. With `--output`, JSON mode returns file metadata. Project tests/name live outside the native workflow and cannot be recovered from a compiled plist unless present in the original project.

`lint` returns diagnostics with `severity`, `code`, `path`, `message`, and `messageZH`. Unknown actions are warnings; `--strict` turns warnings into a failing command. Validation is structural plus selected known parameter checks, not a complete action schema or runtime interpreter.

`create`, `build`, and `decompile` accept `--force` and `--dry-run`. Destination symlinks, directories, and special files are refused even with `--force`. Build/decompile never overwrite their own input. File publication is atomic, with no-overwrite as the default and mode 0600 for new outputs.

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

Inputs, compiled files, signed files, and combined captured native stdout/stderr are limited to 16 MiB. Inputs must be regular files and cannot be symlinks. Nesting is limited to 128 levels. Output conversion of multiple items depends on Apple's CLI: the repeat template explicitly combines its result list into text.

## JSON and exit status

Successful operations emit one JSON envelope to stdout:

```json
{"schemaVersion":1,"command":"lint","ok":true,"data":{"valid":true,"strict":false,"diagnostics":[]}}
```

Operational/argument errors emit one envelope to stderr and leave stdout empty:

```json
{"schemaVersion":1,"command":"decompile","ok":false,"error":{"code":"signed_container_unsupported","message":"Signed AEA1 archives cannot be decompiled by this version.","messageZH":"此版本无法反编译已签名的 AEA1 文件。","exitCode":4}}
```

Optional fields, including `hint`, are omitted when absent. JSON field ordering and whitespace are presentation details. Parse `schemaVersion`, `ok`, stable diagnostic `code`, and process status; do not parse localized text.

**Two report-producing failures use stdout:** lint rejection (exit 3) and failed runtime assertions/native test cases (exit 7) retain their full report in `data` with `ok: false`. These do not emit a second error envelope. Inspection diagnostics do not change its successful inspection status.

| Exit | Meaning |
| --- | --- |
| 0 | Successful operation or dry-run plan |
| 1 | Unexpected operation failure |
| 2 | Invalid arguments, template, or runtime options |
| 3 | Invalid project/value/graph, strict-lint failure, or lossy serialization |
| 4 | Unsupported file/container or unavailable native executable |
| 5 | File/output safety or size-limit failure |
| 6 | Native signing/running failure or missing signed artifact |
| 7 | Runtime test report contains failed cases |
| 124 | Native invocation timed out; inside `test`, reported as a case error with command exit 7 |

Build errors suggest `lint --json` for all structural diagnostics. `--language zh` affects human diagnostics; JSON always contains both English and Chinese diagnostic strings. Human success summaries and help may remain English.
