import MadCore

// Thin upper SDK: references the shared Core, never bundles another copy.
public func featureAlphaRead(_ config: ConfigSnapshot) throws -> Int64 {
    try config.longValue(key: "count")?.int64Value ?? -1
}
