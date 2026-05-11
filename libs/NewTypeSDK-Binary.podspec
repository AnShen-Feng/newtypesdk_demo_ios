Pod::Spec.new do |s|
  s.name = "NewTypeSDK"
  s.version = "0.1.0"
  s.summary = "Type-safe iOS SDK for newtype realtime speaking sessions"
  s.description = <<-DESC
Binary iOS SDK wrapping newtype backend session APIs and LiveKit realtime room flow.
Provides session management, VAD control, and transcript streaming.
  DESC
  s.homepage = "https://github.com/squady/newtype"
  s.license = { :type => "MIT", :text => "Internal use only" }
  s.author = { "Squady" => "dev@squady.app" }
  s.platform = :ios, "15.0"
  s.swift_versions = ["5.9"]
  s.source = { :path => "." }
  s.vendored_frameworks = "NewTypeSDK.xcframework"
  s.frameworks = "Foundation", "AVFoundation"
  s.dependency "LiveKitClient"
  s.pod_target_xcconfig = {
    "EXCLUDED_ARCHS[sdk=iphonesimulator*]" => "i386",
    "DEFINES_MODULE" => "YES",
  }
end
