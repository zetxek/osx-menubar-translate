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

/// The Settings window. Built in code rather than a xib: it is one row, and the recorder
/// is a custom view that a xib could not describe anyway.
///
/// Owns no behaviour of its own — it wires the recorder to persistence and to the caller's
/// re-registration, and reports back whatever that returns.
final class SettingsWindowController: NSWindowController {
    /// Asked to apply a newly recorded shortcut. Returns an error message to display, or
    /// nil on success. The controller doesn't know how registration works; it just shows
    /// the outcome.
    private let applyShortcut: (GlobalShortcut) -> String?
    /// Asked to remove the shortcut entirely.
    private let clearShortcut: () -> Void

    private let recorder = ShortcutRecorderView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let selectionCheckbox = NSButton(checkboxWithTitle: "Translate selected text", target: nil, action: nil)
    private let permissionLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton(title: "Open System Settings", target: nil, action: nil)

    init(shortcut: GlobalShortcut?,
         applyShortcut: @escaping (GlobalShortcut) -> String?,
         clearShortcut: @escaping () -> Void) {
        self.applyShortcut = applyShortcut
        self.clearShortcut = clearShortcut

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 250),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        recorder.shortcut = shortcut
        buildLayout()
        refreshStatus(message: nil)
        refreshSelectionSection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — this window is built in code")
    }

    private func buildLayout() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Global shortcut")
        title.font = .boldSystemFont(ofSize: 13)

        let explanation = NSTextField(labelWithString: "Opens the translate window from any app.")
        explanation.font = .systemFont(ofSize: 11)
        explanation.textColor = .secondaryLabelColor

        recorder.onRecord = { [weak self] shortcut in
            guard let self else { return }
            if let error = self.applyShortcut(shortcut) {
                // Registration failed. Show the reason and drop the field back to whatever
                // is actually registered, so the UI never claims a shortcut that isn't live.
                self.refreshStatus(message: error, isError: true)
                self.recorder.shortcut = GlobalShortcut.load()
            } else {
                self.refreshStatus(message: nil)
            }
        }

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clear))
        clearButton.bezelStyle = .rounded

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2

        selectionCheckbox.target = self
        selectionCheckbox.action = #selector(toggleTranslateSelection)

        let selectionExplanation = NSTextField(labelWithString: "Translate whatever is selected when you press the shortcut.")
        selectionExplanation.font = .systemFont(ofSize: 11)
        selectionExplanation.textColor = .secondaryLabelColor

        permissionLabel.font = .systemFont(ofSize: 11)
        permissionLabel.lineBreakMode = .byWordWrapping
        permissionLabel.maximumNumberOfLines = 3

        permissionButton.target = self
        permissionButton.action = #selector(openAccessibilitySettings)
        permissionButton.bezelStyle = .rounded
        permissionButton.controlSize = .small

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2

        let divider = NSBox()
        divider.boxType = .separator

        let views: [NSView] = [title, explanation, recorder, clearButton, statusLabel,
                               divider, selectionCheckbox, selectionExplanation,
                               permissionLabel, permissionButton]
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),

            explanation.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            explanation.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),

            recorder.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            recorder.topAnchor.constraint(equalTo: explanation.bottomAnchor, constant: 12),
            recorder.widthAnchor.constraint(equalToConstant: 180),
            recorder.heightAnchor.constraint(equalToConstant: 28),

            clearButton.leadingAnchor.constraint(equalTo: recorder.trailingAnchor, constant: 8),
            clearButton.centerYAnchor.constraint(equalTo: recorder.centerYAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            statusLabel.topAnchor.constraint(equalTo: recorder.bottomAnchor, constant: 10),

            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            divider.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),

            selectionCheckbox.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            selectionCheckbox.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 12),

            selectionExplanation.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            selectionExplanation.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            selectionExplanation.topAnchor.constraint(equalTo: selectionCheckbox.bottomAnchor, constant: 2),

            permissionLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            permissionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            permissionLabel.topAnchor.constraint(equalTo: selectionExplanation.bottomAnchor, constant: 8),

            permissionButton.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            permissionButton.topAnchor.constraint(equalTo: permissionLabel.bottomAnchor, constant: 6),
        ])
    }

    /// The checkbox stores the user's *intent*; whether it can actually work depends on a
    /// permission macOS controls. Those are tracked separately on purpose — a ticked box
    /// that silently does nothing is the failure this avoids.
    @objc
    private func toggleTranslateSelection() {
        let wantsIt = selectionCheckbox.state == .on
        Preferences.setTranslateSelection(wantsIt)

        if wantsIt && !SelectionReader.isPermitted {
            // Only prompt when the user asks for the feature — never on launch.
            SelectionReader.requestPermission()
        }
        refreshSelectionSection()
    }

    @objc
    private func openAccessibilitySettings() {
        SelectionReader.openSettingsPane()
    }

    private func refreshSelectionSection() {
        selectionCheckbox.state = Preferences.translateSelection() ? .on : .off

        let wantsIt = Preferences.translateSelection()
        let permitted = SelectionReader.isPermitted

        // Only nag when the user has actually asked for the feature.
        let needsPermission = wantsIt && !permitted
        permissionLabel.isHidden = !needsPermission
        permissionButton.isHidden = !needsPermission

        if needsPermission {
            permissionLabel.stringValue = "Reading the selection needs Accessibility permission. "
                + "Allow “Translate Menu” in System Settings, then it will work. "
                + "Until then the shortcut opens an empty window."
            permissionLabel.textColor = .systemOrange
        }
    }

    @objc
    private func clear() {
        clearShortcut()
        recorder.shortcut = nil
        refreshStatus(message: nil)
    }

    private func refreshStatus(message: String?, isError: Bool = false) {
        if let message {
            statusLabel.stringValue = message
            statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
        } else if recorder.shortcut == nil {
            statusLabel.stringValue = "No shortcut set."
            statusLabel.textColor = .secondaryLabelColor
        } else {
            statusLabel.stringValue = ""
        }
    }

    /// Shows the window and brings it forward.
    ///
    /// Getting this in front is fiddlier than it looks. A menu bar app is not the active
    /// app, so the window opens behind whatever the user was in unless we activate first —
    /// and `activate(ignoringOtherApps:)` has had no effect since macOS 14, so relying on
    /// it alone means the window opens invisibly behind the browser. Hence all three:
    /// the modern activate on 14+, the old one below it, and orderFrontRegardless() to
    /// force the window up even if activation is refused (which is what the popover does).
    func present() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        refreshSelectionSection()
    }
}

extension SettingsWindowController: NSWindowDelegate {
    /// Granting Accessibility happens in System Settings, outside this app, so the user
    /// comes back to a window whose warning is stale. Re-check whenever it regains focus.
    func windowDidBecomeKey(_ notification: Notification) {
        refreshSelectionSection()
    }
}
