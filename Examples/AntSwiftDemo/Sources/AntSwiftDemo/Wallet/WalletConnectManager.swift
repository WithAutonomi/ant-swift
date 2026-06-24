#if os(iOS)
import Foundation
import Combine
// Reown AppKit (product/module `ReownAppKit`). iOS-only: the connect modal and
// some transitive deps (CoinbaseWalletSDK) are iOS-oriented, so the whole
// feature is gated with #if os(iOS) and excluded from the macOS build.
import ReownAppKit

/// WalletConnect spike: connect an external self-custody wallet (MetaMask,
/// Rainbow, …) via Reown AppKit and have it sign an Autonomi payment
/// transaction. The app never holds a key — the mobile equivalent of the
/// desktop app's Reown AppKit + wagmi external-signer flow.
///
/// API verified against the resolved reown-swift source (sessionsPublisher /
/// sessionResponsePublisher, AppKit.configure, request(.eth_sendTransaction),
/// getAddress/getSelectedChain).
@MainActor
final class WalletConnectManager: ObservableObject {
    @Published var address: String?
    @Published var chainCaip2: String?
    @Published var lastTxHash: String?
    @Published var status: String = "Not connected"

    private var cancellables = Set<AnyCancellable>()
    private var configured = false

    /// Get a projectId from https://dashboard.reown.com.
    func configure(projectId: String) {
        guard !configured else { return }
        configured = true

        // `native` must match a URL scheme the app handles so wallets can
        // deep-link back after signing. The scheme is well-formed, so the
        // throwing initializer never fails here.
        let metadata = AppMetadata(
            name: "AntSwiftDemo",
            description: "Autonomi mobile bindings demo",
            url: "https://autonomi.com",
            icons: ["https://avatars.githubusercontent.com/u/179229932"],
            redirect: try! AppMetadata.Redirect(native: "antswiftdemo://", universal: nil)
        )

        AppKit.configure(
            projectId: projectId,
            metadata: metadata,
            crypto: SpikeCryptoProvider(), // only used by SIWE, which we don't use
            authRequestParams: nil
        )

        AppKit.instance.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        refresh()
        status = "Configured — tap Connect Wallet"
    }

    /// Present the Reown connect modal (QR + installed-wallet deep links).
    func connect() { AppKit.present() }

    private func refresh() {
        address = AppKit.instance.getAddress()
        if let chain = AppKit.instance.getSelectedChain() {
            chainCaip2 = "\(chain.chainNamespace):\(chain.chainReference)"
        } else {
            chainCaip2 = nil
        }
        status = address == nil ? "Not connected" : "Connected"
    }

    /// Build + send an ERC-20 `approve(vault, amount)` to the connected wallet
    /// for signing. Returns the broadcast transaction hash.
    func sendApprove(chain: AutonomiChain, amount: String = "0") async throws -> String {
        guard let from = AppKit.instance.getAddress() else { throw SpikeError.notConnected }
        let data = EthCalldata.approve(spender: chain.paymentVaultAddress, amount: amount)
        status = "Awaiting wallet signature…"

        // Subscribe for the response *before* firing the request to avoid a race;
        // request() returns Void and the result arrives on the publisher.
        let hash: String = try await withCheckedThrowingContinuation { cont in
            var token: AnyCancellable?
            token = AppKit.instance.sessionResponsePublisher
                .first()
                .sink { response in
                    token?.cancel()
                    switch response.result {
                    case let .response(value):
                        if let h = try? value.get(String.self) {
                            cont.resume(returning: h)
                        } else {
                            cont.resume(throwing: SpikeError.badResponse)
                        }
                    case let .error(rpcError):
                        cont.resume(throwing: SpikeError.wallet(rpcError.message))
                    }
                }
            token?.store(in: &cancellables)

            Task {
                do {
                    try await AppKit.instance.request(.eth_sendTransaction(
                        from: from,
                        to: chain.tokenAddress,
                        value: "0x0",
                        data: data,
                        nonce: nil, gas: nil, gasPrice: nil,
                        maxFeePerGas: nil, maxPriorityFeePerGas: nil, gasLimit: nil,
                        chainId: String(chain.chainId)
                    ))
                } catch {
                    token?.cancel()
                    cont.resume(throwing: error)
                }
            }
        }

        lastTxHash = hash
        status = "Signed. tx: \(hash)"
        return hash
    }

    enum SpikeError: LocalizedError {
        case notConnected, badResponse
        case wallet(String)
        var errorDescription: String? {
            switch self {
            case .notConnected: return "No wallet connected"
            case .badResponse: return "Unexpected wallet response"
            case let .wallet(msg): return "Wallet rejected/failed: \(msg)"
            }
        }
    }
}

/// Minimal CryptoProvider to satisfy `AppKit.configure`. These are only invoked
/// by SIWE / sign-in-with-ethereum verification, which this spike does not use
/// (authRequestParams: nil). If SIWE is added later, swap in a real keccak256 /
/// secp256k1 recover implementation.
private struct SpikeCryptoProvider: CryptoProvider {
    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data { Data() }
    func keccak256(_ data: Data) -> Data { Data() }
}
#endif
