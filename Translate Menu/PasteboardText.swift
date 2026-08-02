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

import Cocoa

/// Pulls translatable text out of the pasteboard macOS hands to the Services entry.
///
/// `.string` alone covers more than it looks like it does — AppKit coerces rich text, so
/// even an RTF-only pasteboard answers it (pinned down in PasteboardTextTests). The
/// fallback below is for what it does *not* coerce, and the point of the type is that a
/// pasteboard it cannot read is reported rather than silently treated as "no selection".
/// Split out from AppDelegate so the decoding can be tested against a real pasteboard.
enum PasteboardText {

    /// The selection as plain text, or nil if the pasteboard carries nothing usable.
    ///
    /// Whitespace-only content counts as nothing: translating it would just open Google
    /// Translate on a blank query, which is what "no selection" already does.
    static func read(from pasteboard: NSPasteboard) -> String? {
        if let plain = pasteboard.string(forType: .string), !isBlank(plain) {
            return plain
        }

        // One call covers RTF, RTFD and HTML: NSAttributedString declares all of them as
        // readable types, so there is no need to hand-decode each flavour.
        if let rich = pasteboard.readObjects(forClasses: [NSAttributedString.self]) as? [NSAttributedString] {
            for candidate in rich where !isBlank(candidate.string) {
                return candidate.string
            }
        }

        return nil
    }

    /// The pasteboard's type identifiers, for logging a failed read. Callers use this to
    /// make "it opened empty" reportable instead of a dead end.
    static func typeNames(of pasteboard: NSPasteboard) -> [String] {
        pasteboard.types?.map(\.rawValue) ?? []
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
