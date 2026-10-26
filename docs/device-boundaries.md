# Automation and Health boundaries

The MVP's seven commands operate on workflow files or explicitly selected installed macOS shortcuts. They do not configure iPhone personal automation triggers, deploy to a phone, or grant permissions.

## Automation

Apple's documented personal-automation setup uses the Shortcuts interface on the target device. There is no verified general-purpose public API in this project for creating, editing, or enabling arbitrary personal automation triggers. A future planner can generate instructions/configuration for manual device confirmation, but cannot describe that plan as a completed installation. `AutomationPlanner` is a deferred design component, not a placeholder implementation.

See [Apple's personal automation guide](https://support.apple.com/guide/shortcuts/apd690170742/ios) and the [feasibility investigation](architecture.md).

## Health

Health action identifiers and their parameters can be retained as unknown native values. The existing linter checks the surrounding action dictionary, references, control markers, and plist representability. It does **not** validate Health quantity identifiers, units, date semantics, write compatibility, or privacy permissions. A warning for an unknown Health action must not be converted into a claim of Health compatibility.

The typed-value tests cover metadata, binary data, fractional dates, and unknown action parameters. Those structural guarantees are separate from any ability to read or write health records. A dedicated `HealthActionCatalog` and the `health` command remain P2 work.

Apple requires authorization for the relevant HealthKit data types. An App Intents integration would expose actions owned by a companion app and still use system-controlled permissions. This CLI does not bypass those controls, infer whether permission was granted from a successful build, or execute real health writes as a smoke test.

See [Apple's HealthKit authorization documentation](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data) and [App Intents](https://developer.apple.com/documentation/appintents).

**Acceptance:** no physical iPhone or Health write has been tested. Validate those workflows with the intended device, actual action availability, explicit user consent, and a separate record of observed results before claiming support.
