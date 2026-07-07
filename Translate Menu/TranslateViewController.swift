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

class TranslateViewController: NSViewController, WKNavigationDelegate {
    @IBOutlet var webView: TranslateWebView!
    @IBOutlet var webViewContainer: NSView!
    @IBOutlet var progressIndicator: NSProgressIndicator!

    var urlLoaded = false
    private var pendingText: String?
    let defaultUrl = "https://translate.google.com?text="

    override func viewWillAppear() {
        super.viewWillAppear()

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
        focusInputIfPossible()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideProgress()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.focusInputIfPossible()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        hideProgress()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        hideProgress()
    }

    private func hideProgress() {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
    }

    public func loadText(text: String) {
        guard isViewLoaded, webView != nil else {
            pendingText = text
            return
        }

        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        webView.load(getTranslateURL(textToTranslate: text))
    }

    public func getTranslateURL(textToTranslate: String) -> URLRequest {
        var allowedQueryParamAndKey = CharacterSet.urlQueryAllowed
        allowedQueryParamAndKey.remove(charactersIn: ";/?:@&=+$, ")
        let sanitizedInput = textToTranslate.addingPercentEncoding(withAllowedCharacters: allowedQueryParamAndKey) ?? textToTranslate

        let urlString = "\(defaultUrl)\(sanitizedInput)"
        let url = URL(string: urlString) ?? URL(string: defaultUrl)!
        return URLRequest(url: url)
    }

    public func focusInputIfPossible() {
        guard isViewLoaded, let window = view.window else { return }

        window.level = .normal
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.focusWebInputElement()
        }
    }

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
