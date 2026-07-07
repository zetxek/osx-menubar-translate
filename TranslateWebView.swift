//
//  TranslateWebView.swift
//  Translate Menu
//
//  Created by Adrián Moreno Peña on 17/11/2024.
//  Copyright © 2024 Adrian Moreno Peña. All rights reserved.
//

import Cocoa
import WebKit

class TranslateWebView: WKWebView {

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func resignFirstResponder() -> Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch flags {
        case [.command] where event.characters == "c":
            copy(nil)
            return

        case [.command] where event.characters == "v":
            paste(nil)
            return

        case [.command] where event.characters == "a":
            selectAll(nil)
            return

        default:
            super.keyDown(with: event)
        }
    }

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

    @IBAction func copy(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

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

            if let selectedText = selectedText as? String {
                pasteboard.setString(selectedText, forType: .string)
            }
        }
    }

    @IBAction func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard let copiedString = pasteboard.string(forType: .string) else { return }

        // JSON-encode to get a valid JS string literal (handles quotes, backslashes, newlines)
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
