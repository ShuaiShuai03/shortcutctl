# Source research

Research performed on 2026-10-26, before selecting the MVP implementation. No third-party implementation code was copied. The project uses Swift Argument Parser as its only package dependency.

| Source | Inspected revision | License | Decision |
| --- | --- | --- | --- |
| [shortcuts-toolkit](https://github.com/moonhorsemmy/shortcuts-toolkit/tree/d4fb449d2ea3fd7b28eb544a206688723253db35) | `d4fb449d2ea3fd7b28eb544a206688723253db35` | MIT (reference documents include separate attribution) | Study serialization and signing boundaries; do not adopt as a runtime dependency |
| [clean-shortcuts](https://github.com/damionrashford/clean-shortcuts/tree/d34a3de580d791dd87a7cb70e85b6d08e7f7de74) | `d34a3de580d791dd87a7cb70e85b6d08e7f7de74` | Apache-2.0 | Study Swift module design and control-flow encoding; do not adopt its lossy typed decompiler |
| [Swift Argument Parser](https://github.com/apple/swift-argument-parser/tree/1.8.2) | `6a52f3251125d74daf04fcbd5e6f08a75d074382` (1.8.2) | Apache-2.0 with Runtime Library Exception | Pin and adopt for CLI parsing/help |

Relevant search channels were local source, installed Apple documentation/resources, official Apple web documentation, and GitHub source. npm/PyPI packages were not evaluated as runtime dependencies because the specification explicitly requires a single native Swift executable. Available connectors do not provide a supported general-purpose Shortcuts action-graph editing API.

## Format observations

The native action list is `WFWorkflowActions`. Actions contain `WFWorkflowActionIdentifier` and `WFWorkflowActionParameters`. Preserve unknown root fields and action parameters.

- Action outputs are identified by parameter `UUID`. Variable references carry `Type: ActionOutput` and `OutputUUID` inside a `WFTextTokenAttachment` value.
- Interpolated text uses `WFTextTokenString`, `Value.string`, and `attachmentsByRange`. Attachment ranges index **UTF-16 code units**, not characters or UTF-8 bytes.
- If and Repeat blocks are flat marker sequences. Matching markers share an identifier and `GroupingIdentifier`; `WFControlFlowMode` is integer 0 (start), 1 (middle), or 2 (end). Repeat counts can be integral real numbers, not only integer-typed values.
- Dictionary creation uses `WFItems`, wrapping `WFDictionaryFieldValue` and `WFDictionaryFieldValueItems`. The text item type is 0. Published third-party type tables disagree on other item types; the compiler preserves these values instead of enforcing the conflicting tables.
- HTTP GET uses `is.workflow.actions.downloadurl`, `WFURL`, and optional `WFHTTPMethod`. JSON detection uses `is.workflow.actions.detect.dictionary` with `WFInput`; key lookup uses `WFInput` and `WFDictionaryKey`.
- Stop and Output uses `is.workflow.actions.output` and `WFOutput`.
- Native Gallery workflows can omit `WFWorkflowName`. Import naming may use the artifact basename; verify the installed name/identifier rather than assuming a JSON name controls it.

These are observations of a private serialized format, not Apple API guarantees.

## Corroborating evidence

- Installed Apple Gallery `.wflow` resources under `WorkflowKit.framework`: `DocumentReview.wflow`, `ActionItems.wflow`, and `GetStartedWithModels.wflow` corroborate HTTP, variable, repeat, and dictionary lookup encodings. These are bundled sample resources, not the user's database. Their content is not redistributed here.
- [Raycast helper generator](https://github.com/raycast/extensions/blob/2ceb6e4e79bc636bd0528b474587619acef28c33/extensions/focus-modes/src/helper-shortcut.ts): variable tokens, If equality, Stop and Output, filename-based import naming.
- [Cherri dictionary encoder](https://github.com/electrikmilk/cherri/blob/bcc0095754e2cc0baaeb4d93dae172b8153b4716/shortcutgen.go) and [fixture](https://github.com/electrikmilk/cherri/blob/bcc0095754e2cc0baaeb4d93dae172b8153b4716/tests/decomp-me.plist): native dictionary shapes.
- [Cherri web actions](https://github.com/electrikmilk/cherri/blob/bcc0095754e2cc0baaeb4d93dae172b8153b4716/actions/web.cherri) and [basic actions](https://github.com/electrikmilk/cherri/blob/bcc0095754e2cc0baaeb4d93dae172b8153b4716/actions/basic.cherri): HTTP and JSON parameter names.
- [App Intents](https://developer.apple.com/documentation/appintents): exposes an app's own actions/data to system experiences, not arbitrary editing of existing shortcut graphs.

## Rejected assumptions

The installed CLI has no `shortcuts sign --unsign` or `--reverse` option, despite such suggestions in third-party documentation. An AEA1 signed archive is not an unsigned plist. The original MVP refused it explicitly; version 0.2.0 adds the bounded AppleArchive decoder described below. A compiler can preserve unknown actions without knowing whether they are available on the current device. Successful compilation and signing do not establish successful import or execution.

Foundation XML serialization also discards fractional seconds in dates. The compiler performs a decode/compare check before returning output and refuses a lossy conversion; binary format preserves these dates.

## Deterministic binary output

An executable regression test demonstrated different binary bytes across separate processes using Foundation serialization. Apple's [CFBinaryPList.c](https://github.com/apple-oss-distributions/CF/blob/dc54c6bb1c1e5e0b9486c1d26dd5bef110b20bf3/CFBinaryPList.c) documents `bplist00` and enumerates dictionary keys without a sorting guarantee. `plutil` has no canonical-binary option; an XML intermediary loses fractional dates.

The implementation therefore uses an original, small binary writer over the typed value tree with byte-sorted dictionary keys and deterministic object allocation. Every compiled output is independently decoded by Foundation and compared to the source value tree before it can be written. Tests cover wide references, Unicode, signed/unsigned integers, real numbers, data, fractional dates, and separate-process repeatability.

## Native acceptance corrections

Native testing established that Text's `WFTextActionText`, Stop and Output's `WFOutput`, and HTTP's `WFURL` are text-parameter fields: dynamic references use an interpolated `WFTextTokenString`, with a U+FFFC placeholder and `attachmentsByRange`. Supplying a standalone `WFTextTokenAttachment` to Text or Stop and Output imported without an error but left the parameter empty. The templates and validator now distinguish text fields from generic `WFInput` variable attachments. Regression tests preserve this distinction.

If operands require a further `{Type: Variable, Variable: <attachment>}` wrapper; the Raycast helper above demonstrates it. Native testing also required conversion of generic Shortcut Input to Text before string comparison. Repeat's end-marker output is a list; an explicit `is.workflow.actions.text.combine` with `text` and `WFTextSeparator: New Lines` makes CLI assertions deterministic. The [shortcut-lib observed-format notes](https://github.com/findlaywebb/shortcut-lib/blob/535d51e6ca1a5329a24018349ebd7552ac206dd8/docs/wire-format-quirks.md) provided corroborating parameter evidence; no library code was adopted.

On the tested macOS version, `shortcuts run --output-type public.utf8-plain-text` returned empty output despite a visible editor result. `public.plain-text` returned the expected UTF-8 bytes, including Unicode, and is the runner's default. Multi-item output needed explicit text aggregation. These are empirical runtime observations, not universal format guarantees.

Stricter value comparison also demonstrated that Foundation XML normalizes negative zero to positive zero. The compiler refuses this loss and suggests binary output. String comparisons preserve Unicode representation rather than accepting normalization as proof of an identical value.

## Version 0.2.0: signed archives and discovery

Additional research on 2026-10-26 selected Apple's public `AppleArchive`, `CryptoKit`, and `Security` frameworks, with no new package dependency. The original implementation uses SDK stream APIs and does not copy third-party decoder code.

- [Apple decryption streams](https://developer.apple.com/documentation/applearchive/archivebytestream/decryptionstream(readingfrom:encryptioncontext:flags:threadcount:)) and the installed SDK's `AppleArchive.swiftinterface`, `AEAContext.h`, and `AEAStreams.h` establish archive contexts, embedded-key signature integrity, prologue positioning, bounded byte streams, authenticated size attributes, and archive-header/blob access.
- [libshortcutsign at `8feb387`](https://github.com/0xilis/libshortcutsign/blob/8feb387460597365ad6e4e58c64f913a53a9ccbc/extract.c), MIT: corroborates nested AEA → Apple Archive → `Shortcut.wflow`. Its dependency and extraction implementation were not adopted.
- [QuickMergeHelper](https://github.com/0xilis/QuickMergeHelper/blob/main/QuickMerge%20Helper/libshortcutsign/libshortcutsign.m): corroborates the `SigningPublicKey` authentication variant. Used for format evidence only.
- [shortcut-lib at `535d51e`](https://github.com/findlaywebb/shortcut-lib/blob/535d51e6ca1a5329a24018349ebd7552ac206dd8/src/shortcut_lib/decode.py), GPL-3.0: corroborates the `SigningCertificateChain` variant. Not adopted or copied into this MIT project.

The decoder accepts signed, unencrypted profile 0. Authentication metadata begins at offset 12 and contains a signing public key or certificate chain. A leaf certificate's exported P-256 public key supplies archive integrity verification; no certificate trust policy is evaluated. Apple's archive context consumes the prologue, so sequential decryption continues from that stream position. Authenticated sizes are checked before opening decompression; the entire bounded plaintext archive is consumed before workflow parsing. Native Apple-signed fixtures contain an empty root-directory entry followed by one regular `Shortcut.wflow`; synthetic archives with only the workflow are also accepted. No archive-controlled path is extracted.

Native signed files may contain workflow metadata rewritten by Apple. In an existing synthetic Text fixture, decoding revealed `WFQuickActionSurfaces` insertion, a different `WFWorkflowClientVersion`, and removal of `WFWorkflowName`. Diff preserves those differences; they are not discarded to make a source comparison pass. Tests compare the decoded complete workflow through JSON and binary recompilation separately from action-graph comparison with the original source.

App Intents discovery inspects a chosen app's `Contents/Resources/Metadata.appintents/extract.actionsdata`, a JSON resource observed in the installed Shortcuts.app bundle. It exposes an `actions` dictionary, identifiers, title resource keys, parameter names/types, discoverability, and availability metadata. The complete per-action object is retained as JSON. This file format is experimental and is not a public enumeration API. Declared App Intent identifiers cannot be substituted for native serialized workflow action identifiers. The builtin compatibility catalog and observed workflow parameter keys remain separate evidence sources.

Diff uses the existing typed value tree and RFC 6901 paths, without a new dependency. Watch uses content polling and a small pure debounce state; this handles editor atomic replacement without adopting a filesystem-watcher package or retaining a file descriptor to the old inode. Both preserve the existing explicit output, no-overwrite, and process boundaries.

Native 0.2.0 acceptance confirmed that `shortcuts view` rejects installed UUID identifiers while accepting names and the `--` argument separator. The wrapper therefore resolves UUIDs through the supported list command and refuses duplicate-name resolution before requesting the editor. This is separate from `shortcuts run`, whose installed-identifier behavior was already accepted.
