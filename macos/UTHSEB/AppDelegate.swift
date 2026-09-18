import AppKit
import CryptoKit
import WebKit

private enum UTHSEBConfig {
    static let version = "1.0.4-mac"
    static let scheme = "uthseb"
    static let requestHeader = "X-UTHSEB-Request-Hash"
    static let requestKey = "ATDGMFUeicurzkek5234=5575;645755"
    static let userAgentSuffix = "SEB/3.3.2 UTHSEB/1.0.4 (Official Build; School-ID: UTH-2026; SecureMode)"
    static let demoMode = CommandLine.arguments.contains("--demo")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var browserController: BrowserWindowController?
    private var pendingURL: URL?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenURL(event:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let argumentTarget = CommandLine.arguments.dropFirst()
            .compactMap(URL.init(string:))
            .compactMap { launchTarget(from: $0) }
            .first
        browserController = BrowserWindowController(launchURL: pendingURL ?? argumentTarget)
        browserController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let applicationMenuItem = NSMenuItem()
        mainMenu.addItem(applicationMenuItem)
        let applicationMenu = NSMenu()
        applicationMenu.addItem(
            withTitle: "Quit UTH SEB",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationMenuItem.submenu = applicationMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSApp.presentationOptions = []
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let browserController, !browserController.isClosingApproved else { return .terminateNow }
        browserController.confirmExit()
        return .terminateCancel
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let target = urls.compactMap({ launchTarget(from: $0) }).first else { return }
        if let browserController {
            browserController.navigate(to: target)
        } else {
            pendingURL = target
        }
    }

    @objc private func handleOpenURL(event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let incoming = URL(string: value), let target = launchTarget(from: incoming) else { return }
        if let browserController {
            browserController.navigate(to: target)
        } else {
            pendingURL = target
        }
    }

    private func launchTarget(from incoming: URL?) -> URL? {
        guard let incoming else { return nil }
        if ["http", "https"].contains(incoming.scheme?.lowercased() ?? "") { return incoming }
        guard incoming.scheme?.lowercased() == UTHSEBConfig.scheme,
              let components = URLComponents(url: incoming, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name.lowercased() == "url" })?.value,
              let target = URL(string: value),
              ["http", "https"].contains(target.scheme?.lowercased() ?? "") else { return nil }
        return target
    }
}

