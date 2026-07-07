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
        statusItem = NSStatusBar.system.statusItem(withLength: 32)

        let image = NSImage(named: "TranslateStatusBarButtonImage")
        image?.isTemplate = true

        if let button = statusItem.button {
            button.image = image
            button.action = #selector(statusItemButtonActivated(sender:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        popover.contentViewController = translateViewController
        popover.behavior = .applicationDefined

        // ponytail: geometry check keeps IME candidate clicks (which overlap the
        // popover but belong to the input-method process) from dismissing it
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [unowned self] event in
            guard self.popover.isShown,
                  let frame = self.popover.contentViewController?.view.window?.frame,
                  !NSMouseInRect(NSEvent.mouseLocation, frame, false)
            else { return }

            self.closePopover(sender: event)
        }

        NSApplication.shared.servicesProvider = self
    }

    @IBAction
    func statusItemButtonActivated(sender: AnyObject?) {
        // Decide from the triggering event, not live mouse state — by the time
        // this runs the button may already be released and a state read misses the click.
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseDown
            || event?.modifierFlags.contains(.control) == true

        if isSecondary {
            statusItem.menu = self.statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown {
            closePopover(sender: sender)
        } else {
            showPopover(sender: sender)
        }
    }

    func showPopover(sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        DispatchQueue.main.async {
            self.popover.contentViewController?.view.window?.orderFrontRegardless()
            self.translateViewController.focusInputIfPossible()
        }

        eventMonitor?.start()
    }

    func closePopover(sender: AnyObject?) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }

    @objc
    func translateService(_ pasteboard: NSPasteboard,
                          userData: String,
                          error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string) else { return }

        translateViewController.loadText(text: text)
        showPopover(sender: nil)
    }

    @IBAction
    func quitApp(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }

    @IBAction
    func aboutMenuActivated(sender: AnyObject?) {
        NSWorkspace.shared.open(URL(string: "https://github.com/zetxek/osx-menubar-translate")!)
    }
}
