//
//  EditShortcutTests.swift
//  Translate MenuTests
//
//  Unit tests for the ⌘C / ⌘V / ⌘A matcher.
//
//  EditShortcutMatcher is deliberately pure — no window server, no WKWebView — so the
//  layout-independence that issue #29 is about can be pinned down in-process. The bug was
//  matching on the layout's character: on a Ukrainian or German layout the shortcuts
//  stopped working. These tests are the guard against going back to that.
//

import Carbon.HIToolbox
import XCTest
@testable import Translate_Menu

final class EditShortcutTests: XCTestCase {

    private let keyC = UInt16(kVK_ANSI_C)
    private let keyV = UInt16(kVK_ANSI_V)
    private let keyA = UInt16(kVK_ANSI_A)

    private func match(_ keyCode: UInt16,
                       _ characters: String?,
                       _ flags: NSEvent.ModifierFlags = [.command]) -> EditShortcut? {
        EditShortcutMatcher.shortcut(keyCode: keyCode,
                                     charactersIgnoringModifiers: characters,
                                     modifierFlags: flags)
    }

    // MARK: - US layout

    func test_commandC_isCopy() {
        XCTAssertEqual(match(keyC, "c"), .copy)
    }

    func test_commandV_isPaste() {
        XCTAssertEqual(match(keyV, "v"), .paste)
    }

    func test_commandA_isSelectAll() {
        XCTAssertEqual(match(keyA, "a"), .selectAll)
    }

    // MARK: - Layout independence
    //
    // The regression for issue #29. The character is what the active layout types; the key
    // code is the physical key. Only the latter can be trusted to identify the shortcut.

    func test_commandC_onUkrainianLayout_isCopy() {
        XCTAssertEqual(match(keyC, "с"), .copy,
                       "Cyrillic es sits on the C key — matching the character instead of the key code breaks ⌘C")
    }

    func test_commandV_onUkrainianLayout_isPaste() {
        XCTAssertEqual(match(keyV, "м"), .paste,
                       "Cyrillic em sits on the V key — matching the character instead of the key code breaks ⌘V")
    }

    func test_commandA_onUkrainianLayout_isSelectAll() {
        XCTAssertEqual(match(keyA, "ф"), .selectAll,
                       "Cyrillic ef sits on the A key — matching the character instead of the key code breaks ⌘A")
    }

    func test_commandC_withNoCharacters_isCopy() {
        XCTAssertEqual(match(keyC, nil), .copy,
                       "A dead key or IME can leave the character nil; the key code must still carry the shortcut")
    }

    func test_character_isAFallbackWhenThePhysicalKeyDiffers() {
        // Dvorak: the letter C is typed from a different physical key than kVK_ANSI_C.
        XCTAssertEqual(match(UInt16(kVK_ANSI_B), "c"), .copy)
    }

    // MARK: - Modifiers

    func test_capsLock_doesNotPreventAMatch() {
        XCTAssertEqual(match(keyC, "c", [.command, .capsLock]), .copy,
                       "Caps Lock is not a chord modifier — it must not break the shortcut")
    }

    func test_commandShiftC_isNotCopy() {
        XCTAssertNil(match(keyC, "c", [.command, .shift]))
    }

    func test_commandOptionC_isNotCopy() {
        XCTAssertNil(match(keyC, "c", [.command, .option]))
    }

    func test_controlCommandC_isNotCopy() {
        XCTAssertNil(match(keyC, "c", [.control, .command]))
    }

    func test_bareC_isNotCopy() {
        XCTAssertNil(match(keyC, "c", []),
                     "Without ⌘ this is just typing the letter c")
    }

    // MARK: - Other keys

    func test_commandB_isNotAShortcut() {
        XCTAssertNil(match(UInt16(kVK_ANSI_B), "b"))
    }
}
