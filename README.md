# MenuBar Translate

一個極簡的 macOS 選單列翻譯工具：把 Google 翻譯常駐在選單列，點一下圖示立即翻譯，不必另開瀏覽器視窗。同時整合 macOS「服務」選單——在任何 App 選取文字，右鍵即可送進來翻譯。

> 本專案 fork 自 [zetxek/osx-menubar-translate](https://github.com/zetxek/osx-menubar-translate)，MIT 授權。

![](Docs/service-demo.gif)

從選單列圖示開啟，或透過系統服務（「服務 > Translate in MenuTranslate」）呼叫：

![2024-11-19 21 32 57](https://github.com/user-attachments/assets/433a4b0c-2f0d-4782-926c-1f7b8c5ace09)

## 功能

- **選單列常駐**：左鍵點圖示開關翻譯視窗，右鍵顯示選單（關於／結束）
- **服務選單整合**：任何 App 選取文字 → 右鍵 → 服務 → Translate in MenuTranslate
- **秒開**：WebView 常駐記憶體，開啟視窗零載入等待
- **無追蹤**：App 本身不收集任何資料（內嵌網頁中 Google 自己的行為除外）
- **沙盒化**：App Sandbox 啟用，僅申請對外網路連線權限

## 快捷鍵

翻譯視窗內支援：

| 快捷鍵 | 功能 |
|---|---|
| `cmd + A` | 全選 |
| `cmd + C` | 複製 |
| `cmd + V` | 貼上 |

選單列 App 沒有編輯選單可路由快捷鍵，這三組由 App 攔截鍵盤事件、透過 JavaScript 橋接到網頁內實作。

## 架構

~420 行 Swift，四個檔案：

```
使用者動線（三個入口，匯流到同一條路徑）
┌─ 選單列圖示左鍵 ──┐
├─ 右鍵選單         ─┼─▶ AppDelegate ──▶ TranslateViewController
└─ 系統「服務」選單 ─┘        │                   │
                        EventMonitor         WKWebView（Google 翻譯）
                       （點外部自動關閉）      TranslateWebView
                                            （cmd+C/V/A ↔ JS 橋接）
```

| 檔案 | 職責 |
|---|---|
| `AppDelegate.swift` | 入口分派、popover 生命週期、服務註冊 |
| `TranslateViewController.swift` | WebView 宿主、翻譯網址組裝與編碼、焦點注入 |
| `TranslateWebView.swift` | 鍵盤攔截、剪貼簿與網頁間的 JS 橋接 |
| `EventMonitor.swift` | 全域點擊監聽（偵測點擊 popover 外部） |

## 建置

```bash
git clone https://github.com/shuwn/osx-menubar-translate.git
cd osx-menubar-translate
open "Translate Menu.xcodeproj"   # Xcode 直接 Run
```

或用命令列（ad-hoc 簽章）：

```bash
xcodebuild -project "Translate Menu.xcodeproj" -scheme "Translate Menu" \
  -configuration Debug build \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

需求：macOS 12.4+、Xcode 14+。

## 穩定性

本 fork 相對上游修正了下列問題（皆經實機驗證與 50+ 輪壓力測試，零崩潰、零記憶體洩漏）：

- **貼上含引號／反斜線／換行的文字失敗**——手工 JS 跳脫改為 JSON 編碼
- **冷啟動後第一次服務呼叫文字遺失**——view 未載入時暫存文字，顯示時補載
- **選單列圖示有時要點兩次**——點擊判斷改用觸發事件本身，不讀滑鼠即時狀態
- **打中文點輸入法候選字時視窗被誤關**——外部點擊判斷改用滑鼠座標
- **載入指示器在重開視窗或斷網時永遠轉圈**——補上失敗回呼、僅首次載入顯示

## 下載

上游原版：[releases 頁面](https://github.com/zetxek/osx-menubar-translate/releases)。解壓縮後拖進「應用程式」資料夾即可。

## 截圖

選單列圖示：

![](Resources/closed.png)

翻譯視窗展開：

![](Resources/open.png)

## 授權

MIT License，詳見 [license.md](license.md)。原作者：[Adrián Moreno Peña](https://github.com/zetxek)。
