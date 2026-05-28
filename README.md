# AntFfi — Swift bindings for the Autonomi network

In-process Swift bindings for [Autonomi](https://autonomi.com), generated from
the [`ant-sdk`](https://github.com/WithAutonomi/ant-sdk) FFI crate via
[UniFFI](https://github.com/mozilla/uniffi-rs). Talks directly to the
network — no daemon process required, suitable for iOS and macOS apps.

## Installation

In your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/WithAutonomi/ant-swift.git", from: "0.0.1"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "AntFfi", package: "ant-swift"),
        ]
    ),
]
```

Or in Xcode: **File → Add Packages…** and paste the repository URL.

## Platforms

| Platform | Architecture |
|---|---|
| iOS (device) | arm64 |
| iOS Simulator | arm64 (Apple Silicon) |
| macOS | arm64 (Apple Silicon) |

Minimum deployment targets: **iOS 16**, **macOS 13**.

## Usage

```swift
import AntFfi

// Connect to a local devnet.
let client = try await Client.connectLocal()

// Store and retrieve a chunk.
let payload = Data("hello".utf8)
let address = try await client.chunkPut(data: Array(payload))
let retrieved = try await client.chunkGet(addressHex: address.address)
```

For wallet-backed uploads:

```swift
let client = try await Client.connectWithWallet(
    peers: ["..."],
    privateKey: "...",
    rpcUrl: "https://...",
    paymentTokenAddress: "0x...",
    paymentVaultAddress: "0x..."
)
let result = try await client.dataPutPublic(data: Array(payload), paymentMode: "auto")
```

## Versioning

Releases are cut in lockstep with [`ant-sdk`](https://github.com/WithAutonomi/ant-sdk):
a tag `vX.Y.Z` in `ant-sdk` triggers a matching `vX.Y.Z` release here.

## License

Dual-licensed under either MIT or Apache 2.0, at your option.
