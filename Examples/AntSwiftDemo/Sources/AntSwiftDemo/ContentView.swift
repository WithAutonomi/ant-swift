import SwiftUI
import AntFfi

struct ContentView: View {
    @State private var inputText: String = "hello autonomi"
    @State private var addressInput: String = ""
    @State private var lastUploadedAddress: String = ""
    @State private var downloadedText: String = ""
    @State private var status: String = "Idle. Start a local devnet, then tap Upload."
    @State private var busy: Bool = false

    #if os(iOS)
    @StateObject private var wallet = WalletConnectManager()
    // Spike: paste a projectId from https://dashboard.reown.com. (The desktop
    // app uses its own WalletConnect Cloud project; reuse or create one.)
    private let reownProjectId = "REPLACE_WITH_REOWN_PROJECT_ID"
    #endif

    /// Path the devnet writes its manifest to on the host. The iOS Simulator
    /// shares the macOS filesystem so this absolute path is reachable from
    /// inside the sim too — no env-var wiring required.
    private let manifestPath = "/Users/nic/Library/Application Support/ant/devnet-manifest.json"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AntFfi Demo").font(.title).bold()

            GroupBox("Upload") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Text to upload", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                    Button("Upload (appends random suffix)") { Task { await upload() } }
                        .disabled(busy || inputText.isEmpty)
                    if !lastUploadedAddress.isEmpty {
                        Text("Address: \(lastUploadedAddress)")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }.padding(6)
            }

            GroupBox("Download") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Address (hex)", text: $addressInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        Button("Download") { Task { await download() } }
                            .disabled(busy || addressInput.isEmpty)
                        Button("Use last") {
                            addressInput = lastUploadedAddress
                        }.disabled(lastUploadedAddress.isEmpty)
                    }
                    if !downloadedText.isEmpty {
                        Text("Content: \(downloadedText)")
                            .textSelection(.enabled)
                    }
                }.padding(6)
            }

            #if os(iOS)
            walletSection
            #endif

            Text(status).font(.caption).foregroundColor(.secondary)
            if busy { ProgressView().controlSize(.small) }
            Spacer()
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 380)
        #if os(iOS)
        .onAppear { wallet.configure(projectId: reownProjectId) }
        #endif
    }

    #if os(iOS)
    /// WalletConnect spike UI: connect an external wallet and have it sign a
    /// real Autonomi payment-vault `approve` (amount 0 → gas only, no balance
    /// needed). Proves the external-signer path before the FFI prepare/finalize
    /// surface (V2-391) lands to make it a full paid upload.
    @ViewBuilder private var walletSection: some View {
        GroupBox("Wallet (WalletConnect spike)") {
            VStack(alignment: .leading, spacing: 8) {
                if let address = wallet.address {
                    Text("Connected: \(address)")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Chain: \(wallet.chainCaip2 ?? "?")").font(.caption2)
                    Button("Send test approve tx (Arbitrum One)") {
                        Task { await sendApprove() }
                    }.disabled(busy)
                } else {
                    Button("Connect Wallet") { wallet.connect() }
                }
                if let hash = wallet.lastTxHash {
                    Text("tx: \(hash)")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                Text(wallet.status).font(.caption2).foregroundColor(.secondary)
            }.padding(6)
        }
    }

    private func sendApprove() async {
        busy = true
        defer { busy = false }
        do {
            // amount "0": real signed tx, only gas — proves the signing path
            // without needing a token balance.
            _ = try await wallet.sendApprove(chain: .arbitrumOne, amount: "0")
        } catch {
            status = "Approve failed: \(error.localizedDescription)"
        }
    }
    #endif

    // MARK: - Actions

    private func upload() async {
        busy = true
        status = "Connecting to devnet…"
        defer { busy = false }
        do {
            let client = try await Client.connectFromDevnetManifest(path: manifestPath)
            // Append a random suffix so each tap produces a distinct chunk.
            // Content-addressed storage means identical content → identical
            // address; the suffix makes successive uploads observable.
            let suffix = String(UInt32.random(in: 0..<UInt32.max), radix: 36)
            let payload = Data("\(inputText) [\(suffix)]".utf8)
            status = "Uploading \(payload.count) bytes…"
            let result = try await client.chunkPut(data: payload)
            lastUploadedAddress = result.address
            status = "Uploaded. Tap Download or copy the address."
        } catch {
            status = "Upload failed: \(error)"
        }
    }

    private func download() async {
        busy = true
        status = "Connecting to devnet…"
        defer { busy = false }
        do {
            let client = try await Client.connectFromDevnetManifest(path: manifestPath)
            status = "Downloading…"
            let data = try await client.chunkGet(addressHex: addressInput)
            downloadedText = String(data: data, encoding: .utf8) ?? "<\(data.count) non-UTF8 bytes>"
            status = "Downloaded \(data.count) bytes."
        } catch {
            status = "Download failed: \(error)"
        }
    }
}

#Preview { ContentView() }
