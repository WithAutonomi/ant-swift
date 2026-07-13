import SwiftUI
import AntFfi

struct ContentView: View {
    @State private var inputText: String = "hello autonomi"
    @State private var addressInput: String = ""
    @State private var lastUploadedAddress: String = ""
    @State private var downloadedText: String = ""
    @State private var status: String = "Idle. Start a local devnet, then tap Upload."
    @State private var busy: Bool = false

    /// Path the devnet writes its manifest to on the host, resolved per-machine
    /// (works for any user). On the iOS Simulator the shared host home is exposed
    /// via `SIMULATOR_HOST_HOME`; on macOS the app runs on the host, so
    /// `NSHomeDirectory()` is already the host home.
    private var manifestPath: String {
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"]
            ?? NSHomeDirectory()
        return "\(home)/Library/Application Support/ant/devnet-manifest.json"
    }

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

            Text(status).font(.caption).foregroundColor(.secondary)
            if busy { ProgressView().controlSize(.small) }
            Spacer()
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 380)
    }

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
