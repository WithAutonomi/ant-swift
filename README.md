# AntFfi — Swift bindings for the Autonomi network

In-process Swift bindings for [Autonomi](https://autonomi.com), generated from
the [`ant-sdk`](https://github.com/WithAutonomi/ant-sdk) FFI crate via
[UniFFI](https://github.com/mozilla/uniffi-rs). Talks directly to the
network — no daemon process required, suitable for iOS and macOS apps.

## Installation

In your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/WithAutonomi/ant-swift.git", from: "0.0.3"),
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

The release ships the compiled `AntFfi.xcframework` as a binary target
(resolved by url + checksum), so there's nothing to build locally.

## Platforms

| Platform | Architecture |
|---|---|
| iOS (device) | arm64 |
| iOS Simulator | arm64 (Apple Silicon) |
| macOS | arm64 (Apple Silicon) |

Minimum deployment targets: **iOS 16**, **macOS 13**.

> **⚠️ Simulator builds are arm64-only.** The xcframework ships an `arm64`
> simulator slice (Apple Silicon) but **no `x86_64`**. Build for a *concrete*
> simulator — `-destination 'platform=iOS Simulator,name=iPhone 15'` — not
> `generic/platform=iOS Simulator`, which forces an `x86_64` link and fails
> with *"symbol(s) not found for architecture x86_64"*. Intel Macs are not
> supported as a simulator host.

## Choosing a connect method

Everything starts from a `Client`. Pick the constructor that matches how you
pay for uploads:

| Your goal | Constructor | You provide |
|---|---|---|
| **Download / read** public data only | `Client.connect(peers:)` | bootstrap peers |
| **Upload**, the app holds the key | `Client.connectWithWallet(peers:privateKey:rpcUrl:paymentTokenAddress:paymentVaultAddress:)` | key + EVM config |
| **Upload**, the *user's* wallet signs (WalletConnect) | `Client.connectForExternalSigner(peers:rpcUrl:paymentTokenAddress:paymentVaultAddress:)` | EVM config (no key) — see below |
| **Local testing** against a devnet | `Client.connectLocal()` or `Client.connectFromDevnetManifest(path:)` | a running devnet |

All methods are `async` and `throws` — a failure surfaces as a typed
`ClientError`.

## Usage

### Store and retrieve a chunk (local devnet)

```swift
import AntFfi

let client = try await Client.connectLocal()

let payload = Data("hello".utf8)
let put = try await client.chunkPut(data: Array(payload))
let bytes = try await client.chunkGet(addressHex: put.address)
```

### Upload with an app-held key

```swift
let client = try await Client.connectWithWallet(
    peers: [/* network bootstrap multiaddrs */],
    privateKey: "0x…",
    rpcUrl: "https://…",
    paymentTokenAddress: "0x…",   // ANT token
    paymentVaultAddress: "0x…"    // payment vault
)

// Public: the data map is stored on the network; retrieve by address.
let pub = try await client.dataPutPublic(data: Array(payload), paymentMode: "auto")
let back = try await client.dataGetPublic(addressHex: pub.address)

// Private: you keep the returned hex data map; it's the only way back in.
let priv = try await client.dataPutPrivate(data: Array(payload), paymentMode: "auto")
let secret = try await client.dataGetPrivate(dataMapHex: priv.dataMap)
```

### Error handling

```swift
do {
    _ = try await client.dataGetPublic(addressHex: addr)
} catch let error as ClientError {
    switch error {
    case .NotFound:                 // address isn't on the network
        break
    case .NetworkError(let reason): // transient — safe to retry
        print(reason)
    case .PaymentError(let reason):
        print(reason)
    default:
        break
    }
}
```

### Paying with the user's own wallet (external signer)

`connectForExternalSigner` never holds a key. You `prepareDataUpload` /
`prepareFileUpload`, sign the returned payment on-chain with the user's wallet
(e.g. via WalletConnect), then `finalizeUpload`. The full three-step flow,
calldata shapes, and the `IPaymentVault` ABI are documented in
[`ant-sdk/docs/external-signer-flow.md`](https://github.com/WithAutonomi/ant-sdk/blob/main/docs/external-signer-flow.md).
See [`ant-mobile-ios`](https://github.com/WithAutonomi/ant-mobile-ios) for a
complete working reference (WalletConnect wiring, both wave and merkle payment
paths, live progress).

## Parameter reference

- **`paymentMode`** (`dataPutPublic` / `dataPutPrivate` / `fileUploadPublic`):
  `"auto"` (default — picks the cheapest batching for the size), `"single"`,
  or `"merkle"`.
- **`visibility`** (`prepareDataUpload` / `prepareFileUpload`): `"public"`
  (retrieve by address) or `"private"` (retrieve with the hex data map you keep).
- **Addresses & data maps** are hex strings. Chunk/data payloads cross the FFI
  as `[UInt8]` (`Array(data)`).

## Versioning

Releases are cut in lockstep with [`ant-sdk`](https://github.com/WithAutonomi/ant-sdk):
a tag `vX.Y.Z` in `ant-sdk` triggers a matching `vX.Y.Z` release here.

## License

Dual-licensed under either MIT or Apache 2.0, at your option.
