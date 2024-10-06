//
//  AI.swift
//  Selected
//
//  Created by sake on 2024/3/10.
//

import Defaults
import SwiftUI
import OpenAI

@MainActor public struct ChatContext {
    let text: String
    let webPageURL: String
    let bundleID: String
}

func isWord(str: String) -> Bool {
    for c in str {
        if c.isLetter || c == "-" {
            continue
        }
        return false
    }
    return true
}

struct Translation {
    let toLanguage: String

    func translate(content: String, completion: @escaping @Sendable (_: String) -> Void) async -> Void {
        if toLanguage == "cn" {
            await contentTrans2Chinese(content: content, completion: completion)
        } else if toLanguage == "en" {
            await contentTrans2English(content: content, completion: completion)
        }
    }

    private func isWord(str: String) -> Bool {
        for c in str {
            if c.isLetter || c == "-" {
                continue
            }
            return false
        }
        return true
    }

    private func contentTrans2Chinese(content: String, completion: @escaping @Sendable (_: String) -> Void)  async -> Void{
        switch Defaults[.aiService] {
            case "OpenAI":
                if isWord(str: content) {
                    await OpenAIWordTrans.chatOne(selectedText: content, completion: completion)
                } else {
                    await OpenAITrans2Chinese.chatOne(selectedText: content, completion: completion)
                }
            case "Gemini":
                if isWord(str: content) {
                    await GeminiWordTrans.chatOne(selectedText: content, completion: completion)
                } else {
                    await GeminiTrans2Chinese.chatOne(selectedText: content, completion: completion)
                }
            case "Claude":
                if isWord(str: content) {
                    await ClaudeWordTrans.chatOne(selectedText: content, completion: completion)
                } else {
                    await ClaudeTrans2Chinese.chatOne(selectedText: content, completion: completion)
                }
            default:
                completion("no model \(Defaults[.aiService])")
        }
    }

    private func contentTrans2English(content: String, completion: @escaping @Sendable (_: String) -> Void)  async{
            switch Defaults[.aiService] {

                case "OpenAI":
                    await OpenAITrans2English.chatOne(selectedText: content, completion: completion)
                case "Gemini":
                    await GeminiTrans2English.chatOne(selectedText: content, completion: completion)
                case "Claude":
                    await ClaudeTrans2English.chatOne(selectedText: content, completion: completion)
                default:
                    completion("no model \(Defaults[.aiService])")
            }

    }

    private func convert(index: Int, message: ResponseMessage)->Void {

    }
}

struct ChatService: AIChatService, @unchecked Sendable{
    var chatService: AIChatService

    init?(prompt: String, options: [String:String]){
        switch Defaults[.aiService] {
            case "OpenAI":
                chatService = OpenAIService(prompt: prompt, options: options)
            case "Gemini":
                chatService = GeminiPrompt(prompt: prompt, options: options)
            case "Claude":
                chatService = ClaudeService(prompt: prompt, options: options)
            default:
                return nil
        }
    }

    func chat(ctx: ChatContext, completion: @escaping (_: Int, _: ResponseMessage) -> Void) async -> Void{
        await chatService.chat(ctx: ctx, completion: completion)
    }

    func chatFollow(
        index: Int,
        userMessage: String,
        completion: @escaping (_: Int, _: ResponseMessage) -> Void) async -> Void {
            await chatService.chatFollow(index: index, userMessage: userMessage, completion: completion)
        }
}


class OpenAIService: AIChatService{
    var openAI: OpenAIPrompt

    init(prompt: String, tools: [FunctionDefinition]? = nil, options: [String:String]) {
        var fcs = [FunctionDefinition]()
        if let tools = tools {
            fcs.append(contentsOf: tools)
        }
        openAI = OpenAIPrompt(prompt: prompt, tools: fcs,  options: options)
    }

    func chat(ctx: ChatContext, completion: @escaping (_: Int, _: ResponseMessage) -> Void) async -> Void{
        await openAI
            .chat(ctx: ctx, completion: completion)
    }

    func chatFollow(
        index: Int,
        userMessage: String,
        completion: @escaping (_: Int, _: ResponseMessage) -> Void) async -> Void {
            await openAI
                .chatFollow(index: index, userMessage: userMessage, completion: completion)
        }
}


public protocol AIChatService {
    func chat(ctx: ChatContext, completion: @escaping (_: Int, _: ResponseMessage) -> Void) async -> Void
    func chatFollow(
        index: Int,
        userMessage: String,
        completion: @escaping (_: Int, _: ResponseMessage) -> Void) async -> Void
}


public class ResponseMessage: ObservableObject, Identifiable, Equatable, @unchecked Sendable{
    public static func == (lhs: ResponseMessage, rhs: ResponseMessage) -> Bool {
        lhs.id == rhs.id
    }

    public enum Status: String {
        case initial, updating, finished, failure
    }

    public enum Role: String {
        case assistant, tool, user, system
    }

    public var id = UUID()
    @Published var message: String
    @Published var role: Role
    @Published var status: Status
    var new: Bool = false // new start of message

    init(id: UUID = UUID(), message: String, role: Role, new: Bool = false, status: Status = .initial) {
        self.id = id
        self.message = message
        self.role = role
        self.new = new
        self.status = status
    }
}


func systemPrompt() -> String{
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale.current
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let localDate = dateFormatter.string(from: Date())

    let language = getCurrentAppLanguage()
    var currentLocation = ""
    if let location = LocationManager.shared.place {
        currentLocation = "I'm at \(location)"
    }
    return """
                      Current time is \(localDate).
                      \(currentLocation)
                      You are a tool running on macOS called Selected. You can help user do anything.
                      The system language is \(language), you should try to reply in \(language) as much as possible, unless the user specifies to use another language, such as specifying to translate into a certain language.
                      
                      Please provide clear and concise answers to the following questions. If your response includes any mathematical formulas, please format them using LaTeX and enclose the formulas within double dollar signs ($$). For example: $$E = mc^2$$.
                      """
}
