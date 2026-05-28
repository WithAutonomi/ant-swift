# AntSwiftDemo

A minimal SwiftUI app that exercises the AntFfi package end-to-end:
type a message, tap Upload, get a chunk address back, paste that
address into Download to round-trip the content.

Builds for **iOS Simulator** and **macOS**. Uses the parent directory's
`Package.swift` so it always tracks the working copy of `ant-swift`.

## Prerequisites

- Xcode 15+ with the iOS Simulator SDK installed.
- `xcodegen` to generate the project file:
  `brew install xcodegen`
- Rust toolchain (for the devnet): `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- `anvil` from Foundry (the devnet's embedded EVM blockchain):
  `brew install foundry`

### Starting the local devnet

The demo needs a devnet running on the host. From a checkout of
[`ant-client`](https://github.com/WithAutonomi/ant-client):

```sh
# One-time: move any cached public mainnet/testnet bootstrap peers out
# of the way. Otherwise the local devnet's bootstrap nodes will spin
# forever trying to dial unreachable hosts and never become ready.
# Restore the file after you're done with devnet work.
mv ~/Library/Caches/saorsa/bootstrap/bootstrap_cache.json \
   ~/Library/Caches/saorsa/bootstrap/bootstrap_cache.json.aside

cargo run --release --example start-local-devnet --features devnet
```

Leave it running. It writes the manifest at
`~/Library/Application Support/ant/devnet-manifest.json` (hardcoded
path in `ContentView.swift`).

## Run

```sh
cd Examples/AntSwiftDemo
xcodegen                # one-time / after editing project.yml
open AntSwiftDemo.xcodeproj
# then ⌘R against an iPhone simulator or "My Mac"
```

Or all from the command line:

```sh
# macOS
xcodebuild -scheme AntSwiftDemo -destination 'platform=macOS' build
open ./build/Debug/AntSwiftDemo.app

# iOS Simulator
xcodebuild -scheme AntSwiftDemo -destination 'platform=iOS Simulator,name=iPhone 17' build
xcrun simctl install booted ./build/Debug-iphonesimulator/AntSwiftDemo.app
xcrun simctl launch booted com.autonomi.examples.AntSwiftDemo
```

## What it does

- **Upload**: appends a random suffix to the input text (so successive
  taps produce distinct chunks — Autonomi is content-addressed, so
  identical content always lands at the same address), uploads as a
  chunk, displays the resulting address.
- **Download**: paste any chunk address (or tap "Use last") and pull
  the content back as text.

## Caveats

- This is a **devnet** demo. Production wallets, payment flows, and
  bootstrap discovery look different.
- The manifest path is hardcoded to the macOS user's home. For a
  different machine, edit `ContentView.swift` (`manifestPath`).
- The macOS build disables App Sandbox so the app can read the
  manifest from `~/Library/Application Support/ant/` and reach the
  devnet over loopback. Don't ship a real app with these settings.
