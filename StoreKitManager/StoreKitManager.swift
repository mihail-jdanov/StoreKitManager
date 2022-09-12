//
//  StoreKitManager.swift
//  StoreKitManager
//
//  Created by user on 13.07.2020.
//  Copyright © 2020 user. All rights reserved.
//

import StoreKit
import TPInAppReceipt

public extension Notification.Name {
    
    static let storeKitManagerInternetFail = Notification.Name(rawValue: "StoreKitManagerInternetFail")
    static let storeKitManagerPurchaseSuccess = Notification.Name(rawValue: "StoreKitManagerPurchaseSuccess")
    static let storeKitManagerPurchaseFailed = Notification.Name(rawValue: "StoreKitManagerPurchaseFailed")
    static let storeKitManagerPurchaseCancelled = Notification.Name(rawValue: "StoreKitManagerPurchaseCancelled")
    static let storeKitManagerRestoreSuccess = Notification.Name(rawValue: "StoreKitManagerRestoreSuccess")
    static let storeKitManagerRestoreFailed = Notification.Name(rawValue: "StoreKitManagerRestoreFailed")
    static let storeKitManagerVerifiedAutoRenewables = Notification.Name(rawValue: "StoreKitManagerVerifiedAutoRenewables")
    static let storeKitManagerReceivedSKProducts = Notification.Name(rawValue: "StoreKitManagerReceivedSKProducts")
    
}

public typealias SKMPrice = (decimalValue: NSDecimalNumber, localizedString: String)

public struct SKMIntroStatus {
    
    public let isIntroPeriodUsed: Bool
    
}

public class StoreKitManager: NSObject {
    
    // MARK: - Private constants
    
    private let paymentQueue = SKPaymentQueue.default()
    private let products: [SKMProduct]
    private let receiptRefreshTimeout: TimeInterval = 8
    private let firstProductRequestRetryInterval: TimeInterval = 3
    
    // MARK: - Private variables
    
    private lazy var productRequestDelegate: SKMProductsRequestDelegate = {
        return SKMProductsRequestDelegate(self)
    }()
    
    private lazy var paymentTransactionObserver: SKMPaymentTransactionObserver = {
        return SKMPaymentTransactionObserver(self)
    }()
    
    private var priceRequestsQueue: [(product: SKMProduct, multiplier: Float, completion: (SKMPrice) -> Void)] = []
    private var introductoryPriceRequestsQueue: [(product: SKMProduct, multiplier: Float, completion: (SKMPrice) -> Void)] = []
    private var introPeriodStatusRequestsQueue: [(products: [SKMProduct], completion: (SKMIntroStatus) -> Void)] = []
    private var productRequestCompletion: (() -> Void)?
    private var isProductRequestInProgress = false
    private var isVerifyingAutoRenewablesInProgress = false
    private var isRestoreInProgress = false
    private var isHaveSuccessfulProductRequest = false
    private var firstProductRequest: SKProductsRequest?
    
    #if os(macOS)
    private var isReceiptRequired: Bool
    #endif
    
    // MARK: - Public variables
    
    #if os(iOS)
    public var shouldAddStorePaymentHandler: (SKPaymentQueue, SKPayment, SKProduct) -> Bool = { _, _, _ in
        return true
    }
    #endif
    
    // MARK: - StoreKitManager's init
    
    #if os(iOS)
    public init(products: [SKMProduct]) {
        self.products = products
        super.init()
        DispatchQueue.global().async {
            self.paymentQueue.add(self.paymentTransactionObserver)
            self.requestSKProducts(isFirstRequest: true)
            self.verifyAutoRenewables()
        }
    }
    #endif
    
    #if os(macOS)
    public init(products: [SKMProduct], isReceiptRequired: Bool = true) {
        self.isReceiptRequired = isReceiptRequired
        self.products = products
        super.init()
        DispatchQueue.global().async {
            self.paymentQueue.add(self.paymentTransactionObserver)
            self.requestSKProducts(isFirstRequest: true)
            self.verifyAutoRenewables()
        }
    }
    #endif
    
    // MARK: - Private methods
    
    private func requestSKProducts(isFirstRequest: Bool = false) {
        if isProductRequestInProgress { return }
        print("StoreKitManager – Requesting SKProducts...")
        isProductRequestInProgress = true
        let identifiers = products.map { $0.identifier }
        let productRequest = SKProductsRequest(productIdentifiers: Set(identifiers))
        productRequest.delegate = productRequestDelegate
        if isFirstRequest { firstProductRequest = productRequest }
        productRequest.start()
    }
    
