//
//  GlobalShortcutTests.swift
//  Translate MenuTests
//
//  Unit tests for the global shortcut value type.
//
//  GlobalShortcut is deliberately pure — no Carbon, no UI, no global state — so the rules
//  that matter can be tested in-process with no Accessibility permission and no window
//  server. That is the whole reason the validation lives here rather than in the recorder
//  view: a test can reach it, and a future caller cannot skip it.
//

import Carbon.HIToolbox
import XCTest
@testable import Translate_Menu

final class GlobalShortcutTests: XCTestCase {

    /// kVK_ANSI_T — an arbitrary printable key, used wherever the key itself is irrelevant.
    private let keyT = UInt16(kVK_ANSI_T)

    // MARK: - Validation
    //
    // The important behaviour in this type. A global hotkey with no ⌘/⌥/⌃ fires on every
    // press of that key in every app: record "T" and typing "t" in Mail opens the
    // translator over the message. These tests are the guard against that shipping.

    func test_init_rejectsBareKey() {
        XCTAssertNil(GlobalShortcut(keyCode: keyT, modifiers: []),
                     "A key with no modifiers would fire on every press of that key, everywhere")
    }

    func test_init_rejectsShiftOnly() {
        XCTAssertNil(GlobalShortcut(keyCode: keyT, modifiers: [.shift]),
                     "⇧T is just a capital T — shift alone must not qualify")
    }

    func test_init_rejectsFunctionAndCapsLockOnly() {
        XCTAssertNil(GlobalShortcut(keyCode: keyT, modifiers: [.capsLock]))
        XCTAssertNil(GlobalShortcut(keyCode: keyT, modifiers: [.function]))
        XCTAssertNil(GlobalShortcut(keyCode: keyT, modifiers: [.capsLock, .shift]))
    }

    func test_init_acceptsEachQualifyingModifier() {
        XCTAssertNotNil(GlobalShortcut(keyCode: keyT, modifiers: [.command]))
        XCTAssertNotNil(GlobalShortcut(keyCode: keyT, modifiers: [.option]))
        XCTAssertNotNil(GlobalShortcut(keyCode: keyT, modifiers: [.control]))
    }

    func test_init_acceptsShiftWhenCombinedWithAQualifier() {
        XCTAssertNotNil(GlobalShortcut(keyCode: keyT, modifiers: [.shift, .command]),
                        "⇧⌘T is fine — shift just cannot be the only modifier")
    }

    // MARK: - Normalisation

    func test_init_ignoresCapsLock() {
        // Caps Lock is a state, not an intent. ⌘T pressed with Caps Lock on is still ⌘T,
        // and must compare equal — the same class of bug that broke cmd+C/V/A in #13.
        let withCaps = GlobalShortcut(keyCode: keyT, modifiers: [.command, .capsLock])
        let without = GlobalShortcut(keyCode: keyT, modifiers: [.command])
        XCTAssertEqual(withCaps, without)
    }

    func test_init_discardsIrrelevantFlags() {
        // NSEvent hands over flags we don't care about (numeric pad, function, device
        // -dependent bits). Storing them would make two identical shortcuts compare unequal.
        let noisy = GlobalShortcut(keyCode: keyT, modifiers: [.command, .numericPad, .function])
        let clean = GlobalShortcut(keyCode: keyT, modifiers: [.command])
        XCTAssertEqual(noisy, clean)
    }

    // MARK: - Display

