Pod::Spec.new do |spec|

  spec.name         = "StoreKitManager"
  spec.version      = "1.2.4"
  spec.summary      = "StoreKitManager framework"
  spec.description  = "StoreKitManager framework"
  spec.homepage     = "https://github.com/mihail-jdanov/StoreKitManager"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author             = { "Mikhail Zhdanov" => "mihail.jdanov1993@gmail.com" }
  spec.ios.deployment_target = "10.0"
  spec.osx.deployment_target = "10.12"
  spec.source       = { :git => "https://github.com/mihail-jdanov/StoreKitManager.git", :tag => spec.version.to_s }
  spec.swift_version = "5.0"
  spec.source_files  = "StoreKitManager/*.{swift}"
  spec.requires_arc = true
  spec.ios.pod_target_xcconfig = { "PRODUCT_BUNDLE_IDENTIFIER" => "com.skm.${PRODUCT_NAME}-iOS" }
  spec.osx.pod_target_xcconfig = { "PRODUCT_BUNDLE_IDENTIFIER" => "com.skm.${PRODUCT_NAME}-macOS" }
  spec.dependency "TPInAppReceipt", "3.1.1"

end
