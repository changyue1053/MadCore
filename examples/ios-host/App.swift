import UIKit
import Foundation
import Darwin
import MadCore
import FeatureAlpha
import FeatureBeta

final class HostResource: NSObject, CloseableResource {
    private let action: () throws -> Void
    init(action: @escaping () throws -> Void) { self.action = action }
    func close() throws { try action() }
}

enum CheckFailure: Error { case failed }
func check(_ condition: Bool) throws {
    if !condition { throw CheckFailure.failed }
}

private func checkInvalidStorageKey(_ operation: () throws -> Void) throws {
    do {
        try operation()
    } catch {
        // Assert the bridged Kotlin type and failure, not a localized message.
        let nsError = error as NSError
        guard let storageError = nsError.userInfo["KotlinException"] as? StorageException,
              storageError.failure.name == "InvalidKey" else { throw error }
        return
    }
    throw CheckFailure.failed
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        print("MADCORE_HOST_STAGE_APP_LAUNCH")
        fflush(stdout)
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
        print("MADCORE_HOST_STAGE_CHECKS")
        fflush(stdout)
        try check(!Thread.isMainThread)
        let scope = ResourceScope()
        var closeCount = 0
        let resource = HostResource { closeCount += 1 }
        _ = try scope.register(resource: resource)
        try check(try scope.close().attempted == 1)
        try check(scope.isClosed && closeCount == 1)
        try check(try scope.close().attempted == 0)
        let failureScope = ResourceScope()
        var cleanupCount = 0
        _ = try failureScope.register(resource: HostResource { cleanupCount += 1 })
        _ = try failureScope.register(resource: HostResource { throw CheckFailure.failed })
        _ = try failureScope.register(resource: HostResource { cleanupCount += 1 })
        let failureReport = try failureScope.close()
        try check(failureReport.failed == 1 && failureReport.attempted == 3 && cleanupCount == 2)
        try check(try failureScope.close().attempted == 0)

        try check(!MadCoreInfo.shared.version.isEmpty)
        let config = try ConfigSnapshot(values: ["count": "7"])
        try check(try config.longValue(key: "count")?.int64Value == 7)
        let fromBeta = featureBetaIdentity(config)
        try check(fromBeta === config)
        try check(try featureAlphaRead(fromBeta) == 7)
        print("MADCORE_SHARED_UPPER_SDKS_PASS")
        fflush(stdout)

        let defaults = UserDefaults(suiteName: "com.mad.consumer.smoke.preferences")!
        let store = UserDefaultsStringStore(defaults: defaults)
        defer { try? store.remove(key: "theme") }
        try store.put(key: "theme", value: "dark")
        let reopened = UserDefaultsStringStore(defaults: defaults)
        try check(try reopened.get(key: "theme") == "dark")
        try store.remove(key: "theme")
        try check(try reopened.get(key: "theme") == nil)

        let protocolStore: StringStore = store
        try checkInvalidStorageKey { _ = try store.get(key: "") }
        try checkInvalidStorageKey { try store.put(key: "", value: "test") }
        try checkInvalidStorageKey { try store.remove(key: "") }
        try checkInvalidStorageKey { _ = try protocolStore.get(key: "") }
        try checkInvalidStorageKey { try protocolStore.put(key: "", value: "test") }
        try checkInvalidStorageKey { try protocolStore.remove(key: "") }

        print("MADCORE_HOST_STAGE_HTTP")
        fflush(stdout)
        let transport = try IosUrlSessionTransport(callTimeoutMillis: 3000)
        let limits = try HttpLimits(connectTimeoutMillis: 3000, readTimeoutMillis: 3000,
                                    maxResponseBytes: 1024, maxRequestBytes: 1024,
                                    allowInsecureHttp: true)
        let client = HttpClient(transport: transport, limits: limits)
        let get = try HttpRequest(url: "http://127.0.0.1:18082/ok", method: HttpMethod.get,
                                  headers: [:], body: KotlinByteArray(size: 0))
        let response = try client.execute(request: get)
        try check(response.status == 200 && response.bodySize == 5)
        let expected = Array("hello".utf8)
        let received = response.body
        for index in 0..<expected.count {
            try check(received.get(index: Int32(index)) == Int8(expected[index]))
        }
        let redirect = try HttpRequest(url: "http://127.0.0.1:18082/redirect", method: HttpMethod.get,
                                       headers: [:], body: KotlinByteArray(size: 0))
        try check(try client.execute(request: redirect).status == 302)
    }

