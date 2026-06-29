import Foundation
import Testing
@testable import GlyphBar

struct SnapshotEnvelopeTests {
    @Test func snapshotEnvelopeIncludesSchemaVersion() {
        let projections = ProjectionSet()
        let envelope = SnapshotEnvelope(
            id: "test",
            schemaVersion: 1,
            capturedAt: Date(),
            validUntil: nil,
            freshness: .fresh,
            health: .healthy,
            projections: projections
        )

        #expect(envelope.schemaVersion == 1)
        #expect(envelope.id == "test")
        #expect(envelope.freshness == .fresh)
        #expect(envelope.health == .healthy)
    }

    @Test func snapshotEnvelopeDefaultsAreSensible() {
        let projections = ProjectionSet()
        let envelope = SnapshotEnvelope(id: "defaults", projections: projections)

        #expect(envelope.schemaVersion == 1)
        #expect(envelope.capturedAt != Date.distantPast)
        #expect(envelope.health == .healthy)
        #expect(envelope.freshness == .fresh)
    }
}
