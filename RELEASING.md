# Releasing AntFfi

`ant-swift` distributes the Autonomi FFI to Swift consumers as an
[SPM binary target](Package.swift): a prebuilt `AntFfi.xcframework` hosted on
this repo's **GitHub Releases**, plus the generated Swift glue in
`Sources/AntFfi/ant_ffi.swift`. Cutting a release means:

1. build the xcframework from a chosen `ant-sdk` ref,
2. publish it as an `ant-swift` release, and
3. point `Package.swift`'s `binaryTarget` (url + checksum) and the glue at it.

The build **logic** lives in `ant-sdk` (`ffi/scripts/build-swift.sh`) — the
single source of truth. This repo only consumes its output.

## Critical ordering rule

SwiftPM resolves a version tag and reads `Package.swift` **at that tag**. So the
`Package.swift` bump must be committed **before** the release tag is created, and
the release must target that bump commit. Tagging first leaves the tag pointing
at the *previous* release's url+checksum — a stale, un-buildable tag.

## Option A — manual cut (macOS)

Requires Xcode, Rust with the Apple targets
(`aarch64-apple-ios`, `aarch64-apple-ios-sim`, `aarch64-apple-darwin`), and the
`ant-sdk` checkout next to this one. Example bumps `v0.0.3 → v0.0.4`.

```bash
export PATH=/opt/homebrew/bin:$HOME/.cargo/bin:$PATH
TAG=v0.0.4

# 1. Build from ant-sdk (produces ffi/build/{AntFfi.xcframework.zip,.sha256,ant_ffi.swift})
cd ../ant-sdk && git checkout main && git pull
ffi/scripts/build-swift.sh
CHECKSUM=$(cat ffi/build/AntFfi.xcframework.zip.sha256)

# 2. Bump Package.swift + glue and commit (BEFORE tagging)
cd ../ant-swift && git checkout main && git pull
URL="https://github.com/WithAutonomi/ant-swift/releases/download/$TAG/AntFfi.xcframework.zip"
URL="$URL" CHECKSUM="$CHECKSUM" perl -pi -e '
  s{(url: ")[^"]*(")}{$1$ENV{URL}$2};
  s{(checksum: ")[^"]*(")}{$1$ENV{CHECKSUM}$2};
' Package.swift
cp ../ant-sdk/ffi/build/ant_ffi.swift Sources/AntFfi/ant_ffi.swift
git commit -am "release: AntFfi $TAG"
git push origin main

# 3. Create the release/tag AT the bump commit and upload the zip
#    RC tags (e.g. v0.0.9-rc.1): add --prerelease so the repo's "Latest"
#    release stays on the newest stable.
gh release create "$TAG" ../ant-sdk/ffi/build/AntFfi.xcframework.zip \
  --repo WithAutonomi/ant-swift --target "$(git rev-parse HEAD)" --title "$TAG"

# 4. Verify the published asset matches the checksum in Package.swift
gh release download "$TAG" --repo WithAutonomi/ant-swift --pattern 'AntFfi.xcframework.zip' --dir /tmp/relcheck
shasum -a 256 /tmp/relcheck/AntFfi.xcframework.zip   # must equal $CHECKSUM
```

## Option B — automated (`.github/workflows/publish-ffi.yml`)

A `workflow_dispatch` that runs the exact same steps on a `macos-latest` runner.
Trigger from the Actions tab or:

```bash
gh workflow run publish-ffi.yml --repo WithAutonomi/ant-swift \
  -f ant_sdk_ref=main -f release_tag=v0.0.4
```

It checks out `ant-sdk` at `ant_sdk_ref`, runs `build-swift.sh`, commits the
`Package.swift`+glue bump to `main`, creates the release/tag **at that commit**,
and verifies the published asset's checksum. Tags containing `-` (RCs like
`v0.0.8-rc.1`) are published as **pre-releases** automatically, so GitHub's
"Latest" badge keeps pointing at the newest stable. It pushes the bump directly
to `main`, so it requires an **unprotected `main`** — if `main` becomes
protected, fall back to Option A (or split B into a bump-PR + a post-merge
release step).

## History / notes

- `v0.0.3` (2026-07-06) was cut manually via Option A from ant-sdk `main`
  (external-signer wave + merkle uploads, progress callbacks) on
  ant-core 0.3.0 (`ant-cli-v0.2.10`).
- Keep this SDK's ant-core version aligned with the antd daemon's (`ant-sdk`
  `antd/Cargo.toml`) so the whole SDK ships on one core.
