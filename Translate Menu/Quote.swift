/*
* Copyright (c) 2015 Razeware LLC
*
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

import Foundation

struct Quote {
  let text: String
  let author: String

  static let all: [Quote] = [
    Quote(text: "Never put off until tomorrow what you can do the day after tomorrow.", author: "Mark Twain"),
    Quote(text: "Efficiency is doing better what is already being done.", author: "Peter Drucker"),
    Quote(text: "To infinity and beyond!", author: "Buzz Lightyear"),
    Quote(text: "May the Force be with you.", author: "Han Solo"),
    Quote(text: "Simplicity is the ultimate sophistication", author: "Leonardo da Vinci"),
    Quote(text: "It’s not just what it looks like and feels like. Design is how it works.", author: "Steve Jobs")
  ]
}

// MARK: - Printable

extension Quote: CustomStringConvertible {
  var description: String {
    return "\"\(text)\" — \(author)"
  }
}