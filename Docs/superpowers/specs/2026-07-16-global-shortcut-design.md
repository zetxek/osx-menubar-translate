# Global Customizable Keyboard Shortcut — Design

**Issue:** [#3](https://github.com/zetxek/osx-menubar-translate/issues/3) — "Keyboard shortcut to access the translate window in menu bar", originally requested by @feppos0 in #2 (2019).

**Goal:** Let the user press a keyboard shortcut from anywhere in macOS to open the translate popover, and choose that shortcut themselves in a Settings window.

---

## Decisions made during brainstorming

| Decision | Choice | Why |
|---|---|---|
| Default shortcut | **None — opt-in** | Global hotkeys are scarce shared real estate. Claiming one at install could silently break a combo the user already relies on, without their consent. |
| Settings UI | **AppKit, built in code** | Matches the existing AppKit codebase. No xib, because the recorder needs a custom `NSView` subclass anyway and xibs review badly in diffs. |
| Hotkey registration | **Carbon `RegisterEventHotKey`** | Works inside the sandbox with no permission prompt, and consumes the keystroke. |

### Why not `NSEvent.addGlobalMonitorForEvents`

The app already uses `EventMonitor` (a global `NSEvent` monitor) for outside-click detection, so it would be the familiar choice. It is the wrong one here for two reasons:

1. It requires Accessibility permission — a scary system prompt plus a trip to System Settings, for a convenience feature.
2. **It cannot consume the event.** The keystroke would still reach the frontmost app, so the shortcut would open the translator *and* type into whatever the user was doing.

The second is disqualifying.

### Why not sindresorhus/KeyboardShortcuts

It is good, and would supply a polished recorder for far less code. It would also be this project's first-ever dependency, for something that is roughly 150 lines to do directly. Not worth the precedent here.

---

## Architecture

Four new files, each with one responsibility.

### `GlobalShortcut.swift` — the value type

```swift
struct GlobalShortcut: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
}
```

Responsibilities:
- **Validation.** Rejects any combination without at least one of `.command`, `.option`, `.control`. See "The bare-key hazard" below.
- **Display string.** `⌥⌘T`, for the Settings UI.
- **Persistence.** Encode to / decode from `UserDefaults`.
- **Carbon translation.** Converts `NSEvent.ModifierFlags` to Carbon's `cmdKey`/`optionKey`/`controlKey`/`shiftKey` bitmask.

Pure: no UI, no Carbon calls, no global state. This is the only piece that is genuinely unit-testable, and it deliberately holds the logic most worth testing.

### `HotKeyCenter.swift` — the Carbon wrapper

```swift
final class HotKeyCenter {
    func register(_ shortcut: GlobalShortcut, handler: @escaping () -> Void) throws
    func unregister()
}
```

The only file that knows Carbon exists. Owns the `EventHotKeyRef` and the installed event handler, and unregisters on `deinit`. Throws when `RegisterEventHotKey` returns a non-zero `OSStatus` so the caller can report a conflict.

### `ShortcutRecorderView.swift` — the recorder

An `NSView` subclass that becomes first responder, captures one `keyDown`, and reports a `GlobalShortcut` via a callback. Draws the current shortcut, or a "Click to record" prompt.

Knows nothing about Carbon or persistence — it turns keystrokes into values.

Behaviour:
- Click → enters recording state.
- A valid combination → reports it, exits recording.
- An invalid combination (no `cmd`/`opt`/`ctrl`) → stays recording, shows a hint.
- `Escape` → cancels, leaves the existing shortcut untouched.

### `SettingsWindowController.swift` — the window

Builds a small `NSWindow` in code: a label, the recorder, a Clear button, and a status line for errors. Owns no logic beyond wiring the recorder's callback to persistence and re-registration.

### Changes to `AppDelegate.swift`

- Add a "Settings…" item to `statusMenu`.
- Own the `HotKeyCenter`.
- On launch: read the saved shortcut, register it if present.
- The handler calls the existing `statusItemButtonActivated` toggle path — not a new one.

---

## Data flow

```
Launch
  UserDefaults → GlobalShortcut? → HotKeyCenter.register { toggle popover }

Recording
  keyDown → ShortcutRecorderView → GlobalShortcut
          → validate → UserDefaults
          → HotKeyCenter.unregister() → register(new)
          → success or error shown in the window

Clear
  HotKeyCenter.unregister() → remove from UserDefaults
```

---

## The bare-key hazard

This is the one way the feature can go badly wrong, so it is worth stating plainly.

A global hotkey with no modifier fires on **every press of that key, in every application**. If the user records `T` alone, pressing `t` while writing an email would open the translator over their message. Shift alone is not enough either — `shift+T` is just a capital T.

Therefore `GlobalShortcut` refuses to exist without at least one of `.command`, `.option`, `.control`. Validation lives in the value type rather than the recorder view so it cannot be bypassed by a future caller, and so it is testable without a UI.

Function keys (F1–F20) are a legitimate exception in principle — they are not typing keys. They are **out of scope**: allowing them means a second validation path for marginal benefit. If someone asks, revisit then.

---

## Error handling

| Situation | Behaviour |
|---|---|
| `RegisterEventHotKey` fails (combo owned by another app) | `HotKeyCenter.register` throws; Settings shows "⌥⌘T is already in use by another app". The previous shortcut stays registered. |
| Recorded combo has no `cmd`/`opt`/`ctrl` | Recorder refuses, shows "Add ⌘, ⌥ or ⌃". Nothing is saved. |
| `UserDefaults` holds corrupt or partial data | Decode returns `nil`; treated as "no shortcut set". No crash, no migration. |
| No shortcut set (default) | Nothing is registered. The app behaves exactly as it does today. |

---

## Testing

**The repo has no test target.** The XCUITest work from an earlier session is still sitting in `stash@{0}` and was never landed. Adding a test target is a larger decision than this feature warrants, so this ships with manual verification.

`GlobalShortcut` is nevertheless designed pure, so it *can* be unit-tested the moment a target exists — and it is where the logic worth testing lives (validation, display string, defaults round-trip).

Manual verification checklist:

- [ ] Record `⌥⌘T`; it displays as `⌥⌘T`.
- [ ] With another app focused, `⌥⌘T` opens the popover with the input focused.
- [ ] Pressing it again closes the popover.
- [ ] The keystroke does **not** reach the previously focused app.
- [ ] Quit and relaunch: the shortcut still works.
- [ ] Clear: the shortcut stops working, and stays cleared across a relaunch.
- [ ] Try recording `T` alone → refused with a hint.
- [ ] Try recording a combo another app owns (e.g. `⌘Space`) → error shown, previous shortcut still works.
- [ ] With no shortcut set, the app behaves exactly as before.

---

## Scope

**In:** one shortcut, a Settings window containing only that, persistence, validation, conflict reporting.

**Out:** other preferences; a first-run prompt; function-key support; multiple shortcuts; a shortcut to translate the current selection directly.

---

## Note on branching

This branches from `master`, but [PR #18](https://github.com/zetxek/osx-menubar-translate/pull/18) (Start at Login) also adds an item to `statusMenu` in `AppDelegate.applicationDidFinishLaunching`. Whichever merges second will need a small conflict resolution there. The conflict is limited to menu-item insertion order.
