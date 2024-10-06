//
//  GPTAction.swift
//  Selected
//
//  Created by sake on 2024/6/2.
//

import Foundation
import Defaults

class GptAction: Decodable, @unchecked Sendable{
    var prompt: String
    var tools: [FunctionDefinition]?

    init(prompt: String) {
        self.prompt = prompt
    }

    func generate(pluginInfo: PluginInfo,  generic: GenericAction) -> PerformAction {
        if generic.after == kAfterPaste  {
            return PerformAction(
                actionMeta: generic, complete: { ctx in
                    let chatCtx = ChatContext(text: ctx.Text, webPageURL: ctx.WebPageURL, bundleID: ctx.BundleID)
                    await ChatService(prompt: self.prompt, options: pluginInfo.getOptionsValue())!.chat(ctx: chatCtx) { _, ret in
                        if ret.role == .assistant {
                            pasteText(ret.message)
                        }
                    }
                })
        } else {
            return PerformAction(
                actionMeta: generic, complete: { [weak self] ctx in
                    guard let self = self else { return }
                    await MainActor.run {
                        let chatCtx = ChatContext(text: ctx.Text, webPageURL: ctx.WebPageURL, bundleID: ctx.BundleID)
                        let chatService = self.createChatService(pluginInfo: pluginInfo)
                        ChatWindowManager.shared.createChatWindow(chatService: chatService, withContext: chatCtx)
                    }
                })
        }
    }


    private func createChatService(pluginInfo: PluginInfo) -> AIChatService {
        if let tools = tools {
            switch Defaults[.aiService] {
                case "Claude":
                    return ClaudeService(prompt: prompt, tools: tools, options: pluginInfo.getOptionsValue())
                default:
                    return OpenAIService(prompt: prompt, tools: tools, options: pluginInfo.getOptionsValue())
            }
        } else {
            return ChatService(prompt: prompt, options: pluginInfo.getOptionsValue())!
        }
    }
}
