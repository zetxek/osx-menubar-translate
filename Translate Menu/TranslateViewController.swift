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

class TranslateViewController: NSViewController {
    @IBOutlet var webView: WKWebView!
    @IBOutlet var popOverViewController: NSPopover!
    
    var urlLoaded = false
    let defaultUrl = "https://translate.google.com?text="
    
    override func viewWillAppear() {
        super.viewWillAppear()
        
        NSLog("TranslateViewController: willAppear")
        
        if (!self.urlLoaded) {
            NSLog("TranslateViewController: loadURL")
            self.urlLoaded = true
            webView.load(NSURLRequest(url: NSURL(string: defaultUrl)! as URL) as URLRequest)
        }
    }
    
    public func loadText(text: String){
        NSLog("TranslateViewController, Loading text: " + text)
        if (webView != nil){
            webView.load(getTranslateURL(textToTranslate: text))
        }
    }
    
    public func getTranslateURL(textToTranslate: String) -> URLRequest{
        
        var allowedQueryParamAndKey = NSCharacterSet.urlQueryAllowed
        allowedQueryParamAndKey.remove(charactersIn: ";/?:@&=+$, ")
        let sanitizedInput = textToTranslate.addingPercentEncoding(withAllowedCharacters: allowedQueryParamAndKey) ?? textToTranslate
        
        let urlString = String(format: "%@%@", defaultUrl, sanitizedInput)
        let url = URL(string: urlString)
        return NSURLRequest(url: url ?? URL(string: defaultUrl)!) as URLRequest

    }
}