    private func purchase(_ product: SKMProduct, retryIfProductNotFound: Bool) {
        guard products.contains(where: { $0 == product }) else {
            print("StoreKitManager – Wrong product identifier, make sure that this identifier is contained in the identifiers array (manager's init method).")
            return
        }
        guard SKMNetworkStatus.isConnected() else {
            print("StoreKitManager – Unable to start purchase (no internet connection).")
            productRequestCompletion = nil
            NotificationCenter.default.post(name: .storeKitManagerInternetFail, object: nil)
            return
        }
        if let skProduct = product.skProduct {
            let payment = SKPayment(product: skProduct)
            paymentQueue.add(payment)
        } else {
            if retryIfProductNotFound {
                print("StoreKitManager – Unable to start purchase (no SKProduct found). Trying to get products list and restart purchase...")
                productRequestCompletion = {
                    self.purchase(product, retryIfProductNotFound: false)
                    self.productRequestCompletion = nil
                }
                requestSKProducts()
            } else {
                print("StoreKitManager – Unable to start purchase (no SKProduct found).")
                NotificationCenter.default.post(name: .storeKitManagerPurchaseFailed, object: nil)
            }
        }
    }
    
    private func verifyAutoRenewables(for products: [SKMProduct]? = nil, completion: (() -> Void)? = nil) {
        if isVerifyingAutoRenewablesInProgress {
            completion?()
            return
        }
        isVerifyingAutoRenewablesInProgress = true
        if let receipt = try? InAppReceipt.localReceipt() {
            print("StoreKitManager – Local receipt loaded successfully. Verifying auto-renewable subscriptions...")
            updateAutoRenewables(for: products, with: receipt, completion: completion)
        } else {
            #if os(macOS)
            if isReceiptRequired {
                exit(173)
            }
            #endif
            print("StoreKitManager – Local receipt not found. Requesting receipt...")
            let refreshTimeoutTimer = Timer.scheduledTimer(withTimeInterval: receiptRefreshTimeout, repeats: false) { (_) in
                self.isVerifyingAutoRenewablesInProgress = false
                completion?()
            }
            InAppReceipt.refresh { (error) in
                refreshTimeoutTimer.invalidate()
                if let err = error {
                    print("StoreKitManager – Receipt request error: \"\(err.localizedDescription)\"")
                }
                if let receipt = try? InAppReceipt.localReceipt() {
                    print("StoreKitManager – Local receipt loaded successfully. Verifying auto-renewable subscriptions...")
                    self.updateAutoRenewables(for: products, with: receipt, completion: completion)
                } else {
                    self.isVerifyingAutoRenewablesInProgress = false
                    completion?()
                }
            }
        }
    }
    
    private func updateAutoRenewables(for products: [SKMProduct]? = nil, with receipt: InAppReceipt, completion: (() -> Void)? = nil) {
        let products = products ?? self.products
        let autoRenewableProducts = products.filter { $0.type == .autoRenewable }
        if autoRenewableProducts.isEmpty {
            isVerifyingAutoRenewablesInProgress = false
            completion?()
            return
        }
        for product in autoRenewableProducts {
            let activePurchase = receipt.activeAutoRenewableSubscriptionPurchases(ofProductIdentifier: product.identifier, forDate: Date())
            product.isPurchased = activePurchase != nil
            if let purchase = activePurchase {
                product.purchaseDate = purchase.purchaseDate
            }
            product.isIntroPeriodUsed = receipt.purchases(ofProductIdentifier: product.identifier).contains(where: {
                $0.subscriptionTrialPeriod || $0.subscriptionIntroductoryPricePeriod
            })
        }
        print("StoreKitManager – Verified auto-renewable subscriptions:", autoRenewableProducts.map { $0.identifier })
        isVerifyingAutoRenewablesInProgress = false
        NotificationCenter.default.post(name: .storeKitManagerVerifiedAutoRenewables, object: nil)
        processTrialStatusRequests()
        completion?()
    }
    
    private func getProduct(for transaction: SKPaymentTransaction) -> SKMProduct? {
        return products.first { $0.identifier == transaction.payment.productIdentifier }
    }
    
    private func postPurchaseSuccessNotification(for product: SKMProduct) {
        print("StoreKitManager – Purchase successful (\(product.identifier)).")
        NotificationCenter.default.post(name: .storeKitManagerPurchaseSuccess, object: nil)
    }
    
    private func handlePurchasedTransactions(from transactions: [SKPaymentTransaction], checkTransactionState: Bool = true) {
        let purchasedTransactions = checkTransactionState ? transactions.filter { $0.transactionState == .purchased } : transactions
        if purchasedTransactions.isEmpty { return }
        for purchasedTransaction in purchasedTransactions {
            paymentQueue.finishTransaction(purchasedTransaction)
            guard let product = getProduct(for: purchasedTransaction) else { continue }
            if product.type == .nonConsumable {
                product.isPurchased = true
            }
            product.purchaseDate = Date()
            if product.type == .autoRenewable {
                verifyAutoRenewables(for: [product], completion: {
                    self.postPurchaseSuccessNotification(for: product)
                })
            } else {
                postPurchaseSuccessNotification(for: product)
            }
        }
    }
    
