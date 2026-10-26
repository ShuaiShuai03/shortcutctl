# shortcutctl

A native macOS CLI for developing Apple Shortcuts from versioned JSON. Create a workflow, inspect its complete action graph, lint it, compile and sign it, then test the installed shortcut against real output assertions.

`shortcutctl` uses Swift 6, Swift Package Manager, and Apple's Argument Parser. It ships as one executable and delegates signing and execution to `/usr/bin/shortcuts`. It never accesses the private Shortcuts database.

**Format compatibility is experimental.** Apple's serialized action format is not a public editing API. Compilation, signing, import, and execution are separate checks. See [platform boundaries](docs/architecture.md) and [native acceptance](docs/acceptance.md).

## Install

Requirements: macOS 13 or later, an Apple Swift 6 toolchain (Xcode 16 or later), and Shortcuts for signing/running. Apple Silicon is the primary target. Building from source is the supported distribution method; no developer certificate, Homebrew package, or notarized binary is supplied.

```sh
git clone https://github.com/ShuaiShuai03/shortcutctl.git
cd shortcutctl
swift build -c release
mkdir -p "$HOME/.local/bin"
# Refuse to replace an existing installation implicitly.
test ! -e "$HOME/.local/bin/shortcutctl" && \
  install -m 755 "$(swift build -c release --show-bin-path)/shortcutctl" "$HOME/.local/bin/shortcutctl"
"$HOME/.local/bin/shortcutctl" --version
```

Add `$HOME/.local/bin` to your shell's `PATH` if needed. The executable does not need this repository, Python, or third-party Shortcuts toolkits at runtime. Updating an existing installation is an explicit replacement of that binary. Removing the installed binary uninstalls the CLI; it does not remove any shortcuts from Shortcuts.app.

There is no configuration file, API key, background service, or telemetry. `--language en|zh` controls human diagnostics; JSON failures include both languages. All options are per invocation.

## First workflow

```sh
shortcutctl create Echo.json --name Echo --template text --json
shortcutctl lint Echo.json --json
shortcutctl build Echo.json --output Echo.unsigned.shortcut --format binary --json
shortcutctl inspect Echo.unsigned.shortcut --json
shortcutctl build Echo.json --output Echo.shortcut --sign anyone --json
```

In Shortcuts.app, use **File → Import** to select `Echo.shortcut`, review it, and add it. Import may use the **file's basename** as the shortcut name. Signing with `anyone` may send the workflow to Apple for validation; use synthetic examples first. `people-who-know-me` can include contact information.

Then find the installed identifier and test it:

```sh
shortcuts list --show-identifiers
shortcutctl test Echo.json --shortcut Echo --json
```

Prefer the installed identifier when names are ambiguous. The test command cannot prove the installed shortcut matches your JSON: import the latest artifact before testing. Keep the JSON and unsigned artifact; this version cannot decompile signed AEA1 containers.

## Commands

| Command | Behavior |
| --- | --- |
| `create` | Generate a JSON project and assertions from text, dictionary, If, Repeat, or HTTP templates |
| `build` | Validate and deterministically compile XML/binary plist; optionally sign with Apple's CLI |
| `inspect` | Show every action, parameter, native metadata field, and structural diagnostic |
| `decompile` | Convert unsigned plist to loss-preserving JSON; no Swift-source generation |
| `lint` | Check control markers, references, UUIDs, text attachments, and selected known parameter types |
| `run` | Execute an explicitly selected installed shortcut and capture output |
| `test` | Compare actual installed-shortcut output with exact UTF-8 assertions |

Every command has `--help` and `--json`. Place options **after the subcommand**. Output-writing commands refuse replacement unless `--force` is supplied; `--dry-run` plans without writing or invoking Shortcuts. Read-only inspection can succeed while reporting an invalid graph; use `lint` to gate builds.

- [CLI commands and output/exit contracts](docs/cli.md)
- [Project format, typed values, and authoring](docs/project-format.md)
- [Five complete example projects](examples/)
- [Development, tests, and coverage](docs/testing.md)
- [Architecture and technical research](docs/architecture.md), [source references](docs/research.md)
- [Automation and Health boundaries](docs/device-boundaries.md)

## Scripting and coding agents

The installed executable works directly from any terminal or coding agent. No skill, plugin, AI account, or repository checkout is needed at runtime. [AGENTS.md](AGENTS.md) documents the source repository for contributors; the versioned JSON output and exit codes are the integration contract.

## Verification and limits

Native acceptance on Apple Silicon/macOS 27.2 verified signing, GUI import, and all five templates, including Unicode, both branches, repeat aggregation, and local HTTP JSON parsing. [The acceptance record](docs/acceptance.md) distinguishes those checks from automated tests and compatibility claims.

Unknown actions and parameters are preserved and warned about. A clean lint result is not a guarantee of action availability or valid permissions. Signed-container decoding, Swift decompilation, automatic import/export, live action discovery, diff/watch, iPhone automation management, and Health execution are not implemented in this release.

Native output defaults to `public.plain-text`. For lists, explicitly combine items into one text result before asserting output. Use `run --output-type` for another native format; available conversions depend on Shortcuts. A timeout ends the CLI wait but cannot undo actions or guarantee app-side cancellation.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| `signed_container_unsupported` | Inspect the source JSON or original unsigned plist; there is no supported `shortcuts sign --unsign` command |
| `output_exists` | Choose a new output path, or deliberately replace with `--force` |
| `lossy_serialization` | Use binary format for fractional dates or signed zero; review the unsupported value rather than dropping it |
| Native error or timeout | Check Shortcuts for permission prompts, installed name/identifier, and action availability; do not blindly retry side effects |
| Empty native output | Check the final action and output conversion; use Combine Text for multiple items |
| If condition is incomplete | Use the generated template: convert input to Text before comparing, and retain the operand wrapper |
| Unknown action warning | Preserve it; verify its exact native parameters and availability on the target device |

## License

MIT. See [LICENSE](LICENSE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and the bundled dependency license in [LICENSES/](LICENSES/).
