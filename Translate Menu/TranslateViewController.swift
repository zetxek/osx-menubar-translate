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
import WebKit

/// popover 的內容控制器：承載一個載入 Google 翻譯網頁的 WKWebView。
/// WebView 只載入一次、App 存活期間常駐——用約 100MB 記憶體換「點圖示秒開」，
/// 不必每次開啟都等 2-3 秒重新載入。
class TranslateViewController: NSViewController, WKNavigationDelegate {
    @IBOutlet var webView: TranslateWebView!
    @IBOutlet var webViewContainer: NSView!
    /// 頁面載入中的轉圈指示器
    @IBOutlet var progressIndicator: NSProgressIndicator!

    /// 首頁是否已載入過（只在第一次顯示時載入）
    var urlLoaded = false
    /// 冷啟動暫存區：view 還沒載入時就收到的翻譯文字，先存這裡，
    /// 等 viewWillAppear 再補載。沒有它，冷啟動後第一次服務呼叫的文字會被丟掉
    private var pendingText: String?
    /// Google 翻譯網址，text 參數帶要翻譯的文字
    let defaultUrl = "https://translate.google.com?text="

    override func viewWillAppear() {
        super.viewWillAppear()

        // 只有第一次顯示才載入頁面；之後開關 popover 都沿用已載入的頁面。
        // 轉圈指示器也只在這裡開——每次顯示都開的話，沒有導航去關它，會永遠轉下去
        if !urlLoaded {
            urlLoaded = true
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
            webView.navigationDelegate = self
            webView.load(getTranslateURL(textToTranslate: pendingText ?? ""))
            pendingText = nil
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // 每次 popover 顯示都重新把焦點放進輸入框，使用者可以直接打字
        focusInputIfPossible()
    }

    /// 頁面載入完成：收轉圈、把焦點放進輸入框。
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideProgress()

        // 稍等 0.1 秒讓頁面的 JS 初始化完，focus 才抓得到輸入框
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.focusInputIfPossible()
        }
    }

    /// 載入中途失敗（例如斷網）：收轉圈，不能讓它永遠轉下去。
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        hideProgress()
    }

    /// 連線階段就失敗（例如 DNS 解析不到、新載入取消舊載入）：同樣收轉圈。
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        hideProgress()
    }

    private func hideProgress() {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
    }

    /// 載入一段要翻譯的文字（「服務」選單的入口會呼叫）。
    /// view 還沒載入時（冷啟動）先暫存，等 viewWillAppear 再一起載。
    public func loadText(text: String) {
        guard isViewLoaded, webView != nil else {
            pendingText = text
            return
        }

        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        webView.load(getTranslateURL(textToTranslate: text))
    }

    /// 把要翻譯的文字組成 Google 翻譯網址。
    /// 額外把 `;/?:@&=+$, ` 等字元也做百分比編碼——這些字元在 query 值裡雖然「合法」，
    /// 但會被當成參數分隔符號，不編碼的話文字會在 `&` 或 `+` 處被截斷
    public func getTranslateURL(textToTranslate: String) -> URLRequest {
        var allowedQueryParamAndKey = CharacterSet.urlQueryAllowed
        allowedQueryParamAndKey.remove(charactersIn: ";/?:@&=+$, ")
        let sanitizedInput = textToTranslate.addingPercentEncoding(withAllowedCharacters: allowedQueryParamAndKey) ?? textToTranslate

        let urlString = "\(defaultUrl)\(sanitizedInput)"
        let url = URL(string: urlString) ?? URL(string: defaultUrl)!
        return URLRequest(url: url)
    }

    /// 把鍵盤焦點交給網頁裡的翻譯輸入框（分兩層：先讓視窗成為 key window
    /// 並把 first responder 給 WebView，再用 JS 把游標放進頁面的輸入框）。
    public func focusInputIfPossible() {
        guard isViewLoaded, let window = view.window else { return }

        window.level = .normal
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)

        // 等 0.05 秒讓視窗焦點先穩定，再注入 JS 抓輸入框
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.focusWebInputElement()
        }
    }

    /// 用 JS 在頁面裡找輸入框並 focus。選擇器由具體到寬鬆排列，
    /// Google 翻譯改版換 DOM 結構時比較不容易全部失效。
    private func focusWebInputElement() {
        guard view.window != nil else { return }

        let javascript = """
        (function() {
            const selectors = [
                'textarea',
                'input[type="text"]',
                '[contenteditable="true"]',
                'div[contenteditable="true"]',
                'textarea[aria-label]',
                'c-wiz textarea'
            ];

            for (const selector of selectors) {
                const el = document.querySelector(selector);
                if (el) {
                    el.focus();
                    if (typeof el.click === 'function') {
                        el.click();
                    }
                    return 'focused';
                }
            }

            return 'not_found';
        })();
        """

        webView.evaluateJavaScript(javascript) { _, error in
            if let error = error {
                NSLog("TranslateViewController: focusWebInputElement error: \(error.localizedDescription)")
            }
        }
    }
}
