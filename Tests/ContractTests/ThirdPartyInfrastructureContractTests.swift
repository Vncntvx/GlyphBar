import Foundation
import Testing
@testable import GlyphBar

// MARK: - XPC Isolation Contract

@MainActor
struct XPCIsolationContractTests {
    @Test func xpcModuleHostCanBeCreated() {
        let broker = CapabilityBroker()
        _ = XPCModuleHost(capabilityBroker: broker)
        #expect(Bool(true))
    }

    @Test func xpcModuleProxyRequiresConnection() {
        let instanceID = ModuleInstanceID(value: "xpc.test")
        let connection = NSXPCConnection(serviceName: "com.test.xpc")
        let proxy = XPCModuleProxy(instanceID: instanceID, connection: connection)
        #expect(proxy.instanceID == instanceID)
    }

    @Test func xpcModuleHostCreatesProxyForPackage() throws {
        let broker = CapabilityBroker()
        let host = XPCModuleHost(capabilityBroker: broker)

        let testPackage = Package(
            id: PackageID(value: "com.test.xpc"),
            version: "1.0.0",
            manifest: ModuleManifest(
                id: "test", displayName: "Test", subtitle: "",
                systemImage: "circle", capabilities: [], permissions: [],
                defaultRefreshPolicy: .manual, actions: [], widgets: []
            ),
            source: .localPackage,
            installURL: nil
        )

        let proxy = try host.loadModule(package: testPackage)
        #expect(proxy.instanceID == ModuleInstanceID.default(for: ModuleTypeID(value: "test")))
    }
}

// MARK: - DiagnosticContext Contract

struct DiagnosticContextContractTests {
    @Test func diagnosticContextHasAllFields() {
        let moduleID = ModuleInstanceID(value: "thirdparty.module")
        let ctx = DiagnosticContext.new(moduleID: moduleID)

        #expect(ctx.correlationID.isEmpty == false, "correlationID must be non-empty")
        #expect(ctx.moduleInstanceID == "thirdparty.module")
        #expect(ctx.commandID.isEmpty == false, "commandID must be non-empty")
    }

    @Test func diagnosticContextCorrelationIDsAreUnique() {
        let moduleID = ModuleInstanceID(value: "test.uniqueness")
        let ctx1 = DiagnosticContext.new(moduleID: moduleID)
        let ctx2 = DiagnosticContext.new(moduleID: moduleID)

        #expect(ctx1.correlationID != ctx2.correlationID,
                "each DiagnosticContext should have a unique correlationID")
    }
}

// MARK: - SchemaVersion Contract

struct SchemaVersionContractTests {
    @Test func protocolVersionsStartAt1() {
        let versions = ProtocolVersions.current
        #expect(versions.packageSchema == 1)
        #expect(versions.manifestSchema == 1)
        #expect(versions.snapshotSchema == 1)
        #expect(versions.projectionSchema == 1)
        #expect(versions.storageSchema == 1)
        #expect(versions.widgetBridgeSchema == 1)
        #expect(versions.commandProtocol == 1)
        #expect(versions.effectProtocol == 1)
        #expect(versions.declarativeUISchema == 1)
    }

    @Test func packageValidatorRejectsNonexistentPath() {
        let validator = PackageValidator()
        #expect(throws: Error.self) {
            try validator.validate(at: URL(fileURLWithPath: "/nonexistent/package"))
        }
    }
}

// MARK: - IngestionSource Coverage

struct IngestionSourceContractTests {
    @Test func allIngestionSourcesAreRepresentable() {
        let sources: [IngestionSource] = [.cli, .shortcuts, .ci, .urlScheme, .internal_]
        #expect(sources.count == 5)
    }
}

// MARK: - ExternalSnapshotV2 Contract

struct ExternalSnapshotV2ContractTests {
    @Test func externalSnapshotCarriesAllFields() {
        let snapshot = ExternalSnapshotV2(
            title: "Title",
            subtitle: "Sub",
            systemImage: "star",
            metrics: ["key": 1.0],
            notes: ["a note"]
        )
        #expect(snapshot.title == "Title")
        #expect(snapshot.subtitle == "Sub")
        #expect(snapshot.systemImage == "star")
        #expect(snapshot.metrics?.count == 1)
        #expect(snapshot.notes?.count == 1)
    }

    @Test func externalSnapshotMinimalFields() {
        let snapshot = ExternalSnapshotV2(
            title: "Min",
            subtitle: "",
            systemImage: "circle",
            metrics: nil,
            notes: nil
        )
        #expect(snapshot.title == "Min")
        #expect(snapshot.metrics == nil)
        #expect(snapshot.notes == nil)
    }
}
