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

import Foundation

/// The app's stored preferences.
///
/// Deliberately a thin, injectable wrapper rather than reads scattered through the code:
/// the defaults it touches decide whether the app asks for Accessibility at all, so it is
/// worth being able to test the exact answer it gives.
enum Preferences {
    private static let translateSelectionKey = "translateSelection"

    /// Whether pressing the global shortcut should translate the current selection.
    ///
    /// **Defaults to false, and that matters.** Reading the selection needs Accessibility
    /// permission, and nobody should be prompted for that because they installed a
    /// translate window. `UserDefaults.bool(forKey:)` already returns false for a missing
    /// or non-boolean value, which is the behaviour we want: anything unreadable means off.
    static func translateSelection(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: translateSelectionKey)
    }

    static func setTranslateSelection(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: translateSelectionKey)
    }
}
