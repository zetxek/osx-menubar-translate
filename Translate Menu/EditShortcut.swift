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

/// The edit commands the WebView handles itself, because nothing else will.
enum EditShortcut {
    case copy
    case paste
    case selectAll
}

/// Decides whether a key event is ⌘C / ⌘V / ⌘A.
///
/// The decision is keyed on the *physical* key (`keyCode`), not on the character it types.
/// `charactersIgnoringModifiers` reports what the active layout produces, so on a Ukrainian
/// layout ⌘C arrives as "с" (Cyrillic es) and a string comparison against "c" never matches.
/// The key code is layout-independent: the key in the C position is `kVK_ANSI_C` whatever
/// the input source. This matters more than usual here because the app is an LSUIElement
/// with no Edit menu — if the WebView does not recognise the shortcut, nothing else will,
/// and the keystroke silently does nothing.
///
/// The character is still accepted as a fallback, for layouts such as Dvorak where the
/// letter lives on a different physical key. Either signal is enough. A nil character
/// string (dead key, IME composition) is fine: the key code carries it.
///
/// Pure on purpose — no window server, no WKWebView — so it can be unit tested in-process.
enum EditShortcutMatcher {

    static func shortcut(keyCode: UInt16,
                         charactersIgnoringModifiers: String?,
                         modifierFlags: NSEvent.ModifierFlags) -> EditShortcut? {
        // Caps Lock is not a chord modifier; leaving it in would break all three shortcuts
        // while it is on. Anything beyond ⌘ alone (⇧⌘C, ⌥⌘C, ⌃⌘C) is some other command.
        let flags = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        guard flags == [.command] else { return nil }

        // The key code is the layout-independent datum. Compared with the repo's existing
         // `UInt16(kVK_ANSI_*)` idiom rather than switching on `Int(keyCode)`: the Carbon
         // constants are not `Int`, so the conversion has to be explicit either way.
         if keyCode == UInt16(kVK_ANSI_C) { return .copy }
         if keyCode == UInt16(kVK_ANSI_V) { return .paste }
         if keyCode == UInt16(kVK_ANSI_A) { return .selectAll }

        switch charactersIgnoringModifiers?.lowercased() {
        case "c": return .copy
        case "v": return .paste
        case "a": return .selectAll
        default: return nil
        }
    }
}
