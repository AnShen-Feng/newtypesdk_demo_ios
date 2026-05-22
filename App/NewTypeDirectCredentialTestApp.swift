// Relative path: newtypesdk_demo_ios/App/NewTypeDirectCredentialTestApp.swift

import SwiftUI
import UIKit

@UIApplicationMain
final class NewTypeDirectCredentialTestApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_ application: UIApplication) {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(
            rootView: DirectCredentialTestView(viewModel: DirectCredentialTestViewModel())
        )
        window.makeKeyAndVisible()
        self.window = window
    }
}
