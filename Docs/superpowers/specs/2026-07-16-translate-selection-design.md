# Translate the Selection on Shortcut — Design

> **Superseded (2026-08-02). This design never worked, and was reverted in 1.2.6.**
>
> The spike's first finding below — *"Can a sandboxed app be granted Accessibility? **Yes.**
> … The sandbox is not a blocker"* — checked the wrong thing. It confirmed the app can be
> *listed and toggled* in System Settings → Privacy & Security → Accessibility, which is
> true and irrelevant: the App Sandbox blocks the Accessibility API from reading **other
> processes** however the user answers the prompt. `readSelection()` therefore always
> returned nil in a released build, and the shortcut opened an empty window
> ([#21](https://github.com/zetxek/osx-menubar-translate/issues/21)).
>
> Verified on 2026-08-02 against a shipped 1.2.5 with the permission genuinely granted (the
> app's own `AXIsProcessTrusted()` reported true): the selection still never arrived, while
> an unsandboxed binary running the identical AX calls read it first try.
>
> The same trap the spike caught once — mistaking inherited trust from a shell-launched
> binary for the real thing — very likely also produced the "AX works in Chromium" row.
> **Lesson: prove the API call succeeds, not that the permission can be granted.**
>
> Translating a selection now goes through the Services entry, which needs no permission
> and works inside the sandbox. Users assign it a shortcut in System Settings → Keyboard →
> Keyboard Shortcuts → Services.

**Goal:** One shortcut. Press it with text selected and the popover opens already translating that text; press it with nothing selected and it opens empty, exactly as today.

This unifies the global shortcut (#3, PR #19) with what the Services menu entry already does, so there is one key to learn rather than two.

---

## What the spike established

A throwaway spike ran inside the real sandboxed app, because none of this can be answered from an unsandboxed shell. Findings:

| Question | Answer |
|---|---|
| Can a **sandboxed** app be granted Accessibility? | **Yes.** "Translate Menu" appears in System Settings → Privacy & Security → Accessibility with a toggle. The sandbox is not a blocker. |
| Does AX work in Chromium apps? | **Yes.** Vivaldi advertises `AXSelectedText` and returns it. |
| What happens with no grant? | AX returns `-25204` (`kAXErrorCannotComplete`) and synthetic events are **silently dropped**. Nothing errors — it just does nothing. |

Two corrections the spike forced, recorded so they are not repeated:

- An earlier reading of `AXIsProcessTrusted: true` was **inherited trust** — the binary had been launched as a child of an already-trusted shell. Launched properly it reports `false`. Any future trust check must be done on a LaunchServices-launched app.
- `-25212` is `kAXErrorNoValue` ("attribute exists, empty right now"), **not** `kAXErrorAttributeUnsupported` (`-25205`). Misreading it produced the false conclusion that Chromium lacks AX selection support, which nearly bought us a cmd+C fallback we do not need.

---

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Permission | **Opt-in, default off** | Off = today's behaviour and no prompt ever. Users who only want a translate window never pay for a feature they did not ask for. |
| Read method | **AX only** | The spike showed AX covers native *and* Chromium. A cmd+C fallback would add a second code path, a polling race, and clipboard damage to solve a problem that does not exist. |
| Clipboard | **Never touched** | Follows from AX-only. |
| Services entry | **Kept** | Free, needs no permission, and remains the answer for anyone who declines Accessibility. |

### Why not simply put a shortcut on the Service

A Service with `NSSendTypes` is **disabled when nothing is selected**, so a Services shortcut cannot open the translator on an empty selection. It therefore cannot be the single unified shortcut. It stays as a complement.

---

## Architecture

### `SelectionReader.swift` — new, the only file that touches Accessibility

```swift
enum SelectionReader {
    static var isPermitted: Bool          // AXIsProcessTrusted()
    static func requestPermission()       // AXIsProcessTrustedWithOptions(prompt:)
    static func readSelection() -> String?
}
```

`readSelection()`:
1. Find the frontmost app. **Skip if it is us** — our own popover's selection is not what the user means.
2. `AXUIElementCreateApplication(pid)` → `kAXFocusedUIElementAttribute` → `kAXSelectedTextAttribute`.
3. Clean the result (below).
4. Return nil for empty, so the caller cannot tell "no selection" from "nothing useful".

Every failure returns nil. There is no error surface: an unreadable selection means the popover opens empty, which is the pre-existing behaviour.

### `Preferences.swift` — new, one pure value

```swift
enum Preferences {
    static func translateSelection(in: UserDefaults = .standard) -> Bool
    static func setTranslateSelection(_ on: Bool, in: UserDefaults = .standard)
}
```

Pure and injectable, so it tests in the existing suite alongside `GlobalShortcut`.

### `AppDelegate.toggleFromShortcut()` — one branch added

```swift
if popover.isShown { closePopover(sender: nil); return }
if Preferences.translateSelection(), let text = SelectionReader.readSelection() {
    translateViewController.loadText(text: text)
}
showPopover(sender: nil)
```

With the setting off, this is byte-for-byte today's behaviour.

### `SettingsWindowController` — one checkbox

"Translate selected text" plus a status line. Ticking it when Accessibility is not granted prompts, and the status line explains that macOS must be told to allow it, with a button that opens the pane. The checkbox reflects the stored preference; the status line reflects reality. **The two are kept separate on purpose** — a ticked box that silently does nothing is exactly the failure mode being avoided.

---

## Cleaning the selection

Chromium returns `￼` (U+FFFC, object replacement) for inline images, and a `cmd+A` selection drags in page chrome. So:

- Strip U+FFFC.
- Collapse runs of whitespace/newlines into single spaces.
- Trim.
- **Cap at 2000 characters.** The text rides in the Google Translate URL; an unbounded selection would build an absurd URL. 2000 is comfortably inside what the endpoint accepts.
- Empty after cleaning → nil.

This is pure string handling, so it lives in a testable function rather than inline in the AX code.

---

## Error handling

| Situation | Behaviour |
|---|---|
| Setting off | No AX call, no prompt, today's behaviour exactly. |
| Setting on, permission not granted | Popover opens empty. Settings shows the permission is missing and offers to open the pane. |
| Focused element has no `AXSelectedText` | Opens empty. Normal for non-text UI. |
| Selection empty or whitespace | Opens empty. |
| Frontmost app is us | No read attempted. |

Nothing here is an error dialog. The failure mode of every path is "opens empty", which is what the app did before this feature.

---

## Testing

Unit tests join the existing `Translate MenuTests` target:

- `Preferences`: default is **off**; round-trips; a corrupt value reads as off.
- Selection cleaning: strips U+FFFC; collapses whitespace; trims; caps at 2000; empty → nil.

`SelectionReader.readSelection()` itself is not unit-testable — it needs a live AX session, a frontmost app and a granted permission. It is deliberately kept thin for that reason: the logic worth testing (cleaning, preference) sits either side of it.

Manual verification requires the Accessibility toggle to be granted by hand:

- [ ] Setting off: shortcut opens empty even with text selected.
- [ ] Setting on, permission granted, text selected in TextEdit → opens translating it.
- [ ] Same in Vivaldi (Chromium path).
- [ ] Nothing selected → opens empty.
- [ ] The clipboard is unchanged throughout.
- [ ] Setting on, permission denied → opens empty, Settings explains why.

---

## Scope

**In:** one checkbox, AX read, cleaning, the permission explanation.

**Out:** cmd+C fallback; reading selections from apps with no AX support; translating without opening the popover; a first-run prompt.
