//
//  SharingButton.swift
//  Selected
//
//  Created by sake on 2024/3/27.
//

import Foundation
import SwiftUI


// https://stackoverflow.com/a/60955909
struct SharingsPicker: NSViewRepresentable {
    @Binding var isPresented: Bool
    var sharingItems: [Any] = []
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            let picker = NSSharingServicePicker(items: sharingItems)
            picker.delegate = context.coordinator
            
            // !! MUST BE CALLED IN ASYNC, otherwise blocks update
            DispatchQueue.main.async {
                picker.show(relativeTo: .zero, of: nsView, preferredEdge: .minY)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(owner: self)
    }
    
    class Coordinator: NSObject, @preconcurrency NSSharingServicePickerDelegate {
        let owner: SharingsPicker
        
        init(owner: SharingsPicker) {
            self.owner = owner
        }
        
        @MainActor func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            sharingServicePicker.delegate = nil   // << cleanup
            self.owner.isPresented = false        // << dismiss
            showingSharingPicker = false
        }
    }
}

// When in showing SharingPicker, we should avoid close popbar window by accident.
@MainActor var showingSharingPicker = false

struct SharingButton: View {
    @State private var showPicker = false
    var message: String
    var body: some View {
        BarButton(icon: "symbol:square.and.arrow.up", title: "share", clicked: {
            _ in
            showingSharingPicker = true
            self.showPicker = true
        })
        .background(SharingsPicker(isPresented: $showPicker, sharingItems: [message]))
    }
}
