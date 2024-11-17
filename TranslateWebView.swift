//
//  TranslateWebView.swift
//  Translate Menu
//
//  Created by Adrián Moreno Peña on 17/11/2024.
//  Copyright © 2024 Adrian Moreno Peña. All rights reserved.
//

import WebKit

class TranslateWebView: WKWebView {

    override var acceptsFirstResponder: Bool { return true }
    override func becomeFirstResponder() -> Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        NSLog("keyDown translateWebView: " + (event.characters ?? "") )
        
        
        switch event.modifierFlags.intersection(.deviceIndependentFlagsMask) {
        case [.command] where event.characters == "c":
            NSLog("c -> copy")
            self.copy(event)
        case [.command] where event.characters == "v":
            self.paste(event)
        default:
            break
        }
        
        if [48, 34, 40, 4, 1, 3, 32].contains(event.keyCode) {
            // no funk
        } else {
            NSLog("super key down")
            super.keyDown(with: event)
        }
        
        
        
    }
    
    public func keyPress(event: NSEvent){
        super.keyDown(with: event)
    }
    
    
    @IBAction func copy(_ sender: Any?) {
        // Implement your copy logic here
        NSLog("copy!")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Your data to copy", forType: .string)
    }

    @IBAction func paste(_ sender: Any?) {
        NSLog("paste!")

        // Implement your paste logic here
        let pasteboard = NSPasteboard.general
        if let copiedString = pasteboard.string(forType: .string) {
            // Use the copied string
            print("Pasted: \(copiedString)")
            pasteboard.
        }
    }
    
    
}
