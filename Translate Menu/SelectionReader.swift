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

import ApplicationServices
import Cocoa

/// Reads the text currently selected in whatever app is frontmost.
///
/// The only part of the app that touches Accessibility. It reads via the AX API and never
/// touches the pasteboard — the alternative (synthesising cmd+C) would overwrite whatever
/// the user had copied, and a spike confirmed AX covers native *and* Chromium apps, so
/// there is nothing to gain from it.
///
/// Requires Accessibility permission, which is why the feature is opt-in. Without the
/// grant every AX call fails quietly rather than erroring, so this type reports "no
/// selection" and the popover simply opens empty — the app's behaviour before the feature.
enum SelectionReader {

    /// Beyond this the text is not a "selection" any more, and it has to survive being
    /// placed in the Google Translate URL. A cmd+A on a long page would otherwise build an
    /// absurd URL for text nobody meant to translate.
    static let maximumLength = 2000

    /// Whether macOS currently allows this app to read other apps' UI.
    static var isPermitted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to prompt for Accessibility. The prompt is shown at most once per app;
    /// afterwards the user must go to System Settings themselves, which is why callers
    /// should also offer `openSettingsPane()`.
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettingsPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The frontmost app's selected text, or nil if there isn't any worth translating.
    ///
    /// Returns nil rather than throwing on every failure path: a missing permission, an
    /// element with no selection, and a non-text element are all "open empty" as far as
    /// the caller is concerned, and none of them is worth interrupting the user over.
    static func readSelection() -> String? {
        guard isPermitted else { return nil }

        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            // If we are frontmost there is no other app's selection to read, and reading
            // our own popover would translate the translation.
            return nil
        }

        let app = AXUIElementCreateApplication(front.processIdentifier)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused
        else { return nil }

        var selection: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement,
                                            kAXSelectedTextAttribute as CFString,
                                            &selection) == .success,
              let text = selection as? String
        else { return nil }

        return clean(text)
    }

    /// Tidies a raw AX selection into something worth putting in a translate URL.
    ///
    /// Split out from the AX plumbing above so it can be tested without a live session:
    /// this is where the fiddly cases live, and the AX call around it cannot be unit tested.
    static func clean(_ raw: String) -> String? {
        // Chromium substitutes U+FFFC (object replacement) for inline images, so a page
        // selection arrives peppered with them.
        let withoutObjects = raw.replacingOccurrences(of: "\u{FFFC}", with: " ")

        // Collapse the newlines and runs of spaces that come with any real-world selection.
        let collapsed = withoutObjects
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maximumLength))
    }
}
