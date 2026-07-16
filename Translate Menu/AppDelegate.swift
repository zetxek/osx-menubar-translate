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
import ServiceManagement

/// App entry point. Responsible for three things:
/// 1. Creating the menu bar status item, handling left-click (toggle popover) and right-click (show menu)
/// 2. Managing the translate popover's lifecycle (show, close, auto-close on outside click)
/// 3. Registering the macOS Services menu entry so other apps can send selected text here to translate
@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Right-click menu (defined in MainMenu.xib; contains About and Quit)
    @IBOutlet weak var statusMenu: NSMenu!

    /// "Start at Login" toggle. Added in code rather than the xib because it only
    /// exists on macOS 13+, where SMAppService is available.
    private var startAtLoginItem: NSMenuItem?

    /// The status item in the menu bar
    var statusItem: NSStatusItem!
    /// Popover window hosting the translate UI
    let popover = NSPopover()
    /// Translate UI controller. Kept alive for the app's lifetime so the WebView stays
    /// loaded and the popover opens instantly.
    let translateViewController = TranslateViewController(nibName: "TranslateViewController", bundle: nil)
    /// Global mouse click monitor, used to detect clicks outside the popover and auto-close it
    var eventMonitor: EventMonitor?
    /// Registers the user's system-wide shortcut, if they have set one
    private let hotKeyCenter = HotKeyCenter()
    /// Kept alive so the window survives being closed and reopened
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the menu bar icon; isTemplate lets it adapt to light/dark menu bars automatically
        statusItem = NSStatusBar.system.statusItem(withLength: 32)

        let image = NSImage(named: "TranslateStatusBarButtonImage")
        image?.isTemplate = true

        if let button = statusItem.button {
            button.image = image
            button.action = #selector(statusItemButtonActivated(sender:))
            // Fire on mouse-down only: also firing on mouseUp would run the action a second time per click
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        popover.contentViewController = translateViewController
        // Dismissal is controlled entirely in code (not .transient), so system windows such as
        // IME candidate lists stealing focus don't close it
        popover.behavior = .applicationDefined

        // Global monitors only see clicks from other processes. Decide by whether the mouse
        // location falls inside the popover's frame rather than by window identity: IME
        // candidate windows belong to the input-method process and overlap the popover, and
        // clicking a candidate must not dismiss it.
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [unowned self] event in
            guard self.popover.isShown,
                  let frame = self.popover.contentViewController?.view.window?.frame,
                  !NSMouseInRect(NSEvent.mouseLocation, frame, false)
            else { return }

            self.closePopover(sender: event)
        }

        // Version is read from Info.plist at runtime rather than hardcoded in the xib
        // (the xib's "Version" title is just a placeholder)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        statusMenu.item(at: 0)?.title = "Version \(version)"

        // Settings first, so it and Start at Login sit together above the separator,
        // with About/Quit below it. installStartAtLoginItem() inserts relative to the
        // index installSettingsMenuItem() leaves behind, so the order here is load-bearing.
        installSettingsMenuItem()
        installStartAtLoginItem()
        registerSavedShortcut()

        // Register as a Services provider (matches the NSServices declaration in Info.plist)
        NSApplication.shared.servicesProvider = self
    }

    /// Adds "Settings…" to the right-click menu, above About.
    private func installSettingsMenuItem() {
        let item = NSMenuItem(title: "Settings…",
                              action: #selector(showSettings),
                              keyEquivalent: "")
        item.target = self
        // Index 1: directly under the version line, before About and Quit.
        statusMenu.insertItem(item, at: 1)
        statusMenu.insertItem(.separator(), at: 2)
    }

    /// Restores the user's shortcut at launch. There is no default: nothing is registered
    /// until the user chooses a combination, because claiming a global hotkey they never
    /// asked for could silently break one they already use.
    private func registerSavedShortcut() {
        guard let shortcut = GlobalShortcut.load() else { return }
        do {
            try hotKeyCenter.register(shortcut) { [weak self] in
                self?.toggleFromShortcut()
            }
        } catch {
            // Another app may have claimed the combination since it was saved. Leave it in
            // defaults so Settings still shows what the user chose, and say why it is dead.
            NSLog("AppDelegate: could not register \(shortcut.displayString): \(error)")
        }
    }

    /// The shortcut behaves exactly like clicking the menu bar icon.
    private func toggleFromShortcut() {
        if popover.isShown {
            closePopover(sender: nil)
        } else {
            showPopover(sender: nil)
        }
    }

    /// Right-click menu: Settings…
    @objc
    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                shortcut: GlobalShortcut.load(),
                applyShortcut: { [weak self] shortcut in
                    self?.apply(shortcut)
                },
                clearShortcut: { [weak self] in
                    self?.hotKeyCenter.unregister()
                    GlobalShortcut.clear()
                }
            )
        }
        settingsWindowController?.present()
    }

    /// Registers a newly recorded shortcut and saves it. Returns a message to show the
    /// user on failure, or nil on success.
    private func apply(_ shortcut: GlobalShortcut) -> String? {
        do {
            try hotKeyCenter.register(shortcut) { [weak self] in
                self?.toggleFromShortcut()
            }
        } catch {
            // Registration failed, so don't save: defaults must never describe a shortcut
            // that isn't actually live. Put the previous one back if there was one.
            if let previous = GlobalShortcut.load() {
                try? hotKeyCenter.register(previous) { [weak self] in
                    self?.toggleFromShortcut()
                }
            }
            return "\(shortcut.displayString) is already in use by another app."
        }

        shortcut.save()
        return nil
    }

    /// Status item clicked: left-click toggles the popover, right-click (or control+left-click) shows the menu.
    @IBAction
    func statusItemButtonActivated(sender: AnyObject?) {
        // Decide from the triggering event, not live mouse state: when the main thread is busy
        // the action runs late, by which point the button is already released. Reading live
        // state then misses the click entirely — the root cause of the old "sometimes needs
        // two clicks" bug.
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseDown
            || event?.modifierFlags.contains(.control) == true

        if isSecondary {
            // Temporarily attaching the menu then simulating a click is the standard way to make
            // NSStatusItem show a menu. Detach it immediately after, or subsequent left-clicks
            // would open the menu instead of the popover.
            statusItem.menu = self.statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown {
            closePopover(sender: sender)
        } else {
            showPopover(sender: sender)
        }
    }

    /// Shows the popover and hands keyboard focus to the translate input field.
    func showPopover(sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        // A menu bar app isn't normally the active app; it must activate explicitly to receive keyboard input
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // The popover's window doesn't exist until the runloop turn after show(), so defer focus by one hop
        DispatchQueue.main.async {
            self.popover.contentViewController?.view.window?.orderFrontRegardless()
            self.translateViewController.focusInputIfPossible()
        }

        eventMonitor?.start()
    }

    /// Closes the popover and stops the global click monitor (no monitor lingers while unused).
    func closePopover(sender: AnyObject?) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }

    /// macOS Services menu entry point: text selected in another app → "Translate in MenuTranslate" → here.
    /// The system passes the selected text in via the pasteboard.
    @objc
    func translateService(_ pasteboard: NSPasteboard,
                          userData: String,
                          error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string) else { return }

        translateViewController.loadText(text: text)
        showPopover(sender: nil)
    }

    /// Adds the "Start at Login" toggle to the right-click menu, grouped with Settings…
    /// above the separator. Does nothing before macOS 13: SMAppService doesn't exist
    /// there, and the app still deploys back to 12.4. Users on 12.x can add the app to
    /// Login Items in System Settings by hand, which is what this automates.
    private func installStartAtLoginItem() {
        guard #available(macOS 13.0, *) else { return }

        let item = NSMenuItem(title: "Start at Login",
                              action: #selector(toggleStartAtLogin(_:)),
                              keyEquivalent: "")
        item.target = self
        // Index 2: right after "Settings…", before the separator installSettingsMenuItem()
        // left at that index. Assumes installSettingsMenuItem() has already run.
        statusMenu.insertItem(item, at: 2)
        startAtLoginItem = item

        // The state can change outside the app (System Settings > General > Login Items),
        // so refresh it each time the menu opens rather than trusting a cached value.
        statusMenu.delegate = self
    }

    /// Registers or unregisters the app as a login item.
    ///
    /// SMAppService replaces the old login-item helper-bundle dance, and works for any
    /// signed app — App Store distribution is not required, contrary to what this
    /// project previously assumed.
    @available(macOS 13.0, *)
    @objc
    private func toggleStartAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("AppDelegate: could not toggle start at login: \(error.localizedDescription)")
        }
        refreshStartAtLoginItem()
    }

    /// Mirrors the real SMAppService state onto the menu item.
    private func refreshStartAtLoginItem() {
        guard #available(macOS 13.0, *), let item = startAtLoginItem else { return }

        switch SMAppService.mainApp.status {
        case .enabled:
            item.state = .on
            item.title = "Start at Login"
            item.isEnabled = true
        case .requiresApproval:
            // The user has to allow it in System Settings; the app cannot do it for them.
            // Say so, rather than showing an unticked box that appears to do nothing.
            item.state = .off
            item.title = "Start at Login (allow in System Settings)"
            item.isEnabled = true
        default:
            item.state = .off
            item.title = "Start at Login"
            item.isEnabled = true
        }
    }

    /// Right-click menu: Quit.
    @IBAction
    func quitApp(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }

    /// Right-click menu: About — opens the project's GitHub page.
    @IBAction
    func aboutMenuActivated(sender: AnyObject?) {
        NSWorkspace.shared.open(URL(string: "https://github.com/zetxek/osx-menubar-translate")!)
    }
}

extension AppDelegate: NSMenuDelegate {
    /// The login-item state lives in System Settings and can change behind our back,
    /// so re-read it every time the menu is about to be shown.
    func menuWillOpen(_ menu: NSMenu) {
        refreshStartAtLoginItem()
    }
}
