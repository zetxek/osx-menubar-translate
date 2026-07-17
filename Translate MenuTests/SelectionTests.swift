//
//  SelectionTests.swift
//  Translate MenuTests
//
//  Tests for the two pure pieces of the translate-selection feature: the preference that
//  decides whether Accessibility is ever requested, and the cleaning applied to a raw AX
//  selection before it goes into a URL.
//
//  SelectionReader.readSelection() itself is not here: it needs a live AX session, a
//  frontmost app and a granted permission. It is kept deliberately thin for that reason —
//  everything worth testing sits either side of the AX call.
//

import XCTest
@testable import Translate_Menu

final class PreferencesTests: XCTestCase {

    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "PreferencesTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    func test_translateSelection_defaultsToOff() {
        // The load-bearing default. If this were on, every user would be prompted for
        // Accessibility on first launch for a feature they never asked for.
        XCTAssertFalse(Preferences.translateSelection(in: makeDefaults()))
    }

    func test_translateSelection_roundTrips() {
        let defaults = makeDefaults()

        Preferences.setTranslateSelection(true, in: defaults)
        XCTAssertTrue(Preferences.translateSelection(in: defaults))

        Preferences.setTranslateSelection(false, in: defaults)
        XCTAssertFalse(Preferences.translateSelection(in: defaults))
    }

    func test_translateSelection_readsAsOffWhenValueIsNotABool() {
        // Defaults are hand-editable. Anything unreadable must mean off, never on.
        let defaults = makeDefaults()
        defaults.set("yes please", forKey: "translateSelection")

        XCTAssertFalse(Preferences.translateSelection(in: defaults))
    }
}

final class SelectionCleaningTests: XCTestCase {

    func test_clean_passesOrdinaryTextThrough() {
        XCTAssertEqual(SelectionReader.clean("Hola mundo"), "Hola mundo")
    }

    func test_clean_stripsObjectReplacementCharacters() {
        // Chromium substitutes U+FFFC for inline images, so a page selection arrives
        // peppered with them — verified against a real Vivaldi selection during the spike.
        XCTAssertEqual(SelectionReader.clean("\u{FFFC}Hola\u{FFFC} mundo\u{FFFC}"), "Hola mundo")
    }

    func test_clean_collapsesWhitespaceAndNewlines() {
        XCTAssertEqual(SelectionReader.clean("Hola\n\n   mundo\t\tcruel"), "Hola mundo cruel")
    }

    func test_clean_trimsSurroundingWhitespace() {
        XCTAssertEqual(SelectionReader.clean("   Hola mundo   "), "Hola mundo")
    }

    func test_clean_returnsNilForEmptyInput() {
        XCTAssertNil(SelectionReader.clean(""))
    }

    func test_clean_returnsNilForWhitespaceOnly() {
        XCTAssertNil(SelectionReader.clean("   \n\t  "))
    }

    func test_clean_returnsNilWhenOnlyObjectReplacements() {
        // A selection of nothing but images has no text to translate.
        XCTAssertNil(SelectionReader.clean("\u{FFFC}\u{FFFC}\u{FFFC}"))
    }

    func test_clean_capsLongSelections() {
        // A cmd+A on a long page would otherwise build an absurd translate URL.
        let long = String(repeating: "a", count: SelectionReader.maximumLength * 2)

        let cleaned = SelectionReader.clean(long)

        XCTAssertEqual(cleaned?.count, SelectionReader.maximumLength)
    }

    func test_clean_doesNotCapTextAtTheLimit() {
        let exact = String(repeating: "b", count: SelectionReader.maximumLength)

        XCTAssertEqual(SelectionReader.clean(exact)?.count, SelectionReader.maximumLength)
    }

    func test_clean_preservesNonLatinText() {
        // The app's whole purpose. Capping by character must not mangle multi-byte text.
        XCTAssertEqual(SelectionReader.clean("你好世界"), "你好世界")
        XCTAssertEqual(SelectionReader.clean("  Привет   мир "), "Привет мир")
    }
}
