# MenuBar Translate

macOS 選單列翻譯工具：把 Google 翻譯常駐在選單列，點一下圖示立即翻譯，不必另開瀏覽器。支援深色模式，並整合 macOS「服務」選單——在任何 App 選取文字，右鍵即可送進來翻譯。

> Fork 自 [zetxek/osx-menubar-translate](https://github.com/zetxek/osx-menubar-translate)（MIT 授權），此版本包含多項穩定性修正與深色模式。

![](Docs/service-demo.gif)

## 下載安裝

1. 到 [Releases](https://github.com/shuwn/osx-menubar-translate/releases) 下載最新版 zip
2. 解壓縮，把 `Translate Menu.app` 拖進「應用程式」資料夾
3. 打開即可——翻譯圖示出現在選單列

釋出版本**已通過 Apple 公證（Notarized）**，下載後直接打開，不會出現 Gatekeeper 警告。

系統需求：macOS 12.4+（Apple Silicon）。

## 功能

- **點一下就翻譯**：WebView 常駐記憶體，開啟視窗零載入等待
- **深色模式**：跟隨系統外觀即時切換。Google 翻譯網頁版本身沒有深色主題，本版以 CSS 濾鏡實作柔和深灰配色，切換時不需重載
- **服務選單整合**：任何 App 選取文字 → 右鍵 → 服務 → Translate in MenuTranslate
- **右鍵選單**：版本資訊（自動同步 Info.plist）、關於、結束
- **無追蹤**：App 本身不收集任何資料（內嵌網頁中 Google 自己的行為除外）
- **沙盒化**：App Sandbox 啟用，僅申請對外網路連線權限

## 快捷鍵

翻譯視窗內支援（Caps Lock 開啟時也正常運作）：

| 快捷鍵 | 功能 |
|---|---|
| `cmd + A` | 全選 |
| `cmd + C` | 複製 |
| `cmd + V` | 貼上 |

選單列 App 沒有編輯選單可路由快捷鍵，這三組由 App 攔截鍵盤事件、透過 JavaScript 橋接到網頁內實作。

## 架構

~450 行 Swift，四個檔案，全繁體中文註解：

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
| `AppDelegate.swift` | 入口分派、popover 生命週期、服務註冊、版本選單 |
| `TranslateViewController.swift` | WebView 宿主、翻譯網址編碼、深色模式注入、焦點管理 |
| `TranslateWebView.swift` | 鍵盤攔截、剪貼簿與網頁間的 JS 橋接 |
| `EventMonitor.swift` | 全域點擊監聽（偵測點擊 popover 外部） |

## 自行建置

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

### 釋出流程（維護者用）

Developer ID 建置 → Apple 公證 → staple → GitHub Release：

```bash
xcodebuild -scheme "Translate Menu" -configuration Release build \
  CODE_SIGN_IDENTITY="Developer ID Application" ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=<TEAM_ID> PROVISIONING_PROFILE_SPECIFIER=""
ditto -c -k --keepParent "Translate Menu.app" app.zip
xcrun notarytool submit app.zip --keychain-profile notary --wait
xcrun stapler staple "Translate Menu.app"
```

## 相對上游的修正

皆經實機驗證與 50+ 輪壓力測試（零崩潰、零記憶體洩漏、閒置 CPU 0%）：

- 修正貼上含引號／反斜線／換行的文字會失敗（手工 JS 跳脫改為 JSON 編碼）
- 修正冷啟動後第一次透過服務選單翻譯時文字遺失
- 修正選單列圖示有時要點兩次才有反應（點擊判斷改用觸發事件，不讀滑鼠即時狀態）
- 修正打中文點輸入法候選字時視窗被誤關（外部點擊判斷改用滑鼠座標）
- 修正 Caps Lock 開啟時 cmd+C/V/A 失效
- 修正載入指示器在重開視窗或斷網時永遠轉圈
- 修正選單版本號寫死在 xib、與實際版本脫鉤
- 新增深色模式與載入防白閃

## 截圖

選單列圖示：

![](Resources/closed.png)

翻譯視窗展開：

![](Resources/open.png)

## 授權

MIT License，詳見 [license.md](license.md)。原作者：[Adrián Moreno Peña](https://github.com/zetxek)。
