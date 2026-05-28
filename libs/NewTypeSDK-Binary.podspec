# Relative path: newtypesdk_ios/app/libs/NewTypeSDK-Binary.podspec
# Binary Podspec for XCFramework distribution

Pod::Spec.new do |s|
  s.name = "NewTypeSDK"
  s.version = "0.1.0"
  s.summary = "Type-safe iOS SDK for newtype realtime speaking sessions"
  s.description = <<-DESC
Binary iOS SDK wrapping newtype backend session APIs and LiveKit realtime room flow.
Provides session management, VAD control, and transcript streaming.
  DESC
  s.homepage = "https://example.invalid/newtype"
  s.license = { :type => "MIT", :text => "Internal use only" }
  s.author = { "Squady" => "dev@squady.app" }
  s.platform = :ios, "13.4"
  s.swift_versions = ["5.9"]
  s.source = { :http => "https://example.invalid/newtype/NewTypeSDK-0.1.0-xcframework.zip" }
  s.vendored_frameworks = "NewTypeSDK.xcframework"
  s.frameworks = "Foundation", "AVFoundation"
  s.dependency "LiveKitClient"
end
