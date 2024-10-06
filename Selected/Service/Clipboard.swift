//
//  Clipboard.swift
//  Selected
//
//  Created by sake on 2024/3/31.
//

import Foundation
import Cocoa
import SwiftUI
import Carbon
import Defaults
import HotKey

class ClipService: @unchecked Sendable  {
    static let shared = ClipService()

    private var eventMonitor: Any?
    private var pasteboard: NSPasteboard = .general

    //
    private var lock = NSLock()
    private var changeCount: Int = 0
    private var skip = false

    init() {
        changeCount = pasteboard.changeCount
        NSEvent.addGlobalMonitorForEvents(matching:
                                            [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { (event) in
            Task {
                await MainActor.run {
                    _ = ClipWindowManager.shared.closeWindow()
                }
            }
        }
    }

    func startMonitoring() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp, .leftMouseUp]) { [weak self] event in
            guard let self = self else { return }
            guard Defaults[.enableClipboard] else { return }

            //            NSLog("pasteboard event \(eventTypeMap[event.type]!)")

            if skip {
                return
            }

            let eventType = event.type
            DispatchQueue.global(qos: .background).async {
                if eventType == .leftMouseUp {
                    // 如果是鼠标右键菜单栏里左键点击复制的话，需要等半秒才能从 pasteboard 里获取到复制的数据。
                    usleep(500000)
                }
                self.checkPasteboard()
            }
        }
    }

    func pauseMonitor(_ id: String) {
        lock.lock()
        NSLog("pasteboard \(id) pauseMonitor changeCount \(changeCount)")
        skip = true
        lock.unlock()
    }

    func resumeMonitor(_ id: String) {
        lock.lock()
        skip = false
        changeCount = pasteboard.changeCount
        NSLog("pasteboard \(id) resumeMonitor changeCount \(changeCount)")
        lock.unlock()
    }

    private func checkPasteboard() {
        lock.lock()
        defer {
            lock.unlock()
        }

        let currentChangeCount = pasteboard.changeCount
        if changeCount == currentChangeCount {
            return
        }
        changeCount = currentChangeCount
        NSLog("pasteboard changeCount \(changeCount)")

        guard pasteboard.types != nil else {
            return
        }

        // 剪贴板内容发生变化，处理变化
        NSLog("pasteboard \(String(describing: pasteboard.types))")
        guard let clipData = ClipData(pasteboard: pasteboard) else {
            return
        }

        if skip {
            return
        }
        if clipData.types.isEmpty {
            return
        }
        if filterClipData(clipData) {
            return
        }
        PersistenceController.shared.store(clipData)
    }
}

private let excludeApplications = [
    "com.agilebits.onepassword",
    "com.agilebits.onepassword-osx",
    "com.agilebits.onepassword7",
    "com.agilebits.onepassword4"]

private func filterClipData(_ clipData: ClipData) -> Bool{
    if excludeApplications.contains(clipData.appBundleID) {
        return true
    }
    return false
}

private let excludePasteboardTypes: Set<String> = [
    "org.nspasteboard.TransientType",
    "org.nspasteboard.ConcealedType",
    "org.nspasteboard.AutoGeneratedType",
    "com.agilebits.onepassword",
    "com.typeit4me.clipping",
    "de.petermaurer.TransientPasteboardType",
    "net.antelle.keeweb"]

private let SupportedPasteboardTypes: Set<NSPasteboard.PasteboardType> = [
    .URL,
    .color,
    .html,
    .pdf,
    .png,
    .rtf,
    .string,
    .fileURL,
    NSPasteboard.PasteboardType("org.chromium.source-url"),
]

struct ClipItem {
    var type: NSPasteboard.PasteboardType
    var data: Data
}

struct ClipData: Identifiable {
    var id: String
    var timeStamp: Int64
    var types: [NSPasteboard.PasteboardType]
    var appBundleID: String
    var items: [ClipItem]

    var plainText: String?
    var url: String?

    static private func filterPasteboardTypes(_ types: [NSPasteboard.PasteboardType]?) -> [NSPasteboard.PasteboardType] {
        guard let types = types else {
            return []
        }

        var support = [NSPasteboard.PasteboardType]()
        for t in types {
            if SupportedPasteboardTypes.contains(t) {
                support.append(t)
            }
        }
        return support
    }

