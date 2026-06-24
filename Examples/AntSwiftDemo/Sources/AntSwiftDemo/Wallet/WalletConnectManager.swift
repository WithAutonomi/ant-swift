#if os(iOS)
import Foundation
import Combine
// Reown AppKit (product/module `ReownAppKit`). iOS-only: the connect modal and
// some transitive deps (CoinbaseWalletSDK) are iOS-oriented, so the whole
// feature is gated with #if os(iOS) and excluded from the macOS build.
import ReownAppKit

/// WalletConnect spike: connect an external self-custody wallet (MetaMask,
/// Rainbow, …) via Reown AppKit and have it sign an Autonomi payment
/// transaction. This is the mobile equivalent of the desktop app's
/// Reown AppKit + wagmi external-signer flow — the app never holds a key.
///
/// Spike goal: prove connect → sign `eth_sendTransaction` → tx hash on device.
/// The transaction we send is a real ERC-20 `approve` to the payment vault
/// (the same first step the desktop performs before `payForQuotes`); with an
/// approve amount of 0 it costs only gas and needs no token balance.
///
/// ⚠️ The request/response bridging below is written against the documented
/// Reown AppKit Swift API but has NOT been compiled — verify type/method
/// names (`Request`, `Response`, `RPCResult`, publisher names) against the
/// resolved SDK version in Xcode. These are the only spots likely to drift.
@MainActor
final class WalletConnectManager: ObservableObject {
    @Published var address: String?
    @Published var chainCaip2: String?
    @Published var lastTxHash: String?
    @Published var status: String = "Not connected"

    private var cancellables = Set<AnyCancellable>()
    private var configured = false

    /// Get a projectId from https://dashboard.reown.com. The desktop app uses
    /// its own; for the spike you can paste any valid WalletConnect project id.
    func configure(projectId: String) {
        guard !configured else { return }
        configured = true

        let metadata = AppMetadata(
            name: "AntSwiftDemo",
            description: "Autonomi mobile bindings demo",
            url: "https://autonomi.com",
            icons: ["https://avatars.githubusercontent.com/u/179229932"]
        )

        // Advertise the chains/methods we need so the wallet's approval sheet
        // matches the desktop app (Arbitrum One + Sepolia, eth_sendTransaction).
        let chains = [AutonomiChain.arbitrumOne, .arbitrumSepolia]
            .compactMap { Blockchain($0.caip2) }
        let namespaces: [String: ProposalNamespace] = [
            "eip155": ProposalNamespace(
                chains: chains,
                methods: ["eth_sendTransaction", "personal_sign", "eth_signTypedData"],
                events: ["chainChanged", "accountsChanged"]
            )
        ]

        AppKit.configure(
            projectId: projectId,
            metadata: metadata,
            sessionParams: .init(requiredNamespaces: namespaces)
        )

        // Reflect the active session into our @Published state.
        AppKit.instance.sessionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.applySession(sessions.first)
            }
            .store(in: &cancellables)

        status = "Configured — tap Connect Wallet"
    }

    /// Present the Reown connect modal (QR + installed-wallet deep links).
    func connect() {
        AppKit.present()
    }

    /// First eip155 account across the session's namespaces. Using
    /// `namespaces` (rather than any `session.accounts` convenience) keeps us
    /// on the documented-stable shape.
    private func firstAccount(_ session: Session) -> Account? {
        session.namespaces.values.flatMap { $0.accounts }.first
    }

    private func applySession(_ session: Session?) {
        guard let session, let account = firstAccount(session) else {
            address = nil
            chainCaip2 = nil
            status = "Not connected"
            return
        }
        address = account.address
        chainCaip2 = account.blockchain.absoluteString
        status = "Connected"
    }

    /// Build and send an ERC-20 `approve(vault, amount)` to the connected
    /// wallet for signing. Returns the broadcast transaction hash.
    func sendApprove(chain: AutonomiChain, amount: String = "0") async throws -> String {
        guard let session = AppKit.instance.getSessions().first,
              let from = firstAccount(session)?.address else {
            throw SpikeError.notConnected
        }
        guard let blockchain = Blockchain(chain.caip2) else {
            throw SpikeError.badChain
        }

        let data = EthCalldata.approve(spender: chain.paymentVaultAddress, amount: amount)
        let tx: [String: String] = [
            "from": from,
            "to": chain.tokenAddress,
            "data": data,
            "value": "0x0",
        ]

        status = "Awaiting wallet signature…"

        let request = try Request(
            topic: session.topic,
            method: "eth_sendTransaction",
            params: AnyCodable([tx]),   // eth_sendTransaction takes a 1-element array
            chainId: blockchain
        )

        // Fire the request, then await the matching response on the publisher.
        try await AppKit.instance.request(params: request)
        let hash = try await awaitResponse(id: request.id)
        lastTxHash = hash
        status = "Signed. tx: \(hash)"
        return hash
    }

    /// Bridge AppKit's publisher-based response delivery into async/await,
    /// matching on the originating request id.
    private func awaitResponse(id: RPCID) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var token: AnyCancellable?
            token = AppKit.instance.sessionResponsePublisher
                .filter { $0.id == id }
                .first()
                .sink { response in
                    token?.cancel()
                    switch response.result {
                    case let .response(value):
                        // eth_sendTransaction result is the tx hash string.
                        if let hash = try? value.get(String.self) {
                            continuation.resume(returning: hash)
                        } else {
                            continuation.resume(throwing: SpikeError.badResponse)
                        }
                    case let .error(rpcError):
                        continuation.resume(throwing: SpikeError.wallet(rpcError.message))
                    }
                }
            token?.store(in: &cancellables)
        }
    }

    enum SpikeError: LocalizedError {
        case notConnected, badChain, badResponse
        case wallet(String)
        var errorDescription: String? {
            switch self {
            case .notConnected: return "No wallet connected"
            case .badChain: return "Invalid chain"
            case .badResponse: return "Unexpected wallet response"
            case let .wallet(msg): return "Wallet rejected/failed: \(msg)"
            }
        }
    }
}
#endif
