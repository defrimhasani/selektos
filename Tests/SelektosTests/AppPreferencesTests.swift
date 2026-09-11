import SwiftUI
import XCTest
@testable import Selektos

final class AppPreferencesTests: XCTestCase {
    func testResultRowLimitRejectsUnknownValues() {
        withRestoredPreference(AppPreferences.resultRowLimitKey) {
            UserDefaults.standard.set(123, forKey: AppPreferences.resultRowLimitKey)
            XCTAssertEqual(AppPreferences.resultRowLimit, 10_000)

            UserDefaults.standard.set(25_000, forKey: AppPreferences.resultRowLimitKey)
            XCTAssertEqual(AppPreferences.resultRowLimit, 25_000)
        }
    }

    func testBlankDefaultQueryFallsBackToSafeSQL() {
        withRestoredPreference(AppPreferences.defaultQueryKey) {
            UserDefaults.standard.set(" \n ", forKey: AppPreferences.defaultQueryKey)
            XCTAssertEqual(AppPreferences.defaultQueryText, "SELECT version();")
        }
    }

    func testDefaultQueryIsTrimmed() {
        withRestoredPreference(AppPreferences.defaultQueryKey) {
            UserDefaults.standard.set("\n SELECT 42; \n", forKey: AppPreferences.defaultQueryKey)
            XCTAssertEqual(AppPreferences.defaultQueryText, "SELECT 42;")
        }
    }

    func testAppearanceMapsToExpectedColorScheme() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    private func withRestoredPreference(_ key: String, perform: () -> Void) {
        let oldValue = UserDefaults.standard.object(forKey: key)
        defer {
            if let oldValue {
                UserDefaults.standard.set(oldValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        perform()
    }
}
