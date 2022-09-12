# StoreKitManager
Менеджер покупок c локальной валидацией чека.
# 1.2.4
**Swift 5.0+, iOS 10.0+, macOS 10.12+**

**Установка**
1. Добавить в Podfile:
```ruby
source 'https://github.com/CocoaPods/Specs.git'

target 'MyProject' do
    pod 'StoreKitManager', '~> 1.2.4'
end
```
2. Выполнить `pod install`

**Настройка**
1. Создание ID продуктов:
```swift
extension SKMProduct {

    private static let bundle = Bundle.main.bundleIdentifier!

    static let oneMonthSale = SKMProduct(identifier: bundle + ".1monsale", type: .autoRenewable)
    static let threeMonth = SKMProduct(identifier: bundle + ".3mon", type: .autoRenewable)
    static let fullpack = SKMProduct(identifier: bundle + ".fullpack", type: .nonConsumable)
    
}
```
2. Инициализация менеджера:
```swift
subscribeToSKMNotifications() // Перед инициализацией менеджера рекомендуется подписаться на его нотификации (список приведён в 4 пункте)
let products: [SKMProduct] = [.oneMonthSale, .threeMonth .fullpack]
let store = StoreKitManager(products: products) // Для iOS
let store = StoreKitManager(products: products, isReceiptRequired: true) // Для macOS, где isReceiptRequired - обязательность наличия рецепта
```
3. Покупка, восстановление и пр.:
```swift
// Покупка
store.purchase(.oneMonthSale)

// Восстановление
store.restorePurchases()

// Куплен ли продукт
let isPurchased = store.isPurchased(.oneMonthSale)

// Получение статуса интро (или пробного) периода для группы подписок
store.getIntroPeriodStatus(forSubscriptions: [.oneMonthSale, .threeMonth], completion: { status in
    let isIntroPeriodUsed = status.isIntroPeriodUsed
    ...
})

// Получение цены продукта (возвращает tuple с ценой в NSDecimalNumber и локализованной ценой)
store.getPrice(for: .oneMonthSale, multiplier: multiplier, completion: { price in
    let priceDecimal = price.decimalValue
    let priceLocalized = price.localizedString
    ...
})

// Получение интро-цены продукта (только для iOS 11.2+ и macOS 10.13.2+, возвращает tuple с ценой в NSDecimalNumber и локализованной ценой)
store.getIntroductoryPrice(for: .oneMonthSale, multiplier: multiplier, completion: { price in
    let priceDecimal = price.decimalValue
    let priceLocalized = price.localizedString
    ...
})
```
4. Нотификации менеджера (`Notification.Name`):
```swift
.storeKitManagerInternetFail // Нет интернет-соединения
.storeKitManagerPurchaseSuccess // Покупка успешно завершена
.storeKitManagerPurchaseFailed // Покупка не удалась
.storeKitManagerPurchaseCancelled // Покупка отменена
.storeKitManagerRestoreSuccess // Восстановление успешно завершено
.storeKitManagerRestoreFailed // Восстановление не удалось
.storeKitManagerVerifiedAutoRenewables // Верификация подписок завершена
.storeKitManagerReceivedSKProducts // Получена информация о продуктах
```
5. Промоинаппы (по умолчанию возврат `true`):
```swift
store.shouldAddStorePaymentHandler = { queue, payment, product in
    return true
}
```
