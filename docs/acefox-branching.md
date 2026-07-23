# AceFox branch and release model

`main` is a clean mirror of `https://github.com/mozilla-firefox/firefox.git`'s
`main` branch. It accepts only fast-forward upstream synchronization and must
not contain AceFox changes or trigger a full Firefox build.

Product maintenance happens on version branches such as `acefox/143`. Short
lived changes branch from that version line:

- `feature/143/<topic>` for product work;
- `sync/143/<upstream-sha>` for upstream integration;
- `hotfix/143/<issue>` for released-version fixes.

An annotated `upstream/firefox-<version>` tag pins the exact Mozilla base for
each AceFox line. Only immutable release tags, for example
`acefox-v143.0a1-ai2apps.1`, may publish runtime assets. Consumers must fetch
the matching release asset and verify its SHA-256 checksum; they must never
resolve a moving branch or a `latest` asset.

## Upstream synchronization

1. Fetch `upstream/main` into a short-lived integration branch.
2. Verify the update is a fast-forward before synchronizing `main`.
3. For a product-line update, create `sync/<version>/<upstream-sha>` from the
   relevant `acefox/<version>` branch, resolve conflicts, and run a native
   build before merging it through a pull request.

## Release safety

Build validation is unsigned. Signing, macOS notarization, checksum generation,
and GitHub Release publication belong in a separate protected release workflow
that receives credentials only from a protected GitHub Environment. Credentials
and local signing scripts must never be committed.
