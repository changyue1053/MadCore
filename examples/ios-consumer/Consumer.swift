import MadCore

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
