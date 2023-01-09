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

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet weak var statusMenu: NSMenu!
    
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    let translateViewController = TranslateViewController(nibName: "TranslateViewController", bundle: nil)
    var eventMonitor: EventMonitor?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("MenuTranslate: starting")
        self.statusItem = NSStatusBar.system.statusItem(withLength: 32)
        
        let image = NSImage(named: "TranslateStatusBarButtonImage")
        image?.isTemplate = true
        
        if let button = statusItem.button {
            button.image = image
            button.action = #selector(statusItemButtonActivated(sender:))
            
            button.sendAction(on: [ .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp ])
        }
        
        popover.contentViewController = translateViewController
        
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [unowned self] event in
            if self.popover.isShown {
                self.closePopover(sender: event)
            }
        }
        
        eventMonitor?.start()
        
        NSApplication.shared.servicesProvider = self
        NSLog("MenuTranslate: started")

    }
    
    @IBAction
    func statusItemButtonActivated(sender: AnyObject?) {
        let buttonMask = NSEvent.pressedMouseButtons
        var primaryDown = ((buttonMask & (1 << 0)) != 0)
        var secondaryDown = ((buttonMask & (1 << 1)) != 0)
        
        // Treat a control-click as a secondary click
        if (primaryDown && (NSEvent.modifierFlags == NSEvent.ModifierFlags.control)) {
            primaryDown = false;
            secondaryDown = true;
        }
        
        if (primaryDown) {
            if popover.isShown {
                closePopover(sender: sender)
            } else {
                showPopover(sender: sender)
            }
        } else if (secondaryDown) {
            statusItem.menu = self.statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        }
    }
    
    func showPopover(sender: AnyObject?, keyword : String? = nil) {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        }
        eventMonitor?.start()
    }
    
    func closePopover(sender: AnyObject?) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }
    
    @objc func translateService(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let text = pasteboard.string(forType: .string)
        NSLog("MenuTranslate: handling service invocation: " + text!)
        translateViewController.loadText(text: text!)
        self.showPopover(sender: nil, keyword: text)
    }
    
    @IBAction func quitApp(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }
}
