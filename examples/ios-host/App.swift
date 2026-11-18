import UIKit
import Foundation
import Darwin
import MadCore

enum CheckFailure: Error { case failed }
func check(_ condition: Bool) throws {
    if !condition { throw CheckFailure.failed }
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
                try runHostChecks()
                print("MADCORE_EXTERNAL_IOS_HOST_PASS")
                fflush(stdout)
                exit(0)
            } catch {
                // Never interpolate platform/SDK errors or stored values.
                print("MADCORE_EXTERNAL_IOS_HOST_FAIL")
                fflush(stdout)
                exit(1)
            }
        }
        return true
    }

}

private func runHostChecks() throws {
        try check(!Thread.isMainThread)
        try check(!MadCoreInfo.shared.version.isEmpty)
        let config = try ConfigSnapshot(values: ["count": "7"])
        try check(try config.longValue(key: "count")?.int64Value == 7)

        let defaults = UserDefaults(suiteName: "com.mad.consumer.smoke.preferences")!
        let store = UserDefaultsStringStore(defaults: defaults)
        defer { try? store.remove(key: "theme") }
        try store.put(key: "theme", value: "dark")
        let reopened = UserDefaultsStringStore(defaults: defaults)
        try check(try reopened.get(key: "theme") == "dark")
        try store.remove(key: "theme")
        try check(try reopened.get(key: "theme") == nil)

        let transport = try IosUrlSessionTransport(callTimeoutMillis: 3000)
        let limits = try HttpLimits(connectTimeoutMillis: 3000, readTimeoutMillis: 3000,
                                    maxResponseBytes: 1024, maxRequestBytes: 1024,
                                    allowInsecureHttp: true)
        let client = HttpClient(transport: transport, limits: limits)
        let get = try HttpRequest(url: "http://127.0.0.1:18082/ok", method: HttpMethod.get,
                                  headers: [:], body: KotlinByteArray(size: 0))
        let response = try client.execute(request: get)
        try check(response.status == 200 && response.bodySize == 5)
        let redirect = try HttpRequest(url: "http://127.0.0.1:18082/redirect", method: HttpMethod.get,
                                       headers: [:], body: KotlinByteArray(size: 0))
        try check(try client.execute(request: redirect).status == 302)
    }

