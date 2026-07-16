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

/// The popover's content controller: hosts a WKWebView loading the Google Translate page.
/// The WebView loads once and stays resident for the app's lifetime — trading ~100MB of
/// memory for an instant open, instead of a 2-3s reload every time.
class TranslateViewController: NSViewController, WKNavigationDelegate {
    @IBOutlet var webView: TranslateWebView!
    @IBOutlet var webViewContainer: NSView!
    /// Spinner shown while the page loads
    @IBOutlet var progressIndicator: NSProgressIndicator!

    /// Whether the initial page has loaded (loads only on first appearance)
    var urlLoaded = false
    /// Cold-start stash: text arriving before the view has loaded is held here and loaded
    /// in viewWillAppear. Without it, the first Services invocation after a cold start
    /// drops its text.
    private var pendingText: String?
    /// Google Translate URL; the text parameter carries the string to translate
    let defaultUrl = "https://translate.google.com?text="

    override func viewWillAppear() {
        super.viewWillAppear()

        // Load the page only on first appearance; later opens reuse the loaded page.
        // The spinner starts only here too — starting it on every appearance would leave it
        // spinning forever, since no navigation follows to stop it.
        if !urlLoaded {
            urlLoaded = true
            installDarkModeStyle()
            // Match the under-page background to the system appearance to avoid a white flash
            // while loading in dark mode
            webView.underPageBackgroundColor = .windowBackgroundColor
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
            webView.navigationDelegate = self
            webView.load(getTranslateURL(textToTranslate: pendingText ?? ""))
            pendingText = nil
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Re-focus the input on every appearance so the user can type immediately
        focusInputIfPossible()
        retranslateIfNeeded()
    }

    /// Recovers translations stuck on "…": closing the popover suspends the WebContent
    /// process (and Google's backend occasionally drops requests), killing the in-flight
    /// translation — and Google's page never retries, so it waits forever. Re-dispatch an
    /// input event on the textarea whenever the popover reappears to force a fresh request.
    /// Does nothing if the input is empty.
    private func retranslateIfNeeded() {
        let js = """
        (function() {
            const t = document.querySelector('textarea');
            if (t && t.value) {
                t.dispatchEvent(new Event('input', {bubbles: true}));
                return 'retranslated';
            }
            return 'empty';
        })();
        """
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                NSLog("TranslateViewController: retranslateIfNeeded error: \(error.localizedDescription)")
            }
        }
    }

    /// Page finished loading: stop the spinner and focus the input.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideProgress()

        // Wait 0.1s for the page's own JS to initialize, otherwise focus can't find the input
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.focusInputIfPossible()
        }
    }

    /// Navigation failed mid-load (e.g. the network dropped): stop the spinner so it doesn't spin forever.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        hideProgress()
    }

    /// Failed during the provisional phase (e.g. DNS failure, or a new load cancelling an
    /// old one): stop the spinner here too.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        hideProgress()
    }

    private func hideProgress() {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
    }

    /// Loads a string to translate (called from the Services menu entry point).
    /// If the view hasn't loaded yet (cold start), stash the text for viewWillAppear.
    public func loadText(text: String) {
        guard isViewLoaded, webView != nil else {
            pendingText = text
            return
        }

        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        webView.load(getTranslateURL(textToTranslate: text))
    }

    /// Builds the Google Translate URL for the given text.
    /// Also percent-encodes `;/?:@&=+$, ` — these are technically legal inside a query
    /// value but act as parameter separators, so leaving them raw truncates the text at
    /// `&` or `+`.
    public func getTranslateURL(textToTranslate: String) -> URLRequest {
        var allowedQueryParamAndKey = CharacterSet.urlQueryAllowed
        allowedQueryParamAndKey.remove(charactersIn: ";/?:@&=+$, ")
        let sanitizedInput = textToTranslate.addingPercentEncoding(withAllowedCharacters: allowedQueryParamAndKey) ?? textToTranslate

        let urlString = "\(defaultUrl)\(sanitizedInput)"
        let url = URL(string: urlString) ?? URL(string: defaultUrl)!
        return URLRequest(url: url)
    }

    /// Injects a system-following dark mode style. Google Translate's web page has no dark
    /// theme of its own (its prefers-color-scheme rules only cover the top account-bar
    /// icons), so invert the whole page with a CSS filter. Wrapping it in an @media query
    /// means WKWebView passes the app's appearance through to the page, so it follows
    /// light/dark switches live with no toggle and no reload. It doesn't depend on Google's
    /// class names (all obfuscated), so it survives their page redesigns.
    private func installDarkModeStyle() {
        let js = """
        const style = document.createElement('style');
        style.textContent = `
        @media (prefers-color-scheme: dark) {
          /* invert(0.88): pure white -> #1f1f1f soft dark grey, pure black text -> #e0e0e0 —
             easier on the eyes than invert(1)'s dead black.
             The background is declared white so the filter inverts it into a dark colour: the
             filter inverts html's own background too, so declaring it dark would flip it back
             to light. */
          html { filter: invert(0.88) hue-rotate(180deg); background: #fff; }
          img, video, iframe { filter: invert(1) hue-rotate(180deg); }
        }`;
        document.documentElement.appendChild(style);
        """
        // atDocumentStart: attach the style before the page paints, so dark mode doesn't flash white first
        webView.configuration.userContentController.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    /// Hands keyboard focus to the page's translate input, in two layers: make the window
    /// key and the WebView first responder, then use JS to put the caret in the page's input.
    public func focusInputIfPossible() {
        guard isViewLoaded, let window = view.window else { return }

        window.level = .normal
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)

        // Wait 0.05s for window focus to settle before injecting the JS that grabs the input
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.focusWebInputElement()
        }
    }

    /// Finds and focuses the page's input via JS. Selectors run specific → loose, so a
    /// Google Translate DOM change is less likely to break all of them at once.
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
