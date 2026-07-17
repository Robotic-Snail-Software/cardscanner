import CardScanner

/// Seed entries for the demo catalog.
///
/// These use real card NAMES (so the name-only fallback has something to
/// match) under the deliberately fake set code `DEMO` — no real collector
/// numbers are hard-coded, because wrong ones would silently break
/// exact-printing testing. To test exact locks, scan any card you own and
/// tap "Trust Reading": the demo adds that set + collector number to the
/// in-memory catalog, and subsequent frames lock against it.
enum DemoCards {
    static let printings: [CatalogPrinting] = [
        "Lightning Bolt",
        "Counterspell",
        "Llanowar Elves",
        "Birds of Paradise",
        "Wrath of God",
        "Dark Ritual",
        "Giant Growth",
        "Shivan Dragon",
        "Serra Angel",
        "Sol Ring",
        "Swords to Plowshares",
        "Duress",
        "Opt",
        "Negate",
        "Cultivate",
    ].enumerated().map { index, name in
        CatalogPrinting(
            id: "demo-\(index + 1)",
            name: name,
            setCode: "DEMO",
            collectorNumber: String(index + 1)
        )
    }
}
