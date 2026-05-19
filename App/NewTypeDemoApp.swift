// Relative path: newtypesdk_demo_ios/App/NewTypeDemoApp.swift

import SwiftUI
import UIKit

@UIApplicationMain
final class NewTypeDemoApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_ application: UIApplication) {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: ContentView(viewModel: DemoViewModel()))
        window.makeKeyAndVisible()
        self.window = window
    }
}
