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

import XCTest
@testable import Translate_Menu

/// Runs against real `NSPasteboard` instances rather than a stub: the whole point of the
/// type is how AppKit's own pasteboard behaves with each flavour, which a fake would only
/// re-state as an assumption.
final class PasteboardTextTests: XCTestCase {

    /// A private, uniquely named pasteboard per test, so these never touch the user's
    /// clipboard and cannot interfere with each other.
    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasteboardTextTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    private func rtfData(_ string: String) throws -> Data {
        let attributed = NSAttributedString(string: string)
        return try XCTUnwrap(attributed.rtf(from: NSRange(location: 0, length: attributed.length),
                                            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]))
    }

    func test_read_returnsPlainString() {
        let pasteboard = makePasteboard()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("Hola mundo", forType: .string)

        XCTAssertEqual(PasteboardText.read(from: pasteboard), "Hola mundo")
    }

    /// Pins down something surprising that this test suite established: asking a
    /// rich-text-only pasteboard for `.string` **succeeds**, because AppKit coerces it.
    /// So RTF-only selections were never the reason the service came up empty — worth
    /// recording, or the next person will "fix" that non-problem again.
    func test_read_readsARichTextOnlyPasteboard() throws {
        let pasteboard = makePasteboard()
        pasteboard.declareTypes([.rtf], owner: nil)
        pasteboard.setData(try rtfData("El perro corre"), forType: .rtf)

        XCTAssertEqual(pasteboard.string(forType: .string), "El perro corre",
                       "AppKit coerces rich text when asked for .string")
        XCTAssertEqual(PasteboardText.read(from: pasteboard), "El perro corre")
    }

    func test_read_prefersPlainStringOverRichText() throws {
        let pasteboard = makePasteboard()
        pasteboard.declareTypes([.string, .rtf], owner: nil)
        pasteboard.setString("plain", forType: .string)
        pasteboard.setData(try rtfData("rich"), forType: .rtf)

        XCTAssertEqual(PasteboardText.read(from: pasteboard), "plain")
    }

    func test_read_returnsNilForEmptyPasteboard() {
        XCTAssertNil(PasteboardText.read(from: makePasteboard()))
    }

    func test_read_returnsNilForWhitespaceOnlySelection() {
        let pasteboard = makePasteboard()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("   \n\t ", forType: .string)

        XCTAssertNil(PasteboardText.read(from: pasteboard))
    }

    func test_read_fallsBackWhenThePlainFlavourIsBlank() throws {
        let pasteboard = makePasteboard()
        pasteboard.declareTypes([.string, .rtf], owner: nil)
        pasteboard.setString("  ", forType: .string)
        pasteboard.setData(try rtfData("con contenido"), forType: .rtf)

        XCTAssertEqual(PasteboardText.read(from: pasteboard), "con contenido")
    }

    func test_read_preservesNonLatinText() {
        let pasteboard = makePasteboard()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("日本語のテキスト", forType: .string)

        XCTAssertEqual(PasteboardText.read(from: pasteboard), "日本語のテキスト")
    }

    func test_typeNames_listsWhatArrived() {
        let pasteboard = makePasteboard()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("x", forType: .string)

        XCTAssertTrue(PasteboardText.typeNames(of: pasteboard).contains(NSPasteboard.PasteboardType.string.rawValue))
    }

    func test_typeNames_isEmptyForEmptyPasteboard() {
        XCTAssertTrue(PasteboardText.typeNames(of: makePasteboard()).isEmpty)
    }
}
