import UIKit
import Foundation
import Darwin
import AppComposition

enum ProbeFailure: Error { case failed }
func require(_ condition: Bool) throws {
    if !condition { throw ProbeFailure.failed }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let original: StringStore = AlphaSdk().createStore()
                let returned: StringStore = try BetaSdk().mutateAndReturn(store: original)
                guard let first = original as? MemoryStringStore,
                      let second = returned as? MemoryStringStore else { throw ProbeFailure.failed }
                try require(first === second)
                try require(try original.get(key: "upper.beta") == "shared")
                try returned.put(key: "host.roundtrip", value: "same")
                try require(try original.get(key: "host.roundtrip") == "same")
                print("MADCORE_KOTLIN_COMPOSITION_PASS")
                fflush(stdout)
                exit(0)
            } catch {
                print("MADCORE_KOTLIN_COMPOSITION_FAIL")
                fflush(stdout)
                exit(1)
            }
        }
        return true
    }
}
