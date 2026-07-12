//
//  TranslateWebView.swift
//  Translate Menu
//
//  Created by Adrián Moreno Peña on 17/11/2024.
//  Copyright © 2024 Adrian Moreno Peña. All rights reserved.
//

import Cocoa
import WebKit

/// 自訂 WKWebView：攔截 cmd+C / cmd+V / cmd+A 並用 JS 橋接到網頁內。
///
/// 為什麼需要自己做：選單列 App（LSUIElement）沒有主選單（Edit menu），
/// 系統的複製／貼上快捷鍵沒有選單項目可以路由，在 WebView 裡按了沒反應，
/// 所以在 keyDown 攔下來，自己透過 JavaScript 對頁面執行對應操作。
class TranslateWebView: WKWebView {

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func resignFirstResponder() -> Bool {
        true
    }

    /// 攔截 cmd+C / cmd+V / cmd+A，其餘按鍵（包含輸入法組字）交回 WebKit 原生處理。
    /// 排除 capsLock 並把字元轉小寫比對——否則大寫鎖定開啟時三組快捷鍵全部失效。
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

    /// 全選：焦點在輸入框就選輸入框內容，否則選整頁。
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

    /// 複製：用 JS 取出頁面目前選取的文字，寫進系統剪貼簿。
    /// 輸入框（textarea）的選取要用 selectionStart/End 取，一般網頁文字用 getSelection()。
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

    /// 貼上：把系統剪貼簿的文字插入頁面目前的輸入框。
    @IBAction func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard let copiedString = pasteboard.string(forType: .string) else { return }

        // JSON-encode to get a valid JS string literal (handles quotes, backslashes, newlines)
        // 用 JSON 編碼產生合法的 JS 字串常值——引號、反斜線、換行等所有邊界情況一次處理。
        // 手工跳脫（舊做法）漏掉任何一種字元，注入的 JS 就直接語法錯誤、貼上整個失敗
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