    static private func shouldIgnore(_ types: [NSPasteboard.PasteboardType]?) -> Bool{
        guard let types = types else {
            return false
        }

        for tp in types {
            if excludePasteboardTypes.contains(tp.rawValue){
                return true
            }
        }
        return false
    }

    init?(pasteboard: NSPasteboard) {
        self.id = UUID().uuidString
        self.timeStamp = Int64(Date().timeIntervalSince1970*1000)
        self.appBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"

        if ClipData.shouldIgnore(pasteboard.types) {
            return nil
        }

        self.types = ClipData.filterPasteboardTypes(pasteboard.types)

        var items = [ClipItem]()
        for type in types {
            guard let data = pasteboard.data(forType: type) else {
                continue
            }
            let item = ClipItem(type: type, data: data)
            items.append(item)

            if type == .string {
                if let content = pasteboard.string(forType: type) {
                    plainText = content
                }
            } else if type.rawValue == "org.chromium.source-url" {
                if let content = pasteboard.string(forType: type) {
                    url = content
                }
            } else if type == .fileURL {
                if let content = pasteboard.string(forType: type) {
                    url = content
                }
            } else if type == .URL {
                if let content = pasteboard.string(forType: type) {
                    url = content
                }
            } else if type == .png {
                //                TODO: OCR
                //                let image = NSImage(data: item.data)!
                //                recognizeTextInImage(image)
            }
        }
        if (types.first == .html || types.first == .rtf ) && self.plainText == nil {
            return nil
        }
        self.items = items
    }
}

extension ClipData: Hashable {
    static func == (lhs: ClipData, rhs: ClipData) -> Bool {
        return lhs.timeStamp == rhs.timeStamp
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(timeStamp)
    }
}

extension String {
    func tokenize() -> [String] {
        let word = self
        let tokenize = CFStringTokenizerCreate(kCFAllocatorDefault, word as CFString?, CFRangeMake(0, word.count), kCFStringTokenizerUnitWord, CFLocaleCopyCurrent())
        CFStringTokenizerAdvanceToNextToken(tokenize)
        var range = CFStringTokenizerGetCurrentTokenRange(tokenize)
        var keyWords : [String] = []
        while range.length > 0 {
            let wRange = word.index(word.startIndex, offsetBy: range.location)..<word.index(word.startIndex, offsetBy: range.location + range.length)
            let keyWord = String(word[wRange])
            keyWords.append(keyWord)
            CFStringTokenizerAdvanceToNextToken(tokenize)
            range = CFStringTokenizerGetCurrentTokenRange(tokenize)
        }
        return keyWords
    }
}


class ClipboardHotKeyManager {
    nonisolated(unsafe) static let shared = ClipboardHotKeyManager()

    private var hotkey: HotKey?

    func registerHotKey() {
        if hotkey != nil {
            return
        }

        hotkey = HotKey(key: .init(carbonKeyCode: Defaults[.clipboardShortcut].carbonKeyCode)!, modifiers:  Defaults[.clipboardShortcut].modifierFlags)
        hotkey?.keyDownHandler = {
            Task {
                await MainActor.run {
                    ClipWindowManager.shared.createWindow()
                }
            }
        }
    }

    func unregisterHotKey() {
        hotkey?.keyDownHandler = nil
        hotkey = nil
    }
}


private class EnterHotKeyManager {
    private var hotkey: HotKey?

    @MainActor func registerHotKey() {
        if hotkey != nil {
            return
        }
        hotkey = HotKey(key: .return, modifiers: [])
        hotkey?.keyDownHandler = {
            self.handle()
        }
    }

    func unregisterHotKey() {
        hotkey?.keyDownHandler = nil
        hotkey = nil
    }

