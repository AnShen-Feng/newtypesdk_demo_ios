//
//  NewTypeDemoApp.swift
//  NewTypeDemo
//
//  NewType iOS SDK Demo 应用入口文件
//  该文件使用 @main 属性标记整个应用的入口点
//

import SwiftUI

/// 应用主入口结构体
/// 使用 SwiftUI 的 @main 属性自动注册为应用程序入口
@main
struct NewTypeDemoApp: App {
    /// 应用的主场景
    /// 返回一个 WindowGroup，其中包含 ContentView 作为根视图
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
