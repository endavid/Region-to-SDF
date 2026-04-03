//
//  Color+Ext.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 03/04/2026.
//

import Foundation
import AppKit

extension NSColor {
    convenience init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        self.init(srgbRed: (CGFloat)(r)/255.0, green: (CGFloat)(g)/255.0, blue: (CGFloat)(b)/255.0, alpha: (CGFloat)(a)/255.0)
    }
}
