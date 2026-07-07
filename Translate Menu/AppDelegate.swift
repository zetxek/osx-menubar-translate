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

/// App 進入點。負責三件事：
/// 1. 建立選單列（menu bar）狀態圖示，處理左鍵（開關 popover）與右鍵（顯示選單）
/// 2. 管理翻譯 popover 的生命週期（顯示、關閉、點擊外部自動關閉）
/// 3. 註冊 macOS「服務」選單入口，讓其他 App 選取文字後可直接送進來翻譯
@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    /// 右鍵選單（定義在 MainMenu.xib，含「關於」與「結束」）
    @IBOutlet weak var statusMenu: NSMenu!

    /// 選單列上的狀態圖示
    var statusItem: NSStatusItem!
    /// 承載翻譯畫面的 popover 視窗
    let popover = NSPopover()
    /// 翻譯畫面的控制器（App 存活期間常駐，維持 WebView 已載入狀態以求秒開）
    let translateViewController = TranslateViewController(nibName: "TranslateViewController", bundle: nil)
    /// 全域滑鼠點擊監聽器，用來偵測「點擊 popover 以外的地方」以自動關閉
    var eventMonitor: EventMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 建立選單列圖示；isTemplate 讓圖示自動適應深色／淺色選單列
        statusItem = NSStatusBar.system.statusItem(withLength: 32)

        let image = NSImage(named: "TranslateStatusBarButtonImage")
        image?.isTemplate = true

        if let button = statusItem.button {
            button.image = image
            button.action = #selector(statusItemButtonActivated(sender:))
            // 只在滑鼠「按下」時觸發：mouseUp 也觸發的話，每次點擊會多跑一次空轉
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        popover.contentViewController = translateViewController
        // 關閉時機完全由程式控制（不用 .transient），避免輸入法等系統視窗搶焦點時誤關
        popover.behavior = .applicationDefined

        // ponytail: geometry check keeps IME candidate clicks (which overlap the
        // popover but belong to the input-method process) from dismissing it
        // 全域監聽只會收到「其他程序」的點擊。用「滑鼠座標是否落在 popover 框內」判斷，
        // 而不是比對視窗身分——因為輸入法候選字視窗屬於輸入法程序，點候選字不該關閉 popover
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [unowned self] event in
            guard self.popover.isShown,
                  let frame = self.popover.contentViewController?.view.window?.frame,
                  !NSMouseInRect(NSEvent.mouseLocation, frame, false)
            else { return }

            self.closePopover(sender: event)
        }

        // 註冊為「服務」提供者（對應 Info.plist 的 NSServices 宣告）
        NSApplication.shared.servicesProvider = self
    }

    /// 選單列圖示被點擊：左鍵開關 popover，右鍵（或 control+左鍵）顯示選單。
    @IBAction
    func statusItemButtonActivated(sender: AnyObject?) {
        // Decide from the triggering event, not live mouse state — by the time
        // this runs the button may already be released and a state read misses the click.
        // 一律用「觸發這次 action 的事件」判斷，不能讀滑鼠即時狀態：
        // 主執行緒忙碌時 action 會延遲執行，等跑到這裡手指早已放開，
        // 讀即時狀態會誤判成「沒有點擊」而把這次點擊吃掉（舊版「有時要點兩次」的根因）
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseDown
            || event?.modifierFlags.contains(.control) == true

        if isSecondary {
            // 暫時掛上選單再模擬點擊，是讓 NSStatusItem 顯示選單的標準做法；
            // 用完立刻拿掉，否則之後的左鍵會變成開選單而不是開 popover
            statusItem.menu = self.statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown {
            closePopover(sender: sender)
        } else {
            showPopover(sender: sender)
        }
    }

    /// 顯示 popover 並把鍵盤焦點交給翻譯輸入框。
    func showPopover(sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        // 選單列 App 平常不是作用中 App，必須主動 activate 才能接收鍵盤輸入
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // popover 的視窗要等 show 之後的下一個 runloop 才存在，所以 async 一拍再抓焦點
        DispatchQueue.main.async {
            self.popover.contentViewController?.view.window?.orderFrontRegardless()
            self.translateViewController.focusInputIfPossible()
        }

        eventMonitor?.start()
    }

    /// 關閉 popover 並停止全域點擊監聽（不用時不留監聽器，避免無謂負載）。
    func closePopover(sender: AnyObject?) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }

    /// macOS「服務」選單入口：其他 App 選取文字 →「Translate in MenuTranslate」→ 這裡。
    /// 系統會把選取的文字放進 pasteboard 傳入。
    @objc
    func translateService(_ pasteboard: NSPasteboard,
                          userData: String,
                          error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string) else { return }

        translateViewController.loadText(text: text)
        showPopover(sender: nil)
    }

    /// 右鍵選單「結束」。
    @IBAction
    func quitApp(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }

    /// 右鍵選單「關於」：開啟專案 GitHub 頁面。
    @IBAction
    func aboutMenuActivated(sender: AnyObject?) {
        NSWorkspace.shared.open(URL(string: "https://github.com/zetxek/osx-menubar-translate")!)
    }
}
