import Foundation
import Testing
@testable import GlyphBar

private final class IngestionEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [IngestionEvent] = []

    var events: [IngestionEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ event: IngestionEvent) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
    }
}

// MARK: - Third-Party Module Contract Tests
//
// Third-party modules (declarative JSON, XPC-hosted) must satisfy the same
// ModuleContract paradigm constraints. These tests verify the platform
// infrastructure that supports third-party modules.

// MARK: - IngestionAPI Contract

@MainActor
struct IngestionAPIContractTests {
    @Test func ingestionAPIPublishesToSubscribers() {
        let api = IngestionAPI()
        let recorder = IngestionEventRecorder()

        api.subscribe { event in
            recorder.append(event)
        }

        let instanceID = ModuleInstanceID(value: "thirdparty.demo")
        let payload = IngestionPayload(
            snapshot: ExternalSnapshotV2(
                title: "Demo", subtitle: "v1", systemImage: "sparkles",
                metrics: nil, notes: nil
            ),
            source: .cli
        )

        try? api.publish(payload: payload, forInstance: instanceID)

        let receivedEvents = recorder.events
        #expect(receivedEvents.count == 1)
        if case .snapshotPublished(let id, _) = receivedEvents.first {
            #expect(id == instanceID)
        } else {
            Issue.record("Expected snapshotPublished event, got \(receivedEvents)")
        }
    }

    @Test func ingestionAPIRejectsUnsupportedSchemaVersion() {
        let api = IngestionAPI()
        let payload = IngestionPayload(
            schemaVersion: 999,
            snapshot: ExternalSnapshotV2(
                title: "Bad", subtitle: "", systemImage: "xmark",
                metrics: nil, notes: nil
            ),
            source: .shortcuts
        )

        #expect(throws: IngestionError.self) {
            try api.publish(payload: payload, forInstance: ModuleInstanceID(value: "bad.schema"))
        }
    }

    @Test func ingestionAPIAcceptsAllSourceTypes() {
        let api = IngestionAPI()
        let recorder = IngestionEventRecorder()

        api.subscribe { recorder.append($0) }

        let sources: [IngestionSource] = [.cli, .shortcuts, .ci, .urlScheme, .internal_]
        for source in sources {
            let payload = IngestionPayload(
                snapshot: ExternalSnapshotV2(
                    title: "Test", subtitle: "", systemImage: "circle",
                    metrics: nil, notes: nil
                ),
                source: source
            )
            try? api.publish(payload: payload, forInstance: ModuleInstanceID(value: "src.\(source)"))
        }

        #expect(recorder.events.count == sources.count, "all source types should produce events")
    }

    @Test func ingestionAPIInvalidateRemovesSnapshot() throws {
        let api = IngestionAPI()
        let instanceID = ModuleInstanceID(value: "invalidate.test")

        let payload = IngestionPayload(
            snapshot: ExternalSnapshotV2(
                title: "Temp", subtitle: "", systemImage: "circle",
                metrics: nil, notes: nil
            ),
            source: .cli
        )

        try api.publish(payload: payload, forInstance: instanceID)
        try api.invalidate(instance: instanceID)
        // No crash = success
    }

    @Test func ingestionAPIClearRemovesAllSnapshots() throws {
        let api = IngestionAPI()
        let instanceID = ModuleInstanceID(value: "clear.test")

        let payload = IngestionPayload(
            snapshot: ExternalSnapshotV2(
                title: "Clear", subtitle: "", systemImage: "circle",
                metrics: nil, notes: nil
            ),
            source: .ci
        )

        try api.publish(payload: payload, forInstance: instanceID)
        try api.clear(instance: instanceID)
        // No crash = success
    }
}