final class BrowserWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private let webView: WKWebView
    private var keyboardMonitor: Any?
    private var alertIsOpen = false
    private var screenLockEnabled = false
    private var unlockedFrame: NSRect?
    fileprivate var isClosingApproved = false

    init(launchURL: URL?) {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = UTHSEBConfig.userAgentSuffix
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)

        let availableFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let width = min(1280, availableFrame.width)
        let height = min(820, availableFrame.height)
        let frame = NSRect(
            x: availableFrame.midX - width / 2,
            y: availableFrame.midY - height / 2,
            width: width,
            height: height
        )
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "UTH SEB"
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary]
        window.level = .normal
        window.isReleasedWhenClosed = false
        // macOS screenshot shortcuts may capture the app only while it is unlocked.
        window.sharingType = .readOnly
        window.contentView = webView

        super.init(window: window)
        writeDemoStatus("STARTING")
        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        installKeyboardMonitor()

        if let launchURL {
            navigate(to: launchURL)
        } else {
            showLauncher()
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        webView.window?.makeFirstResponder(webView)
    }

    func navigate(to url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        webView.load(authenticatedRequest(for: url))
    }

    private func installKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if self.screenLockEnabled {
                if event.keyCode == 53 {
                    self.confirmExit()
                    return nil
                }

                let character = event.charactersIgnoringModifiers?.lowercased()
                let isClipboardShortcut = modifiers.contains(.command) &&
                    ["c", "x", "v"].contains(character ?? "")
                let isScreenshotShortcut = event.keyCode == 21 &&
                    modifiers.contains([.command, .shift])
                if isClipboardShortcut || isScreenshotShortcut {
                    NSSound.beep()
                    return nil
                }
            }

            guard event.keyCode == 23, modifiers.contains(.control),
                  !modifiers.contains(.command), !modifiers.contains(.option) else {
                return event
            }
            self.toggleScreenLock()
            return nil
        }
    }

    private func toggleScreenLock() {
        screenLockEnabled.toggle()
        guard let window else { return }

        if screenLockEnabled {
            unlockedFrame = window.frame
            window.sharingType = .none
            NSPasteboard.general.clearContents()
            NSApp.presentationOptions = [
                .hideDock,
                .hideMenuBar,
                .disableAppleMenu,
                .disableProcessSwitching,
                .disableForceQuit,
                .disableSessionTermination,
                .disableHideApplication
            ]
            window.styleMask = [.borderless]
            window.collectionBehavior = [.fullScreenPrimary, .stationary]
            window.level = .mainMenu + 1
            window.setFrame(NSScreen.main?.frame ?? window.frame, display: true, animate: false)
            window.title = "UTH SEB — ĐANG KHÓA (Control + 5 để mở khóa)"
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.presentationOptions = []
            window.sharingType = .readOnly
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.collectionBehavior = [.fullScreenPrimary]
            window.level = .normal
            if let unlockedFrame {
                window.setFrame(unlockedFrame, display: true, animate: false)
            } else {
                window.center()
            }
            window.title = "UTH SEB"
            window.makeKeyAndOrderFront(nil)
        }
        webView.window?.makeFirstResponder(webView)
    }

    fileprivate func confirmExit() {
        guard !alertIsOpen else { return }
        alertIsOpen = true
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "XÁC NHẬN THOÁT"
        alert.informativeText = "Bạn muốn thoát ứng dụng thi?"
        alert.addButton(withTitle: "Ở lại")
        alert.addButton(withTitle: "Thoát")
        if screenLockEnabled {
            alert.window.level = .mainMenu + 2
        }
        let response = alert.runModal()
        alertIsOpen = false
        if response == .alertSecondButtonReturn {
            isClosingApproved = true
            NSApp.presentationOptions = []
            window?.level = .normal
            NSApp.terminate(nil)
        } else if screenLockEnabled {
            window?.makeKeyAndOrderFront(nil)
            webView.window?.makeFirstResponder(webView)
        }
    }

    private func writeDemoStatus(_ value: String) {
        guard UTHSEBConfig.demoMode else { return }
        try? value.write(
            to: URL(fileURLWithPath: "/tmp/UTHSEB-demo-status.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func authenticatedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        let content = Data((url.absoluteString + UTHSEBConfig.requestKey).utf8)
        let digest = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        request.setValue(digest, forHTTPHeaderField: UTHSEBConfig.requestHeader)
        return request
    }

    private func showLauncher() {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        *{box-sizing:border-box}body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:linear-gradient(135deg,#0b2942,#087f86);color:#123239}
        main{width:min(560px,calc(100vw - 48px));padding:38px;background:rgba(255,255,255,.96);border-radius:16px;box-shadow:0 18px 50px rgba(0,0,0,.3);text-align:center}h1{font-size:25px;color:#004a80;margin:0 0 26px}.buttons{display:grid;gap:14px}a{display:flex;align-items:center;justify-content:center;min-height:52px;padding:12px 18px;border-radius:9px;color:white;text-decoration:none;font-weight:800}.courses{background:#087ce1}.thnn{background:#269d4b}.portal{background:#63717c}.note{margin-top:28px;padding-top:20px;border-top:1px solid #efc3c3}.note strong{display:block;color:#c31532;margin-bottom:8px}.hint{background:#e8f6f7;border:1px solid #b7dddf;border-radius:7px;padding:10px;font-weight:700;font-size:14px}.version{font-size:12px;color:#667;margin-top:13px}
        </style></head><body><main><h1>CỔNG THÔNG TIN &amp; THI TRỰC TUYẾN UTH</h1><div class="buttons">
        <a class="courses" href="https://courses.ut.edu.vn/">COURSES (Hệ thống học tập)</a>
        <a class="thnn" href="https://thnn.ut.edu.vn/">THNN (Hệ thống Tin học Ngoại Ngữ)</a>
        <a class="portal" href="https://portal.ut.edu.vn/">PORTAL (Trang thông tin SV)</a>
        </div><div class="note"><strong>LƯU Ý NGHIÊM TÚC</strong><p>Mọi hành vi ghi hình/chụp màn hình sẽ bị hạn chế.</p><div class="hint">Cách thoát UTH SEB: nhấn phím Esc, sau đó chọn Thoát.</div><div class="version">Phiên bản ứng dụng: \(UTHSEBConfig.version)</div></div></main></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" || scheme == "data" {
            decisionHandler(.allow)
            return
        }
        guard ["http", "https"].contains(scheme) else {
            decisionHandler(.cancel)
            return
        }

        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let method = navigationAction.request.httpMethod?.uppercased() ?? "GET"
        if isMainFrame && (method == "GET" || method == "HEAD") &&
            navigationAction.request.value(forHTTPHeaderField: UTHSEBConfig.requestHeader) == nil {
            decisionHandler(.cancel)
            var request = navigationAction.request
            let content = Data((url.absoluteString + UTHSEBConfig.requestKey).utf8)
            let digest = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
            request.setValue(digest, forHTTPHeaderField: UTHSEBConfig.requestHeader)
            webView.load(request)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { navigate(to: url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        writeDemoStatus("LOADED\n\(webView.url?.absoluteString ?? "unknown")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        writeDemoStatus("FAILED\n\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        writeDemoStatus("FAILED\n\(error.localizedDescription)")
    }

    @available(macOS 12.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.prompt)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isClosingApproved { return true }
        confirmExit()
        return false
    }

}
