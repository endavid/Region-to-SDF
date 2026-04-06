//
//  Log.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 06/04/2026.
//
import Foundation
import SwiftUI
import os.log

// https://docs.swift.org/swift-book/ReferenceManual/Expressions.html
// https://stackoverflow.com/a/24402688/1765629
func logFunctionName(file: String = #file, fn: String = #function) {
    #if DEBUG
    let base = (file as NSString).lastPathComponent
    NSLog("\(base): \(fn)")
    #endif
}

func logDebug(_ text: String) {
    #if DEBUG
    print(text)
    #endif
}

class Logger {
    static let shared = Logger() // lazy init by default
    private let _log: OSLog
    
    init() {
        let bundleName = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String ?? "Mantis Shrimp"
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        _log = OSLog(subsystem: bundleId, category: bundleName)
    }
    
    func log(_ message: String) {
        os_log(.info, log: _log, "%@", message)
    }
    func err(_ message: String) {
        os_log(.error, log: _log, "%@", message)
    }
}

func popMessage(title: String, message: String, alignment: NSTextAlignment = .center) {
    logDebug(message)
    DispatchQueue.main.async {
        let alert = NSAlert()
        alert.messageText = title
        if alignment == .center {
            alert.informativeText = message
        } else {
            // Create a custom text field
            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
            textField.stringValue = message
            textField.isEditable = false
            textField.isBordered = false
            textField.backgroundColor = NSColor.clear
            textField.alignment = alignment
            alert.accessoryView = textField
        }
        //alert.icon = NSImage(named: "AppIcon")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
