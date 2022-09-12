//
//  SKMProduct.swift
//  StoreKitManager
//
//  Created by user on 13.07.2020.
//  Copyright © 2020 user. All rights reserved.
//

import StoreKit

public class SKMProduct {
    
    public enum DurationUnit {
        case days
        case months
        case years
        
        var calendarComponent: Calendar.Component {
            switch self {
            case .days:
                return .day
            case .months:
                return .month
            case .years:
                return .year
            }
        }
    }
    
    public enum `Type`: Equatable {
        case consumable
        case nonConsumable
        case autoRenewable
        case nonRenewing(duration: Int, unit: DurationUnit)
    }
    
    private let isPurchasedKey = ".purchased"
    private let isTrialUsedKey = ".trialUsed"
    private let isIntroPeriodUsedKey = ".introPeriodUsed"
    private let purchaseDateKey = ".purchaseDate"
    
    private var priceFormatter: NumberFormatter {
        let priceFormatter = NumberFormatter()
        priceFormatter.numberStyle = .currency
        priceFormatter.locale = skProduct?.priceLocale ?? Locale.current
        return priceFormatter
    }
    
    var skProduct: SKProduct?
    
    var purchaseDate: Date? {
        get {
            return UserDefaults.standard.object(forKey: identifier + purchaseDateKey) as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: identifier + purchaseDateKey)
        }
    }
    
    var isIntroPeriodUsed: Bool? {
        get {
            return UserDefaults.standard.object(forKey: identifier + isIntroPeriodUsedKey) as? Bool
        }
        set {
            UserDefaults.standard.set(newValue, forKey: identifier + isIntroPeriodUsedKey)
        }
    }
    
    var isPurchased: Bool {
        get {
            switch type {
            case .consumable:
                return false
            case .nonConsumable, .autoRenewable:
                return UserDefaults.standard.bool(forKey: identifier + isPurchasedKey)
            case .nonRenewing(let duration, let unit):
                guard let purchaseDate = purchaseDate,
                    let expirationDate = Calendar.current.date(
                        byAdding: unit.calendarComponent,
                        value: duration,
                        to: purchaseDate
                    ) else { return false }
                return Date() < expirationDate
            }
        }
        set {
            switch type {
            case .nonConsumable, .autoRenewable:
                UserDefaults.standard.set(newValue, forKey: identifier + isPurchasedKey)
            default:
                break
            }
        }
    }
    
    public let identifier: String
    public let type: Type
    
    public init(identifier: String, type: Type) {
        self.identifier = identifier
        self.type = type
    }
    
    func getPrice(multiplier: Float) -> NSDecimalNumber? {
        guard let price = skProduct?.price.floatValue else { return nil }
        return NSDecimalNumber(value: price * multiplier)
    }
    
    @available(iOS 11.2, macOS 10.13.2, *)
    func getIntroductoryPrice(multiplier: Float) -> NSDecimalNumber? {
        guard let price = skProduct?.introductoryPrice?.price.floatValue else { return nil }
        return NSDecimalNumber(value: price * multiplier)
    }
    
    func getLocalizedPrice(multiplier: Float) -> String? {
        guard let skProduct = skProduct else { return nil }
        let price = skProduct.price.floatValue * multiplier
        return priceFormatter.string(from: NSDecimalNumber(value: price))
    }
    
    @available(iOS 11.2, macOS 10.13.2, *)
    func getLocalizedIntroductoryPrice(multiplier: Float) -> String? {
        guard let introductoryPrice = skProduct?.introductoryPrice else { return nil }
        let price = introductoryPrice.price.floatValue * multiplier
        return priceFormatter.string(from: NSDecimalNumber(value: price))
    }
    
    public func getPurchaseDate() -> Date? {
        return purchaseDate
    }
    
}

extension SKMProduct: Equatable {
    
    public static func ==(lhs: SKMProduct, rhs: SKMProduct) -> Bool {
        return lhs.identifier == rhs.identifier
    }
    
}
extension SKMProduct: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
    
}
