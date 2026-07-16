/*
* Copyright (c) 2015 Adrián Moreno Peña
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
* THE SOFTWARE.
*/

import Carbon.HIToolbox
import Cocoa

/// A global keyboard shortcut: a key plus the modifiers held with it.
///
/// Pure value type — it knows nothing about Carbon registration or the UI, so the
/// rules that matter (what counts as a legal shortcut, how it reads, how it round-trips
/// through UserDefaults) live somewhere they can be reasoned about on their own.
struct GlobalShortcut: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    /// Modifiers that make a shortcut safe to register globally.
    ///
    /// At least one of these is required. Without a modifier the hotkey fires on *every*
    /// press of that key in *every* app — record "T" and typing "t" in Mail would open
    /// the translator over the message. Shift alone doesn't count: shift+T is a capital T.
    private static let qualifyingModifiers: NSEvent.ModifierFlags = [.command, .option, .control]

    /// Creates a shortcut, or nil if the combination isn't safe to register globally.
    ///
    /// Returning nil rather than trapping means callers must handle the invalid case, and
    /// keeps the rule in one place — a recorder can't forget to check it.
    init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let relevant = modifiers.intersection(.deviceIndependentFlagsMask)
        guard !relevant.intersection(Self.qualifyingModifiers).isEmpty else { return nil }

        self.keyCode = keyCode
        // Store only the modifiers that matter, so ⌘T recorded with Caps Lock on still
        // equals ⌘T recorded without it.
        self.modifiers = relevant.intersection([.command, .option, .control, .shift])
    }

    /// How the shortcut reads in the UI, e.g. `⌥⌘T`.
    /// Ordered the way macOS orders modifiers everywhere else: ⌃⌥⇧⌘.
    var displayString: String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        return out + Self.keyName(for: keyCode)
    }

    // MARK: - Carbon

    /// The modifier bitmask Carbon's RegisterEventHotKey expects. Carbon uses its own
    /// constants rather than NSEvent's, so the two have to be translated explicitly.
    var carbonModifiers: UInt32 {
        var out: UInt32 = 0
        if modifiers.contains(.command) { out |= UInt32(cmdKey) }
        if modifiers.contains(.option) { out |= UInt32(optionKey) }
        if modifiers.contains(.control) { out |= UInt32(controlKey) }
        if modifiers.contains(.shift) { out |= UInt32(shiftKey) }
        return out
    }

    // MARK: - Persistence

    private static let keyCodeDefault = "globalShortcutKeyCode"
    private static let modifiersDefault = "globalShortcutModifiers"

    /// Reads the saved shortcut, or nil if none is set or the stored data no longer makes
    /// sense. Anything unreadable is treated as "not set" rather than migrated or repaired —
    /// the cost of a wrong guess here is a hotkey the user didn't ask for.
    static func load(from defaults: UserDefaults = .standard) -> GlobalShortcut? {
        guard defaults.object(forKey: keyCodeDefault) != nil,
              defaults.object(forKey: modifiersDefault) != nil else { return nil }

        let rawKey = defaults.integer(forKey: keyCodeDefault)
        let rawModifiers = defaults.integer(forKey: modifiersDefault)
        guard let keyCode = UInt16(exactly: rawKey), rawModifiers >= 0 else { return nil }

        // Runs through init? so a stored value that fails today's validation is rejected
        // rather than trusted.
        return GlobalShortcut(keyCode: keyCode,
                              modifiers: NSEvent.ModifierFlags(rawValue: UInt(rawModifiers)))
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(Int(keyCode), forKey: Self.keyCodeDefault)
        defaults.set(Int(modifiers.rawValue), forKey: Self.modifiersDefault)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: keyCodeDefault)
        defaults.removeObject(forKey: modifiersDefault)
    }

    // MARK: - Key names

    /// Keys whose glyph can't be derived from the keyboard layout (arrows, return, and
    /// friends). Everything else is resolved live against the user's actual layout, so
    /// that a French or Dvorak keyboard shows the key the user is really pressing.
    private static let namedKeys: [UInt16: String] = [
        UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥", UInt16(kVK_Space): "Space",
        UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    ]

    static func keyName(for keyCode: UInt16) -> String {
        if let named = namedKeys[keyCode] { return named }
        if let character = layoutCharacter(for: keyCode) { return character.uppercased() }
        return "Key \(keyCode)"
    }

    /// Asks the current keyboard layout what character a key code produces, unmodified.
    /// Returns nil for keys that produce nothing printable.
    private static func layoutCharacter(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(layout,
                                  keyCode,
                                  UInt16(kUCKeyActionDisplay),
                                  0, // no modifiers: we want the key's own character
                                  UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState,
                                  characters.count,
                                  &length,
                                  &characters)
        }

        guard status == noErr, length > 0 else { return nil }
        let name = String(utf16CodeUnits: characters, count: length)
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
    }
}