    @MainActor func handle() {
        guard let item = ClipViewModel.shared.selectedItem else {
            return
        }

        let id = UUID().uuidString
        ClipService.shared.pauseMonitor(id)

        let pboard = NSPasteboard.general
        pboard.clearContents()
        for t in item.getItems() {
            pboard.setData(t.data, forType: NSPasteboard.PasteboardType(rawValue: t.type!))
        }

        PersistenceController.shared.updateClipHistoryData(item)

        // 粘贴时需要取消 key window，才能复制到当前的应用上。
        ClipWindowManager.shared.resignKey()

        usleep(100000)
        PressPasteKey()
        ClipWindowManager.shared.forceCloseWindow()
        ClipService.shared.resumeMonitor(id)
    }
}

extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        for char in self.utf16 {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
}

extension String.StringInterpolation {
    mutating func appendInterpolation(_ value: NSPasteboard.PasteboardType) {
        if let desc = descriptionOfPasteboardType[value] {
            appendInterpolation(desc)
        } else {
            appendInterpolation("unknown")
        }
    }
}

let descriptionOfPasteboardType: [NSPasteboard.PasteboardType: String]  = [
    .URL: "URL",
    .png: "PNG image",
    .html: "HTML",
    .pdf: "PDF",
    .rtf: "rich text format",
    .string: "plain text",
    .fileURL: "file"
]

// MARK: - window

class ClipWindowManager: @unchecked Sendable {
    static let shared =  ClipWindowManager()


    private var windowCtr: ClipWindowController?

    @MainActor fileprivate func createWindow() {
        windowCtr?.close()
        let view = ClipView().environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        let window = ClipWindowController(rootView: AnyView(view))
        windowCtr = window
        window.showWindow(nil)

        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window.window, queue: nil) { _ in
            self.windowCtr = nil
        }
        return
    }

    @MainActor fileprivate func closeWindow() -> Bool {
        guard let windowCtr = windowCtr else {
            return true
        }
        var closed = false
        let frame =  windowCtr.window!.frame
        if !frame.contains(NSEvent.mouseLocation){
            windowCtr.close()
            closed = true
            self.windowCtr = nil
        }
        return closed
    }

    @MainActor func resignKey(){
        windowCtr?.window?.resignKey()
    }

    @MainActor func forceCloseWindow() {
        guard let windowCtr = windowCtr else {
            return
        }
        windowCtr.close()
        self.windowCtr = nil
    }
}


private class ClipWindowController: NSWindowController, NSWindowDelegate {
    var hotkeyMgr = EnterHotKeyManager()

    init(rootView: AnyView) {
        let window = FloatingPanel(
            contentRect: .zero,
            backing: .buffered,
            defer: false,
            key: true // 成为 key 和 main window 就可以用一些快捷键，比如方向键，以及可以文本编辑。
        )

        super.init(window: window)

        window.level = .screenSaver
        window.contentView = NSHostingView(rootView: rootView)
        window.delegate = self // 设置代理为自己来监听窗口事件
        positionWindow()
    }

    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            WindowPositionManager.shared.storePosition(of: window)
        }
    }

    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            WindowPositionManager.shared.storePosition(of: window)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowDidResignActive(_ notification: Notification) {
        self.close() // 如果需要的话
    }

    override func showWindow(_ sender: Any?) {
        hotkeyMgr.registerHotKey()
        super.showWindow(sender)
    }

    private func positionWindow() {
        guard let window = self.window else { return }
        if WindowPositionManager.shared.restorePosition(for: window) {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else {
            return
        }

        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame

        let x = (screenFrame.width - windowFrame.width) / 2 + screenFrame.origin.x
        let y = (screenFrame.height - windowFrame.height) * 3 / 4 + screenFrame.origin.y

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }


    func windowWillClose(_ notification: Notification) {
        hotkeyMgr.unregisterHotKey()
        ClipViewModel.shared.selectedItem = nil
    }
}


private class WindowPositionManager: @unchecked Sendable {
    static let shared = WindowPositionManager()

    func storePosition(of window: NSWindow) {
        Task {
            await MainActor.run {
                let frameString = NSStringFromRect(window.frame)
                UserDefaults.standard.set(frameString, forKey: "ClipboardWindowPosition")
            }
        }
    }

    @MainActor func restorePosition(for window: NSWindow) -> Bool {
        if let frameString = UserDefaults.standard.string(forKey: "ClipboardWindowPosition") {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
            return true
        }
        return false
    }
}
