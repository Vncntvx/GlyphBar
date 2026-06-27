import Foundation

@MainActor
final class ModuleRegistry {
    typealias Factory = () -> any StatusModule

    private var factories: [ModuleID: Factory] = [:]

    func register(_ factory: @escaping Factory) {
        let module = factory()
        factories[module.manifest.id] = factory
    }

    func makeModules() -> [ModuleID: any StatusModule] {
        Dictionary(uniqueKeysWithValues: factories.map { id, factory in
            (id, factory())
        })
    }
}
