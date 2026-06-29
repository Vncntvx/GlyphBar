import Foundation
import Testing
@testable import GlyphBar

@MainActor
struct ModuleCacheNamespaceTests {
    @Test func moduleCacheNamespaceIsolatesTwoModules() {
        let defaults = UserDefaults(suiteName: "CacheNamespaceTests.\(UUID().uuidString)")!
        let cacheA = ModuleCacheNamespace(moduleID: "moduleA", defaults: defaults)
        let cacheB = ModuleCacheNamespace(moduleID: "moduleB", defaults: defaults)

        cacheA.saveDomainState(Data([1, 2, 3]))
        cacheB.saveDomainState(Data([4, 5, 6]))

        #expect(cacheA.loadDomainState() == Data([1, 2, 3]))
        #expect(cacheB.loadDomainState() == Data([4, 5, 6]))
        #expect(cacheA.loadDomainState() != cacheB.loadDomainState())
    }

    @Test func moduleCacheNamespaceClearRemovesState() {
        let cache = ModuleCacheNamespace(moduleID: "clearTest")
        cache.saveDomainState(Data([1, 2, 3]))
        #expect(cache.loadDomainState() != nil)
        cache.clearDomainState()
        #expect(cache.loadDomainState() == nil)
    }
}