    private func handleRestoredTransactions(from transactions: [SKPaymentTransaction]) {
        let restoredTransactions = transactions.filter { $0.transactionState == .restored }
        if restoredTransactions.isEmpty { return }
        // Handle wrong .restored state for macOS
        #if os(macOS)
        if restoredTransactions.count == 1 && !isRestoreInProgress {
            handlePurchasedTransactions(from: restoredTransactions, checkTransactionState: false)
            return
        }
        #endif
        for restoredTransaction in restoredTransactions {
            paymentQueue.finishTransaction(restoredTransaction)
            let product = getProduct(for: restoredTransaction)
            if product?.type == .nonConsumable {
                product?.isPurchased = true
            }
        }
        verifyAutoRenewables()
    }
    
    private func handleFailedTransactions(from transactions: [SKPaymentTransaction]) {
        let failedTransactions = transactions.filter { $0.transactionState == .failed }
        if failedTransactions.isEmpty { return }
        for failedTransaction in failedTransactions {
            paymentQueue.finishTransaction(failedTransaction)
            guard let product = getProduct(for: failedTransaction) else { continue }
            if let nsError = failedTransaction.error as NSError?, nsError.code == SKError.paymentCancelled.rawValue {
                print("StoreKitManager – Purchase cancelled (\(product.identifier)).")
                NotificationCenter.default.post(name: .storeKitManagerPurchaseCancelled, object: nil)
            } else {
                print("StoreKitManager – Purchase failed (\(product.identifier)).")
                NotificationCenter.default.post(name: .storeKitManagerPurchaseFailed, object: nil)
            }
        }
    }
    
