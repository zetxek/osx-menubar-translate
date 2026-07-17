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

import Carbon.HIToolbox
import Foundation

/// Registers one system-wide hotkey and calls a handler when it fires.
///
/// Uses Carbon's RegisterEventHotKey, which looks archaic but is still the right tool:
/// it works inside the App Sandbox with no Accessibility permission, and it *consumes*
/// the keystroke. The obvious alternative, NSEvent.addGlobalMonitorForEvents, needs
/// Accessibility permission and cannot consume the event — the shortcut would open the
/// popover and also type into whatever app the user was in. Apple never shipped a modern
/// replacement for this API.
///
/// The only type that talks to Carbon's hotkey APIs. `GlobalShortcut` and
/// `ShortcutRecorderView` also import `Carbon.HIToolbox`, but only for its keycode and
/// modifier constants — this is the only one that calls `RegisterEventHotKey` and friends.
final class HotKeyCenter {
    enum RegistrationError: Error {
        /// RegisterEventHotKey refused the combination — usually because another app
        /// already owns it.
        case unavailable(OSStatus)
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    /// Whether a hotkey is currently registered and live. Lets a caller tell "nothing is
    /// registered because the user hasn't set a shortcut" apart from "registration was
    /// attempted and failed" without keeping its own shadow state.
    var isRegistered: Bool { hotKeyRef != nil }

    /// Identifies our hotkey in the Carbon callback. Arbitrary, but must be stable.
    private static let signature: OSType = 0x4D42_5452 // 'MBTR'
    private let identifier: UInt32 = 1

    deinit {
        unregister()
        // unregister() only removes the hotkey binding, not the Carbon event handler
        // installed below — that has to go too, or its userData pointer (an unretained
        // reference back to this instance) dangles and a stray event would use-after-free.
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    /// Registers `shortcut` system-wide, replacing any previously registered one.
    ///
    /// Throws if Carbon rejects the combination, leaving nothing registered — callers
    /// that want to keep the old shortcut on failure must re-register it themselves.
    func register(_ shortcut: GlobalShortcut, handler: @escaping () -> Void) throws {
        unregister()
        self.handler = handler

        installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode),
                                         shortcut.carbonModifiers,
                                         hotKeyID,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &ref)

        guard status == noErr, let ref else {
            self.handler = nil
            throw RegistrationError.unavailable(status)
        }
        hotKeyRef = ref
    }

    /// Removes the hotkey. Safe to call when nothing is registered.
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        handler = nil
    }

    /// Installs the Carbon event handler once and leaves it installed. Registering and
    /// unregistering hotkeys doesn't require tearing it down, and reinstalling per
    /// registration would risk leaking handlers.
    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))

        // Carbon is a C API with no notion of self, so pass an unretained pointer back to
        // this instance. Unretained is safe because deinit removes this handler (see
        // above), so the callback cannot outlive the object it points at.
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }

            var firedID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &firedID)
            guard status == noErr else { return status }

            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            guard firedID.signature == HotKeyCenter.signature,
                  firedID.id == center.identifier else {
                return OSStatus(eventNotHandledErr)
            }

            // Carbon calls back on the main thread, but the handler touches AppKit, so be
            // explicit rather than relying on that.
            DispatchQueue.main.async { center.handler?() }
            return noErr
        }, 1, &spec, context, &eventHandler)
    }
}
