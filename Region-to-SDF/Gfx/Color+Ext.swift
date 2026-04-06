//
//  Color+Ext.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 03/04/2026.
//

import Foundation
import AppKit
import SwiftUI

typealias UintColorTuple = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

extension NSColor {
    convenience init(_ c: UintColorTuple) {
        self.init(srgbRed: (CGFloat)(c.r)/255.0, green: (CGFloat)(c.g)/255.0, blue: (CGFloat)(c.b)/255.0, alpha: (CGFloat)(c.a)/255.0)
    }
}

extension Color {
    
    var colorTuple: UintColorTuple {
        get {
            let ns = NSColor(self)
            guard let conv = ns.usingColorSpace(.sRGB) else { return (0,0,0,0) }
            let r = UInt8(round(conv.redComponent * 255))
            let g = UInt8(round(conv.greenComponent * 255))
            let b = UInt8(round(conv.blueComponent * 255))
            let a = UInt8(round(conv.alphaComponent * 255))
            return (r,g,b,a)
        }
    }
    
    func hexDescription() -> String {
        #if canImport(AppKit)
        // Convert to sRGB NSColor to get components
        let ns = NSColor(self)
        guard let conv = ns.usingColorSpace(.sRGB) else { return "#??????" }
        let r = Int(round(conv.redComponent * 255))
        let g = Int(round(conv.greenComponent * 255))
        let b = Int(round(conv.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        return "#??????"
        #endif
    }
}