    private func processPriceRequests() {
        while !priceRequestsQueue.isEmpty {
            let queueObj = priceRequestsQueue.removeFirst()
            if let decimalValue = queueObj.product.getPrice(multiplier: queueObj.multiplier),
                let localizedString = queueObj.product.getLocalizedPrice(multiplier: queueObj.multiplier) {
                DispatchQueue.main.async {
                    queueObj.completion((decimalValue, localizedString))
                }
            }
        }
        if #available(iOS 11.2, macOS 10.13.2, *) {
            while !introductoryPriceRequestsQueue.isEmpty {
                let queueObj = introductoryPriceRequestsQueue.removeFirst()
                if let decimalValue = queueObj.product.getIntroductoryPrice(multiplier: queueObj.multiplier),
                    let localizedString = queueObj.product.getLocalizedIntroductoryPrice(multiplier: queueObj.multiplier) {
                    DispatchQueue.main.async {
                        queueObj.completion((decimalValue, localizedString))
                    }
                }
            }
        }
    }
    
    private func processTrialStatusRequests() {
        while !introPeriodStatusRequestsQueue.isEmpty {
            let queueObj = introPeriodStatusRequestsQueue.removeFirst()
            var isIntroPeriodUsed: Bool?
            for product in queueObj.products {
                guard let isIntroPeriodUsedForProduct = product.isIntroPeriodUsed else { continue }
                isIntroPeriodUsed = isIntroPeriodUsedForProduct
                if isIntroPeriodUsedForProduct { break }
            }
            if let isIntroPeriodUsed = isIntroPeriodUsed {
                DispatchQueue.main.async {
                    queueObj.completion(SKMIntroStatus(isIntroPeriodUsed: isIntroPeriodUsed))
                }
            }
        }
    }
    
    // MARK: - SKProductsRequestDelegate
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        print("StoreKitManager – SKProducts request completed. Identifiers from response:", response.products.map { $0.productIdentifier })
        for product in products {
            product.skProduct = response.products.first { $0.productIdentifier == product.identifier }
        }
        isHaveSuccessfulProductRequest = true
        isProductRequestInProgress = false
        NotificationCenter.default.post(name: .storeKitManagerReceivedSKProducts, object: nil)
        processPriceRequests()
        productRequestCompletion?()
        firstProductRequest = nil
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        if request is SKProductsRequest {
            print("StoreKitManager – SKProducts request failed with error: \"\(error.localizedDescription)\"")
            isProductRequestInProgress = false
            productRequestCompletion?()
            if request === firstProductRequest {
                DispatchQueue.global().asyncAfter(deadline: .now() + firstProductRequestRetryInterval) {
                    self.requestSKProducts(isFirstRequest: true)
                }
            }
        }
    }
    
    // MARK: - SKPaymentTransactionObserver
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        handlePurchasedTransactions(from: transactions)
        handleRestoredTransactions(from: transactions)
        handleFailedTransactions(from: transactions)
    }
    
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        isRestoreInProgress = false
        print("StoreKitManager – Restore successfully finished.")
        NotificationCenter.default.post(name: .storeKitManagerRestoreSuccess, object: nil)
    }

    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        isRestoreInProgress = false
        print("StoreKitManager – Restore failed with error: \"\(error.localizedDescription)\"")
        NotificationCenter.default.post(name: .storeKitManagerRestoreFailed, object: nil)
    }
    
    #if os(iOS)
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        return shouldAddStorePaymentHandler(queue, payment, product)
    }
    #endif
    
    // MARK: - Public methods
    
    public func purchase(_ productIdentifier: SKMProduct) {
        purchase(productIdentifier, retryIfProductNotFound: true)
    }
    
    public func restorePurchases() {
        guard SKMNetworkStatus.isConnected() else {
            print("StoreKitManager – Unable to restore purchases (no internet connection).")
            NotificationCenter.default.post(name: .storeKitManagerInternetFail, object: nil)
            return
        }
        isRestoreInProgress = true
        paymentQueue.restoreCompletedTransactions()
    }
    
    public func isPurchased(_ product: SKMProduct) -> Bool {
        return product.isPurchased
    }
    
    public func getIntroPeriodStatus(forSubscriptions products: [SKMProduct], completion: @escaping (SKMIntroStatus) -> Void) {
        if products.contains(where: { $0.type != .autoRenewable }) {
            print("StoreKitManager – Introductory period status can be checked only for auto-renewable subscriptions. Make sure you checking status only for auto-renewable product types.")
            return
        }
        var isIntroPeriodUsed: Bool?
        for product in products {
            guard let isIntroPeriodUsedForProduct = product.isIntroPeriodUsed else { continue }
            isIntroPeriodUsed = isIntroPeriodUsedForProduct
            if isIntroPeriodUsedForProduct { break }
        }
        if let isIntroPeriodUsed = isIntroPeriodUsed {
            DispatchQueue.main.async {
                completion(SKMIntroStatus(isIntroPeriodUsed: isIntroPeriodUsed))
            }
        } else {
            introPeriodStatusRequestsQueue.append((products, completion))
            verifyAutoRenewables()
        }
    }
    
    public func getPrice(for product: SKMProduct, multiplier: Float = 1, completion: @escaping (SKMPrice) -> Void) {
        guard isHaveSuccessfulProductRequest else {
            priceRequestsQueue.append((product, multiplier, completion))
            requestSKProducts()
            return
        }
        if let decimalValue = product.getPrice(multiplier: multiplier),
            let localizedString = product.getLocalizedPrice(multiplier: multiplier) {
            DispatchQueue.main.async {
                completion((decimalValue, localizedString))
            }
        }
    }
    
    @available(iOS 11.2, macOS 10.13.2, *)
    public func getIntroductoryPrice(for product: SKMProduct, multiplier: Float = 1, completion: @escaping (SKMPrice) -> Void) {
        guard isHaveSuccessfulProductRequest else {
            introductoryPriceRequestsQueue.append((product, multiplier, completion))
            requestSKProducts()
            return
        }
        if let decimalValue = product.getIntroductoryPrice(multiplier: multiplier),
            let localizedString = product.getLocalizedIntroductoryPrice(multiplier: multiplier) {
            DispatchQueue.main.async {
                completion((decimalValue, localizedString))
            }
        }
    }
    
}

class SKMProductsRequestDelegate: NSObject, SKProductsRequestDelegate {
    
    weak var storeKitManager: StoreKitManager?
    
    init(_ storeKitManager: StoreKitManager) {
        super.init()
        self.storeKitManager = storeKitManager
    }
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        storeKitManager?.productsRequest(request, didReceive: response)
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        storeKitManager?.request(request, didFailWithError: error)
    }
    
}

class SKMPaymentTransactionObserver: NSObject, SKPaymentTransactionObserver {
    
    weak var storeKitManager: StoreKitManager?
    
    init(_ storeKitManager: StoreKitManager) {
        super.init()
        self.storeKitManager = storeKitManager
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        storeKitManager?.paymentQueue(queue, updatedTransactions: transactions)
    }
    
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        storeKitManager?.paymentQueueRestoreCompletedTransactionsFinished(queue)
    }

    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        storeKitManager?.paymentQueue(queue, restoreCompletedTransactionsFailedWithError: error)
    }
    
    #if os(iOS)
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        return storeKitManager?.paymentQueue(queue, shouldAddStorePayment: payment, for: product) ?? true
    }
    #endif
    
}
