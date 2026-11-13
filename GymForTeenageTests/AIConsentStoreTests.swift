import Foundation
import XCTest
@testable import GymForTeenage

@MainActor
final class AIConsentStoreTests: XCTestCase {
    func testConsentIsEmptyByDefaultAndPersistsOnlySelectedCategories() {
        let suiteName = "AIConsentStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = AIConsentStore(defaults: defaults)
        XCTAssertFalse(initial.hasConsent)
        XCTAssertFalse(initial.allows([.chatMessages]))

        initial.grant([.chatMessages, .exerciseHistory])
        XCTAssertNil(defaults.object(forKey: "aiCoachEnabled"), "Recording consent must not enable AI.")
        let restored = AIConsentStore(defaults: defaults)

        XCTAssertTrue(restored.allows([.chatMessages]))
        XCTAssertTrue(restored.allows([.chatMessages, .exerciseHistory]))
        XCTAssertFalse(restored.allows([.chatMessages, .waterIntake]))
        XCTAssertFalse(restored.allows([.weeklyInsights]))
    }

    func testRevokeRemovesPersistedConsent() {
        let suiteName = "AIConsentStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let consent = AIConsentStore(defaults: defaults)
        consent.grant([.chatMessages, .weeklyInsights])

        consent.revoke()

        XCTAssertFalse(consent.hasConsent)
        XCTAssertFalse(AIConsentStore(defaults: defaults).allows([.weeklyInsights]))
    }

    func testUnknownConsentVersionDoesNotGrantStoredCategories() {
        let suiteName = "AIConsentStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([AIDataCategory.chatMessages.rawValue, AIDataCategory.weeklyInsights.rawValue], forKey: "aiCoachConsentCategories")
        defaults.set(AIConsentStore.currentVersion + 1, forKey: "aiCoachConsentVersion")

        let consent = AIConsentStore(defaults: defaults)

        XCTAssertFalse(consent.hasConsent)
        XCTAssertFalse(consent.allows([.chatMessages]))
        XCTAssertTrue(consent.consentedCategories.isEmpty)
    }

}
