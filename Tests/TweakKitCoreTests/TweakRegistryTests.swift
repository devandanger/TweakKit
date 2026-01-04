import XCTest
@testable import TweakKitCore

final class TweakRegistryTests: XCTestCase {
    func testRegistryEmitsEventOnSet() {
        let registry = TweakRegistry.shared
        let key = "test.event.\(UUID().uuidString)"
        let tweak = Tweak<Int>(key, defaultValue: 1, registry: registry)
        let startHistoryCount = registry.history.count

        let expectation = XCTestExpectation(description: "Receives tweak event")
        let observerId = registry.addObserver { event in
            guard event.key == key else {
                return
            }
            XCTAssertEqual(event.oldValueString, "1")
            XCTAssertEqual(event.newValueString, "2")
            XCTAssertEqual(event.source, .code)
            expectation.fulfill()
        }
        defer { registry.removeObserver(observerId) }

        _ = tweak.set(2, source: .code)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(registry.lastTweak?.key, key)
        XCTAssertEqual(registry.history.count, startHistoryCount + 1)
    }

    func testRegistrySetFromStringRecordsEvent() {
        let registry = TweakRegistry.shared
        let key = "test.registry.\(UUID().uuidString)"
        _ = Tweak<Double>(key, defaultValue: 1.5, registry: registry)
        let startHistoryCount = registry.history.count

        let result = registry.set(key, valueString: "3.5", source: .web)
        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(registry.lastTweak?.key, key)
        XCTAssertEqual(registry.lastTweak?.newValueString, "3.5")
        XCTAssertEqual(registry.lastTweak?.source, .web)
        XCTAssertEqual(registry.history.count, startHistoryCount + 1)
    }
}
