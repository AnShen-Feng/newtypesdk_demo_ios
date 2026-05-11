#
#  NewTypeSDK-Binary.podspec
#
#  NewType iOS SDK CocoaPods 配置文件
#  该 Podspec 用于将二进制 XCFramework 形式发布的 NewTypeSDK
#  通过 CocoaPods 集成到 iOS 项目中
#

Pod::Spec.new do |s|
  # SDK 基本信息
  s.name = "NewTypeSDK"                              # SDK 名称
  s.version = "0.1.0"                                # SDK 版本号
  s.summary = "Type-safe iOS SDK for newtype realtime speaking sessions"  # 简短描述
  
  # 详细描述
  s.description = <<-DESC
Binary iOS SDK wrapping newtype backend session APIs and LiveKit realtime room flow.
Provides session management, VAD control, and transcript streaming.
  DESC
  
  # 主页和许可证
  s.homepage = "https://github.com/squady/newtype"
  s.license = { :type => "MIT", :text => "Internal use only" }
  s.author = { "Squady" => "dev@squady.app" }
  
  # 平台和 Swift 版本要求
  s.platform = :ios, "15.0"                          # 最低支持 iOS 15.0
  s.swift_versions = ["5.9"]                         # 需要 Swift 5.9+
  
  # 源码配置 - 使用本地路径（二进制框架模式）
  s.source = { :path => "." }
  
  #  vendored_frameworks 指定二进制框架路径
  #  CocoaPods 会将此 XCFramework 打包到最终应用中
  s.vendored_frameworks = "NewTypeSDK.xcframework"
  
  # 依赖的系统框架
  s.frameworks = "Foundation", "AVFoundation"
  
  # 依赖 LiveKitClient（用于实时音视频通信）
  s.dependency "LiveKitClient"
  
  # Xcode 构建设置
  s.pod_target_xcconfig = {
    # 排除模拟器 i386 架构（仅支持 x86_64 和 arm64）
    "EXCLUDED_ARCHS[sdk=iphonesimulator*]" => "i386",
    # 启用模块定义
    "DEFINES_MODULE" => "YES",
  }
end
