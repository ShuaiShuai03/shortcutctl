# Version 0.2.0 acceptance — 2026-10-26

Observed native platform: Apple Silicon, macOS 27.2 (26B118), Xcode 27.0 (27A5252f), Swift 6.4, and Shortcuts 10.0. This record covers the new signed decoding, discovery, diff, watch, and list/view commands. The [original record](acceptance.md) retains the separate signing/import/execution evidence for the five templates.

## Automated checks

- `swift build` and `swift build -c release`: passed.
- `python3 scripts/check-coverage.py`: **41 Swift test functions** passed, including the existing 22-case and 8-case parameterized functions; **16 executable CLI tests** passed.
- Combined first-party line coverage: **2,010 / 2,165 lines (92.84%)**. Region coverage: **1,027 / 1,192 (86.16%)**. Test code and dependencies are excluded; GUI/native acceptance is not included in these counts.
- Strict recursive Swift formatting and `git diff --check`: passed.
- All 16 executable CLI tests passed against the optimized release executable.
- The local release executable targets macOS 13.0, contains an Apple Silicon Mach-O image, and links only system libraries/frameworks. It has an ad hoc linker signature, with no Developer ID or notarization.

CI separately verifies and packages Apple Silicon and Intel release executables. Check the [CI workflow](https://github.com/ShuaiShuai03/shortcutctl/actions/workflows/ci.yml) for the exact release commit; hosted tests do not establish device execution or GUI acceptance.

## Native signed-container checks

The release executable decoded five existing, synthetic Apple-signed acceptance artifacts through `decompile`, `inspect`, and `lint`. Each complete decoded workflow was rebuilt as binary plist and compared to the signed input with `diff --workflow-only --check`; every comparison was equal. The native observations and fixture hashes are in [the machine-readable record](acceptance-0.2.0-results.json). Raw signed containers and local reports remain ignored.

| Fixture | Decoded actions | Complete native workflow round trip |
| --- | --- | --- |
| Text | 2 | Equal |
| Dictionary | 4 | Equal |
| If | 8 | Equal |
| Repeat | 5 | Equal |
| HTTP | 5 | Equal |

These checks establish preservation of decoded native content, including metadata. They do not assert that Apple signing leaves source metadata unchanged: the Text artifact contained a changed client version, an added quick-action field, and no native workflow name. The typed diff reported all three differences. Project runtime assertions remain outside the compiled native workflow.

Synthetic automated archives additionally cover both embedded-public-key and certificate-chain authentication, optional empty-root entries, unknown native values, fractional dates, Unicode, sliced input data, truncation, tampering, malformed authentication, encrypted-profile rejection, duplicate/link/path rejection, and decompression/block-size limits. The test certificate is self-signed and generated with an ephemeral key; successful decoding does not establish certificate trust.

## Discovery and editor checks

- `discover --app` read the installed Shortcuts.app metadata and returned **15 App Intent declarations**, retaining their complete action JSON and marking the result incomplete.
- `discover --workflow` found **5 distinct native action identifiers** in the decoded HTTP fixture.
- Installed-shortcut and folder listing succeeded through Apple's CLI. Raw list content was not published.
- An explicit editor request for the synthetic installed Text fixture succeeded. Native acceptance first demonstrated that Apple's `view` rejects UUIDs directly; the wrapper now resolves identifiers through the list command and requires a unique name. This record establishes a successful native editor request, not a visual audit or editing session.

## Diff and watch checks

Executable regressions verify typed before/after values, JSON Pointer escaping, Unicode key identity, structural comparison across project/plist representations, and `--check` exit 8.

Watch tests build a synthetic source, observe an invalid edit without changing the last successful output, then recover after an atomic save. Further tests confirm dry-run/once behavior, strict validation, output/source separation, a fixed output directory despite symlink retargeting, and refusal to replace external output edits. The native release executable also completed initial watch validation on the decoded Text fixture.

## Boundaries

- Archive integrity is checked against an embedded key; Apple certificate trust, contact identity, and shortcut safety are not evaluated. Encrypted AEA profiles remain unsupported.
- The serialized workflow and App Intents metadata formats are experimental. Discovery is partial, and metadata identifiers are distinct from native action identifiers.
- Diff is structural and compares arrays by index; it does not establish behavioral equivalence or align moved actions.
- No new physical iPhone, iPad, Health, automation-trigger, or cross-device acceptance was performed. Original template execution evidence is separate.
- Watch produces unsigned local artifacts and performs no signing, import, or workflow execution. Native timeouts do not reverse side effects or guarantee app-side cancellation.
