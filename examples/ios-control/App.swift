// Diagnostic control only: no MadCore linkage, no network or storage.
import UIKit
import Darwin

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        print("MADCORE_CONTROL_APP_LAUNCH")
        fflush(stdout)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        DispatchQueue.global(qos: .userInitiated).async {
            print("MADCORE_CONTROL_PASS")
            fflush(stdout)
            exit(0)
        }
        return true
    }
}
