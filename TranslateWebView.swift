//
//  TranslateWebView.swift
//  Translate Menu
//
//  Created by Adrián Moreno Peña on 17/11/2024.
//  Copyright © 2024 Adrian Moreno Peña. All rights reserved.
//

import Cocoa
import WebKit

/// Custom WKWebView that intercepts cmd+C / cmd+V / cmd+A and bridges them into the page via JS.
///
/// Why this is needed: a menu bar app (LSUIElement) has no main menu, so there is no Edit
/// menu for the system copy/paste shortcuts to route through — pressing them in the WebView
/// does nothing. Intercept them in keyDown and perform the equivalent operation via JavaScript.
class TranslateWebView: WKWebView {

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func resignFirstResponder() -> Bool {
        true
    }

    /// Intercepts cmd+C / cmd+V / cmd+A; every other key (including IME composition)
    /// falls through to WebKit's native handling.
    /// Subtracts capsLock and lowercases the character before matching — otherwise all
    /// three shortcuts break while Caps Lock is on.
    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        let key = event.charactersIgnoringModifiers?.lowercased()

        switch flags {
        case [.command] where key == "c":
            copy(nil)
            return

        case [.command] where key == "v":
            paste(nil)
            return

        case [.command] where key == "a":
            selectAll(nil)
            return

        default:
            super.keyDown(with: event)
        }
    }

    /// Select all: selects the focused input's contents if there is one, otherwise the whole page.
    @IBAction override func selectAll(_ sender: Any?) {
        let javascript = """
        (function() {
            const active = document.activeElement;
            if (active && typeof active.select === 'function') {
                active.select();
                return 'selected_input';
            }

            const selection = window.getSelection();
            const range = document.createRange();
            range.selectNodeContents(document.body);
            selection.removeAllRanges();
            selection.addRange(range);
            return 'selected_document';
        })();
        """

        evaluateJavaScript(javascript) { _, error in
            if let error = error {
                NSLog("TranslateWebView selectAll error: \(error.localizedDescription)")
            }
        }
    }

    /// Copy: reads the page's current selection via JS and writes it to the system pasteboard.
    /// Input fields (textarea) need selectionStart/End; ordinary page text uses getSelection().
    /// The pasteboard is only cleared once there is text to replace it with — clearing up
    /// front would destroy the user's clipboard whenever the JS fails or nothing is selected.
    @IBAction func copy(_ sender: Any?) {
        let script = """
        (function() {
            const active = document.activeElement;
            if (active && typeof active.value === 'string') {
                const start = active.selectionStart ?? 0;
                const end = active.selectionEnd ?? 0;
                return active.value.substring(start, end);
            }
            return window.getSelection().toString();
        })();
        """

        evaluateJavaScript(script) { selectedText, error in
            if let error = error {
                NSLog("TranslateWebView copy error: \(error.localizedDescription)")
                return
            }

            guard let selectedText = selectedText as? String, !selectedText.isEmpty else { return }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(selectedText, forType: .string)
        }
    }

    /// Paste: inserts the system pasteboard's text into the page's currently focused input.
    @IBAction func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard let copiedString = pasteboard.string(forType: .string) else { return }

        // JSON-encode to get a valid JS string literal — handles quotes, backslashes and
        // newlines in one shot. The old hand-rolled escaping missed cases, which made the
        // injected JS a syntax error and silently broke paste entirely.
        guard let data = try? JSONSerialization.data(withJSONObject: [copiedString]),
              let json = String(data: data, encoding: .utf8) else { return }
        let literal = String(json.dropFirst().dropLast())

        let javascript = """
        (function() {
            const active = document.activeElement;
            if (active) {
                active.focus();
            }
            document.execCommand('insertText', false, \(literal));
        })();
        """

        evaluateJavaScript(javascript) { _, error in
            if let error = error {
                NSLog("TranslateWebView paste error: \(error.localizedDescription)")
            }
        }
    }
}
