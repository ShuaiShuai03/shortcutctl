# Project format and authoring

Schema version 1 wraps the native workflow dictionary and optional runtime assertions:

```json
{
  "schemaVersion": 1,
  "name": "Constant",
  "workflow": {
    "WFWorkflowActions": [
      {
        "WFWorkflowActionIdentifier": "is.workflow.actions.gettext",
        "WFWorkflowActionParameters": {
          "WFTextActionText": "Hello"
        }
      }
    ]
  },
  "tests": [
    {"name": "constant", "expectedOutput": "Hello"}
  ]
}
```

For import-ready metadata and tested variable/control-flow encodings, start with `shortcutctl create` or one of the [examples](../examples/). This minimal example illustrates the schema, not compatibility with every device.

`schemaVersion`, `name`, and `workflow` are required. `tests` defaults to an empty array. Unknown wrapper/test fields are rejected to catch typos; unknown **native** fields inside `workflow` are preserved. `name` is project metadata; native import may name the shortcut from the artifact filename. `tests` are never embedded in compiled shortcuts. Source projects belong in version control; generated signed files generally do not.

## Values

Strings, booleans, arrays, and dictionaries map directly to property-list values. Integer numbers are signed 64-bit, or unsigned 64-bit above the signed range. JSON consumers should avoid converting these integers through IEEE-754 doubles. Null and non-finite numbers are unsupported.

Property-list types that JSON cannot distinguish have explicit tags:

| Type | JSON representation |
| --- | --- |
| Data | `{"$plist":"data","value":"AAEC"}` (base64) |
| Date | `{"$plist":"date","value":0.25}` (seconds since 2001-01-01T00:00:00Z) |
| Real | `{"$plist":"real","value":"1.0"}` |
| Literal dictionary containing `$plist` | `{"$plist":"dictionary","value":{"$plist":"literal","other":true}}` |

Tags must contain exactly `$plist` and `value`. Real values use decimal strings to preserve their real type, including integral-valued doubles and signed zero; the codec emits these tags even if input JSON used an ordinary fractional number. Binary format preserves fractional dates and signed zero. Foundation XML serialization changes these values; the compiler detects and refuses that conversion.

Preservation means the decoded native property-list values and types, not source whitespace, XML comments, key order, binary object layout, or signatures. The compiler independently decodes its output with Foundation and compares it with the input tree before publishing it. XML and canonical binary generation are repeatable for the same project and toolchain; Apple signing can introduce changing signatures/metadata. Invalid/unsupported inputs fail instead of falling back to an empty graph.

## Actions and references

`WFWorkflowActions` is an ordered array. Each action has a nonempty `WFWorkflowActionIdentifier` and an optional dictionary of `WFWorkflowActionParameters`. Unknown actions are retained with an `unknown_action` warning; the small compatibility registry is not a catalog of installed actions.

A producer's `UUID` belongs inside its parameters. Generic single-variable input fields commonly use:

```json
{
  "WFSerializationType": "WFTextTokenAttachment",
  "Value": {"Type":"ActionOutput","OutputUUID":"A0000000-0000-4000-8000-000000000001","OutputName":"Text"}
}
```

Text parameter fields such as Text's `WFTextActionText`, Stop and Output's `WFOutput`, and HTTP's `WFURL` require a string token:

```json
{
  "WFSerializationType": "WFTextTokenString",
  "Value": {
    "string": "\ufffc",
    "attachmentsByRange": {
      "{0, 1}": {"Type":"ExtensionInput"}
    }
  }
}
```

Offsets index **UTF-16 code units**, and each attachment addresses a U+FFFC placeholder. An emoji before a token can occupy two UTF-16 units. Passing a standalone attachment into a text field may import without error yet produce an empty native parameter; the linter rejects this known mismatch.

If's `WFInput` has a further wrapper: `{"Type":"Variable","Variable":<attachment>}`. The If template converts shortcut input to Text first so Shortcuts can infer the comparison's type. Conditional and repeat blocks use matching `GroupingIdentifier` values and marker modes 0 (start), 1 (otherwise/menu item), and 2 (end). Repeat has no middle marker. Repeat results refer to the end marker's UUID; the example explicitly combines them into a single text result.

Named variables use `Type: Variable` and `VariableName` inside their attachment. Undefined names produce a warning because dynamic variables are not fully resolved statically. UUID references must resolve to preceding actions. The linter does not perform branch-sensitive data-flow analysis or prove that a variable is assigned on every execution path.

Do not extrapolate parameter envelopes from an action's name: different actions can use the same key with different serialization. Use observed native examples, preserve unfamiliar fields, and validate through actual import/execution on the target device.

## Runtime assertions

```json
{"name":"unicode","input":"Hello 世界 🧪","expectedOutput":"Hello 世界 🧪"}
```

Names must be nonempty and unique. `input` is optional text, written to a temporary UTF-8 file. Output is compared byte-for-byte, including whitespace and newlines. Tests invoke the explicitly selected installed shortcut; they neither emulate actions nor auto-import source files. A successful test proves only those cases on that installed artifact and environment.
