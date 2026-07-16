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

/// A field that records one keyboard shortcut.
///
/// Click it, press a combination, and it reports a `GlobalShortcut`. It only turns
/// keystrokes into values — it doesn't save them or register anything, so it can be
/// reasoned about without involving Carbon or UserDefaults.
final class ShortcutRecorderView: NSView {
    /// Called with a valid shortcut. Not called for rejected combinations.
    var onRecord: ((GlobalShortcut) -> Void)?

    /// The shortcut to display when not recording.
    var shortcut: GlobalShortcut? {
        didSet { needsDisplay = true }
    }

    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    /// Set when the user pressed something without ⌘/⌥/⌃, so the view can explain itself
    /// rather than appearing to ignore the keystroke.
    private var showsModifierHint = false {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        showsModifierHint = false
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Escape abandons recording and leaves the existing shortcut alone. Recording it
        // would be a poor trade: ⎋ is how you back out of things everywhere else in macOS.
        if event.keyCode == UInt16(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return
        }

        guard let recorded = GlobalShortcut(keyCode: event.keyCode, modifiers: event.modifierFlags) else {
            // Rejected: no ⌘/⌥/⌃. Stay in recording mode so the user can simply try again.
            showsModifierHint = true
            NSSound.beep()
            return
        }

        showsModifierHint = false
        shortcut = recorded
        onRecord?(recorded)
        window?.makeFirstResponder(nil)
    }

    /// Modifier-only presses shouldn't be recorded, but the view should look alive while
    /// the user holds ⌘ waiting to pick a key.
    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return }
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let rounded = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)

        NSColor.controlBackgroundColor.setFill()
        rounded.fill()

        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        rounded.lineWidth = isRecording ? 2 : 1
        rounded.stroke()

        let style = NSMutableParagraphStyle()
        style.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: textColour,
            .paragraphStyle: style,
        ]

        let text = displayText as NSString
        let size = text.size(withAttributes: attributes)
        let origin = NSRect(x: 0,
                            y: (bounds.height - size.height) / 2,
                            width: bounds.width,
                            height: size.height)
        text.draw(in: origin, withAttributes: attributes)
    }

    private var textColour: NSColor {
        if showsModifierHint { return .systemRed }
        if isRecording { return .secondaryLabelColor }
        return shortcut == nil ? .secondaryLabelColor : .labelColor
    }

    private var displayText: String {
        if showsModifierHint { return "Add ⌘, ⌥ or ⌃" }
        if isRecording {
            // Echo the modifiers already held, so the field responds while the user decides.
            let held = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
            if !held.isEmpty, let partial = GlobalShortcut(keyCode: 0, modifiers: held) {
                return String(partial.displayString.dropLast(GlobalShortcut.keyName(for: 0).count))
            }
            return "Press a shortcut…"
        }
        return shortcut?.displayString ?? "Click to record"
    }
}
