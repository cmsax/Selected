//
//  ChatWindow.swift
//  Selected
//
//  Created by sake on 2024/8/14.
//

import Foundation
import SwiftUI


class ChatWindowManager: @unchecked Sendable {
    static let shared = ChatWindowManager()

    private var lock = NSLock()
    private var windowCtrs = [ChatWindowController]()

    @MainActor func closeAllWindows(_ mode: CloseWindowMode) {
        lock.lock()
        defer {lock.unlock()}

        for index in (0..<windowCtrs.count).reversed() {
            if closeWindow(mode, windowCtr: windowCtrs[index]) {
                windowCtrs.remove(at: index)
            }
        }
    }

    @MainActor func createChatWindow(chatService: AIChatService, withContext ctx: ChatContext) {
        let windowController = ChatWindowController(chatService: chatService, withContext: ctx)
        closeAllWindows(.force)

        lock.lock()
        windowCtrs.append(windowController)
        lock.unlock()

        windowController.showWindow(nil)
        // 如果你需要处理窗口关闭事件，你可以添加一个通知观察者
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: windowController.window, queue: nil) { _ in
        }
    }

    @MainActor private func closeWindow(_ mode: CloseWindowMode, windowCtr: ChatWindowController) -> Bool {
        if windowCtr.pinnedModel.pinned {
            return false
        }

        switch mode {
            case .expanded:
                let frame =  windowCtr.window!.frame
                let expandedFrame = NSRect(x: frame.origin.x - kExpandedLength,
                                           y: frame.origin.y - kExpandedLength,
                                           width: frame.size.width + kExpandedLength * 2,
                                           height: frame.size.height + kExpandedLength * 2)
                if !expandedFrame.contains(NSEvent.mouseLocation){
                    windowCtr.close()
                    return true
                }

            case .original:
                let frame =  windowCtr.window!.frame
                if !frame.contains(NSEvent.mouseLocation){
                    windowCtr.close()
                    return true
                }

            case .force:
                windowCtr.close()
                return true
        }
        return false
    }

}

private class ChatWindowController: NSWindowController, NSWindowDelegate {
    var resultWindow: Bool
    var onClose: (()->Void)?

    var pinnedModel: PinnedModel

    init(chatService: AIChatService, withContext ctx: ChatContext) {
        var window: NSWindow
        // 必须用 NSPanel 并设置 .nonactivatingPanel 以及 level 为 .screenSaver
        // 保证悬浮在全屏应用之上
        window = FloatingPanel(
            contentRect: .zero,
            backing: .buffered,
            defer: false,
            key: true
        )

        window.alphaValue = 0.9
        self.resultWindow = true
        pinnedModel = PinnedModel()

        super.init(window: window)

        let view = ChatTextView(ctx: ctx, viewModel: MessageViewModel(chatService: chatService)).environmentObject(pinnedModel)

        window.level = .screenSaver
        window.contentView = NSHostingView(rootView: AnyView(view))
        window.delegate = self // 设置代理为自己来监听窗口事件

        self.positionWindow()
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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowDidResignActive(_ notification: Notification) {
        self.close() // 如果需要的话
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

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        DispatchQueue.main.async{
            self.positionWindow()
        }
    }
}


class PinnedModel: ObservableObject {
    @Published var pinned: Bool = false
}


private class WindowPositionManager: @unchecked Sendable {
    static let shared = WindowPositionManager()

    func storePosition(of window: NSWindow) {
        Task {
            await MainActor.run {
                let frameString = NSStringFromRect(window.frame)
                UserDefaults.standard.set(frameString, forKey: "ChatWindowPosition")
            }
        }
    }

    @MainActor func restorePosition(for window: NSWindow) -> Bool {
        if let frameString = UserDefaults.standard.string(forKey: "ChatWindowPosition") {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
            return true
        }
        return false
    }
}
