# AntFfi — Swift bindings for the Autonomi network

In-process Swift bindings for [Autonomi](https://autonomi.com), generated from
the [`ant-sdk`](https://github.com/WithAutonomi/ant-sdk) FFI crate via
[UniFFI](https://github.com/mozilla/uniffi-rs). Talks directly to the
network — no daemon process required, suitable for iOS and macOS apps.

## Installation

In your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/WithAutonomi/ant-swift.git", from: "0.0.7"),
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

### Upload a file from disk (recommended for large data)

For anything larger than a small blob, upload **from a file path** rather than
loading bytes into memory. `ant-core` streams the file through self-encryption
and spills chunks to disk, so memory stays flat regardless of file size — the
in-memory `dataPut*` / `chunkPut` APIs hold the whole payload in RAM.

```swift
// Preview the cost before paying (sampled — fast, confidence-aware).
let est = try await client.estimateFileCost(path: fileURL.path, paymentMode: "auto")
print("\(est.chunkCount) chunks · ~\(est.storageCostAtto) atto ANT · \(est.confidence)")

// Public: retrievable by address.
let put = try await client.fileUploadPublic(path: fileURL.path, paymentMode: "auto")

// Private: keep the returned hex data map — it's the only way back in.
let priv = try await client.fileUploadPrivate(path: fileURL.path, paymentMode: "auto")

// Download straight to disk (streams; ProgressListener is required).
final class NoopProgress: ProgressListener { func onProgress(update: ProgressUpdate) {} }
let bytes = try await client.downloadPublicToFile(
    addressHex: put.address, destPath: outURL.path, listener: NoopProgress())
```

`CostEstimate` fields: `fileSize`, `chunkCount`, `storageCostAtto` (storage in
atto-ANT), `estimatedGasCostWei`, `paymentMode`, and `confidence` — a string
(`priced_sample`, `verified_all_already_stored`, …) telling you how firm the
estimate is, so you don't render a best-effort `0` as "free".

> **Memory model.** File uploads and `download*ToFile` **stream** (constant
> memory). The `dataPut*` / `dataGet*` / `chunk*` APIs load the full payload
> into `[UInt8]` — fine for small data, avoid for large. Prefer the file-path
> APIs on mobile.

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

`connectForExternalSigner` never holds a key. The flow is: `prepareFileUpload`
→ `paymentTransactions(uploadId)` (the SDK returns the ready-to-sign `approve` +
`pay` transactions — you never build calldata) → sign each with the user's
wallet and `waitForReceipt` → `finalizeUpload` (wave) or `finalizeUploadMerkle`
(merkle). All ABI encoding, receipt polling, and the merkle-winner lookup live
in the SDK.

The full step-by-step flow, with Swift **and** Kotlin worked examples, wave vs
merkle routing, and the paid-but-not-stored retry contract, is documented in
[`ant-sdk/docs/mobile-external-signer.md`](https://github.com/WithAutonomi/ant-sdk/blob/main/docs/mobile-external-signer.md).
See [`ant-mobile-ios`](https://github.com/WithAutonomi/ant-mobile-ios) for a
complete working reference (WalletConnect wiring, both payment paths, live
progress).

> The older [`external-signer-flow.md`](https://github.com/WithAutonomi/ant-sdk/blob/main/docs/external-signer-flow.md)
> describes the **antd daemon REST** flow (HTTP endpoints, hand-rolled ABI) — it
> does **not** apply to this mobile SDK. Use the mobile doc above.

## Parameter reference

- **`paymentMode`** (`dataPutPublic` / `dataPutPrivate` / `fileUploadPublic`):
  `"auto"` (default — picks the cheapest batching for the size), `"single"`,
  or `"merkle"`.
- **`visibility`** (`prepareDataUpload` / `prepareFileUpload`): `"public"`
  (retrieve by address) or `"private"` (retrieve with the hex data map you keep).
- **Addresses & data maps** are hex strings. Chunk/data payloads cross the FFI
  as `[UInt8]` (`Array(data)`).

## Versioning

Releases are built from [`ant-sdk`](https://github.com/WithAutonomi/ant-sdk)'s
`ffi/` source and published from this repo via the manual
[`publish-ffi`](.github/workflows/publish-ffi.yml) workflow (see
[RELEASING.md](RELEASING.md)): each release bumps `Package.swift` to the new
asset URL + checksum, commits, then tags `vX.Y.Z` here. The Android SDK
([`ant-android`](https://github.com/WithAutonomi/ant-android)) is published at
the same version to [`ant-maven`](https://github.com/WithAutonomi/ant-maven).

## License

Dual-licensed under either MIT or Apache 2.0, at your option.
