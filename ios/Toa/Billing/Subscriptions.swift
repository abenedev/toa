import Foundation
import Observation
import StoreKit

/// "Remove ads" auto-renewable subscription (StoreKit 2). The entitlement is read
/// on device, so it works offline; purchases are also sent to the backend so the
/// subscription follows the account to other platforms.
@MainActor
@Observable
final class Subscriptions {
    private(set) var product: Product?
    private(set) var isEntitled = false
    private(set) var isPurchasing = false
    private(set) var lastError: String?

    /// Signed transaction not yet accepted by the backend.
    private var pendingJWS: String? {
        get { UserDefaults.standard.string(forKey: "billing.pendingJWS") }
        set { UserDefaults.standard.set(newValue, forKey: "billing.pendingJWS") }
    }

    private var updates: Task<Void, Never>?

    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task { await load() }
    }

    func load() async {
        if product == nil {
            product = try? await Product.products(for: [AppConfig.subscriptionProductId]).first
        }
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == AppConfig.subscriptionProductId,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        isEntitled = entitled
    }

    func purchase(userId: String?) async {
        guard let product else { return }
        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }
        var options: Set<Product.PurchaseOption> = []
        if let userId, let token = UUID(uuidString: userId) {
            options.insert(.appAccountToken(token))
        }
        do {
            let result = try await product.purchase(options: options)
            if case .success(let verification) = result {
                await handle(verification)
            }
        } catch {
            lastError = "The purchase couldn't be completed."
        }
    }

    func restore() async {
        lastError = nil
        do {
            try await AppStore.sync()
        } catch {
            lastError = "Couldn't restore purchases."
        }
        await refreshEntitlement()
    }

    /// Sends the pending purchase to the backend; called after each sync.
    func uploadPending(using api: APIClient?) async -> ProfileDTO? {
        guard let jws = pendingJWS, let api else { return nil }
        do {
            let profile = try await api.submitAppleTransaction(jws)
            pendingJWS = nil
            return profile
        } catch APIError.http(let status) where (400..<500).contains(status) {
            pendingJWS = nil  // rejected for good (e.g. bought while signed in to another account)
            return nil
        } catch {
            return nil
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        if transaction.productID == AppConfig.subscriptionProductId {
            pendingJWS = result.jwsRepresentation
            NotificationCenter.default.post(name: .toaLocalChange, object: nil)
        }
        await transaction.finish()
        await refreshEntitlement()
    }
}
