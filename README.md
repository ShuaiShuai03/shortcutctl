# shortcutctl

A macOS command-line tool for reproducible Apple Shortcuts development and management, designed for people and coding agents.

## Project status

Repository bootstrap and platform feasibility research are in progress. No executable or supported command interface has been released yet.

Implementation will follow verified product requirements and macOS capabilities. The intended engineering contract includes structured output, stable errors and exit codes, explicit validation, and safeguards for existing user data.

## Safety

Do not commit personal shortcuts, credentials, local configuration, or private integration artifacts. Keep local test artifacts in the ignored `local-artifacts/` directory. Tests must not modify or execute existing personal shortcuts without explicit authorization.
