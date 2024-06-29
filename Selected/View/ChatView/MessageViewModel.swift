//
//  MessageViewModel.swift
//  Selected
//
//  Created by sake on 2024/6/29.
//

import Foundation

class MessageViewModel: ObservableObject {
    @Published var messages: [ResponseMessage] = []
    var chatService: AIChatService

    init(chatService: AIChatService) {
        self.chatService = chatService
        self.messages.append(ResponseMessage(message: "waiting", role: "none"))
    }


    func fetchMessages(content: String, options: [String:String]) async -> Void{
        await chatService.chat(content: content, options: options) { [weak self]  index, message in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.messages.count < index+1 {
                    self.messages.append(ResponseMessage(message: "", role:  message.role))
                }

                if message.role != self.messages[index].role {
                    self.messages[index].role = message.role
                }

                if message.new {
                    self.messages[index].message = message.message
                } else {
                    self.messages[index].message += message.message
                }
            }
        }
    }
}