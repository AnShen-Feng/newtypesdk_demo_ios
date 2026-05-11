# NewTypeSDK Binary

此目录包含 NewTypeSDK 的 XCFramework 二进制文件。

## 文件说明

- `NewTypeSDK.xcframework`: SDK 二进制文件（需要单独构建或下载）
- `NewTypeSDK-Binary.podspec`: CocoaPods 配置

## 获取 XCFramework

### 方式一：从本地 SDK 构建

```bash
# 在项目根目录运行
./scripts/setup_xcframework.sh
```

### 方式二：手动构建

```bash
# 1. 进入 SDK 项目
cd ../../newtypesdk_ios/scripts

# 2. 构建 XCFramework
./build_xcframework.sh

# 3. 复制 XCFramework 到此目录
cp -r ../dist/NewTypeSDK.xcframework ../newtypesdk_demo_ios/libs/
```

### 方式三：从远程下载

如果 XCFramework 已上传到 artifact 仓库，可修改 `NewTypeSDK-Binary.podspec` 中的 `source` 字段：

```ruby
s.source = { :http => "https://your-artifact-repo/NewTypeSDK-0.1.0-xcframework.zip" }
```

## Podspec 配置

当前 `NewTypeSDK-Binary.podspec` 使用本地路径配置，适用于开发环境：

```ruby
s.source = { :path => "." }
s.vendored_frameworks = "NewTypeSDK.xcframework"
```

发布时请更新为远程下载地址。