    func test_displayString_usesStandardModifierOrder() {
        // macOS orders modifiers ⌃⌥⇧⌘ everywhere; matching it means the field reads the
        // same as the shortcut printed in any other app's menu.
        let all = GlobalShortcut(keyCode: keyT, modifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(all?.displayString, "⌃⌥⇧⌘T")
    }

    func test_displayString_singleModifier() {
        XCTAssertEqual(GlobalShortcut(keyCode: keyT, modifiers: [.command])?.displayString, "⌘T")
        XCTAssertEqual(GlobalShortcut(keyCode: keyT, modifiers: [.option])?.displayString, "⌥T")
    }

    func test_displayString_namesNonPrintableKeys() {
        // Keys with no character of their own get a glyph rather than "Key 49".
        XCTAssertEqual(GlobalShortcut(keyCode: UInt16(kVK_Space), modifiers: [.command])?.displayString, "⌘Space")
        XCTAssertEqual(GlobalShortcut(keyCode: UInt16(kVK_LeftArrow), modifiers: [.command])?.displayString, "⌘←")
        XCTAssertEqual(GlobalShortcut(keyCode: UInt16(kVK_Return), modifiers: [.command])?.displayString, "⌘↩")
    }

    // MARK: - Carbon translation
    //
    // Carbon uses its own modifier constants, unrelated to NSEvent's. Getting this mapping
    // wrong registers a shortcut the user never asked for, which is hard to spot by eye.

    func test_carbonModifiers_mapsEachModifier() {
        XCTAssertEqual(GlobalShortcut(keyCode: keyT, modifiers: [.command])?.carbonModifiers, UInt32(cmdKey))
        XCTAssertEqual(GlobalShortcut(keyCode: keyT, modifiers: [.option])?.carbonModifiers, UInt32(optionKey))
        XCTAssertEqual(GlobalShortcut(keyCode: keyT, modifiers: [.control])?.carbonModifiers, UInt32(controlKey))
    }

    func test_carbonModifiers_combinesModifiers() {
        let shortcut = GlobalShortcut(keyCode: keyT, modifiers: [.command, .option])
        XCTAssertEqual(shortcut?.carbonModifiers, UInt32(cmdKey) | UInt32(optionKey))
        // Guards the exact value verified against a live registration of ⌥⌘T.
        XCTAssertEqual(shortcut?.carbonModifiers, 2304)
    }

    func test_carbonModifiers_excludesCapsLock() {
        // Carbon has no caps lock hotkey modifier; leaking it in would corrupt the mask.
        let shortcut = GlobalShortcut(keyCode: keyT, modifiers: [.command, .capsLock])
        XCTAssertEqual(shortcut?.carbonModifiers, UInt32(cmdKey))
    }

    // MARK: - Persistence

    /// A throwaway defaults domain per test, so these never touch the real app's settings.
    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "GlobalShortcutTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    func test_load_returnsNilWhenNothingSaved() {
        XCTAssertNil(GlobalShortcut.load(from: makeDefaults()),
                     "No shortcut set is the default state — nothing may be registered")
    }

    func test_saveThenLoad_roundTrips() {
        let defaults = makeDefaults()
        let original = GlobalShortcut(keyCode: keyT, modifiers: [.command, .option])!

        original.save(to: defaults)

        XCTAssertEqual(GlobalShortcut.load(from: defaults), original)
    }

    func test_clear_removesTheShortcut() {
        let defaults = makeDefaults()
        GlobalShortcut(keyCode: keyT, modifiers: [.command])!.save(to: defaults)
        XCTAssertNotNil(GlobalShortcut.load(from: defaults))

        GlobalShortcut.clear(in: defaults)

        XCTAssertNil(GlobalShortcut.load(from: defaults))
    }

    func test_load_rejectsStoredValueThatFailsValidation() {
        // Defaults are editable by hand, and an older build could have written something
        // today's rules reject. Loading it would register a bare-key hotkey — so a stored
        // value has to clear the same bar as a freshly recorded one.
        let defaults = makeDefaults()
        defaults.set(Int(keyT), forKey: "globalShortcutKeyCode")
        defaults.set(0, forKey: "globalShortcutModifiers") // no modifiers

        XCTAssertNil(GlobalShortcut.load(from: defaults))
    }

    func test_load_returnsNilWhenOnlyOneHalfIsPresent() {
        let defaults = makeDefaults()
        defaults.set(Int(keyT), forKey: "globalShortcutKeyCode")
        // modifiers deliberately absent — a partial write must not read as "no modifiers".

        XCTAssertNil(GlobalShortcut.load(from: defaults))
    }

    func test_load_rejectsOutOfRangeKeyCode() {
        let defaults = makeDefaults()
        defaults.set(Int(UInt32.max), forKey: "globalShortcutKeyCode") // too big for UInt16
        defaults.set(Int(NSEvent.ModifierFlags.command.rawValue), forKey: "globalShortcutModifiers")

        XCTAssertNil(GlobalShortcut.load(from: defaults))
    }
}
