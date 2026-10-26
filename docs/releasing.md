# Releases and installation

Source and packaged macOS executables are published through [GitHub Releases](https://github.com/ShuaiShuai03/shortcutctl/releases). Each release identifies the exact source commit. Native workflow compatibility remains experimental regardless of successful builds or tests.

## Packaged executables

Choose `shortcutctl-<version>-macos-arm64.tar.gz` for Apple Silicon or `shortcutctl-<version>-macos-x86_64.tar.gz` for Intel. Download the matching `.sha256` file into the same directory. Verify it before extraction:

```sh
shasum -a 256 -c shortcutctl-0.2.0-macos-arm64.tar.gz.sha256
tar -xzf shortcutctl-0.2.0-macos-arm64.tar.gz
./shortcutctl-0.2.0-macos-arm64/bin/shortcutctl --version
mkdir -p "$HOME/.local/bin"
test ! -e "$HOME/.local/bin/shortcutctl" && \
  install -m 755 shortcutctl-0.2.0-macos-arm64/bin/shortcutctl "$HOME/.local/bin/shortcutctl"
```

`BUILD-INFO.json` records the version, source commit, and architecture. Keep the included license files with redistributed binaries. macOS system frameworks and `/usr/bin/shortcuts` are runtime dependencies supplied by the operating system; Python and this checkout are unnecessary at runtime.

These executables have no Developer ID signature or Apple notarization. A checksum establishes correspondence to the published archive, not Apple trust or workflow safety. macOS may require the user's normal security approval for a downloaded executable; building from source is also supported. Do not disable system security protections as an installation step.

## Updating and rollback

Updating is an explicit replacement of the installed executable. First check the destination and its current `--version`, preserve a copy of the previous binary, and verify the new binary from its extracted directory. Replace only the intended CLI installation, then check its version again. Roll back by restoring that preserved executable. No shortcut data migration is performed; installation does not import, modify, or remove anything in Shortcuts.app.

## Maintainer release procedure

1. Update the CLI version, changelog, contract documentation, and acceptance record.
2. Run the checks in [testing.md](testing.md), including combined coverage, strict Swift formatting, a release build, and CLI tests against the release executable.
3. Complete bounded native checks with synthetic fixtures. Keep signed containers and raw native evidence in ignored `local-artifacts/`; never include account-associated containers in a release.
4. Review the final diff, commit the exact changes, and push the release branch. The CI matrix verifies Apple Silicon and Intel separately, runs the executable contracts against installed release builds, and packages binaries with documentation/licenses and SHA-256 checksums.
5. Require successful CI for the exact source commit to be released. Download both `release-*` artifacts and verify their checksums and architecture/version before publication. Preserve runner provenance; do not label a local Apple Silicon build as Intel-tested.
6. Publish a version tag and GitHub release with the verified archives, checksums, changes, and limitations. Do not replace an existing version's assets silently. Record the release URL and CI run in the release report.

The release workflow does not sign shortcuts, import them, execute personal shortcuts, use the private Shortcuts database, or notarize binaries. Successful hosted CI is distinct from local native acceptance.
