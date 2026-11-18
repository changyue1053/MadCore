import MadCore
import Foundation

let version: String = MadCoreInfo.shared.version

// This consumer is typechecked outside the checkout against the generated framework only.
// Throwing configuration APIs must import as Swift throws, not process-terminating Kotlin exceptions.
func consumeConfiguration() throws {
    let config = try ConfigSnapshot(values: ["feature.enabled": "true", "timeout": "10"])
    _ = try config.booleanValue(key: "feature.enabled")
    _ = try config.longValue(key: "timeout")
    _ = try config.doubleValue(key: "missing")
}

func constructNativeTransport() throws {
    let transport: HttpTransport = try IosUrlSessionTransport(callTimeoutMillis: 30_000)
    _ = transport
}

func useMemoryStorage() throws {
    let store: StringStore = MemoryStringStore()
    try store.put(key: "theme", value: "dark")
    _ = try store.get(key: "theme")
    try store.remove(key: "theme")
}

// Check concrete Foundation adapter bridge and throwing methods too.
func useNativeStorage() throws {
    let defaults = UserDefaults(suiteName: "com.mad.consumer.typecheck")!
    let store = UserDefaultsStringStore(defaults: defaults)
    try store.put(key: "theme", value: "dark")
    _ = try store.get(key: "theme")
    try store.remove(key: "theme")
}
