//
//  Color.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 09/04/2026.
//


//
//  Color.swift
//  advent2023
//
//  Created by David Gavilan on 03/12/2023.
//

import Foundation

typealias Palette = [ColorRGB]


struct ColorRGB {
    static let black = ColorRGB(hexValue: 0x0)
    static let white = ColorRGB(hexValue: 0xffffff)
    static let gray = ColorRGB(hexValue: 0x7f7f7f)
    static let red = ColorRGB(hexValue: 0xff0000)
    static let green = ColorRGB(hexValue: 0x00ff00)
    static let blue = ColorRGB(hexValue: 0x0000ff)
    static let yellow = ColorRGB(hexValue: 0xffff00)
    static let magenta = ColorRGB(hexValue: 0xff00ff)
    static let cyan = ColorRGB(hexValue: 0x00ffff)
    // http://endavid.com/index.php?entry=89
    static let enDavid_brown1 = ColorRGB(hexValue: 0x1A1717)
    static let enDavid_brown2 = ColorRGB(hexValue: 0x2B2626)
    static let enDavid_gray = ColorRGB(hexValue: 0x4C4337)
    static let enDavid_brown3 = ColorRGB(hexValue: 0x47564F)
    static let enDavid_white = ColorRGB(hexValue: 0xE6E6E6)
    static let enDavid_black = ColorRGB(hexValue: 0x1A1717)
    static let enDavid_orange = ColorRGB(hexValue: 0xFF8000)
    static let enDavid_darkOrange = ColorRGB(hexValue: 0xBD642A)
    static let enDavid_lightBrown = ColorRGB(hexValue: 0xDBAF67)
    static let enDavid_lightGreen = ColorRGB(hexValue: 0x3A7D4D)
    static let enDavid_red = ColorRGB(r: 231, g: 87, b: 81)
    static let enDavid_green = ColorRGB(r: 59, g: 124, b: 76)
    
    static func grayScale(maxValue: Int) -> Palette {
        return (0...maxValue).map {
            let c = UInt8(255 * $0 / maxValue)
            return ColorRGB(r: c, g: c, b: c)
        }
    }
        
    static func redToYellow(maxValue: Int) -> Palette {
        return (0...maxValue).map {
            let r = UInt8(128 + 127 * $0 / maxValue)
            let g = UInt8(255 * $0 / maxValue)
            return ColorRGB(r: r, g: g, b: 0)
        }
    }
    
    static func gradient(low: ColorRGB, high: ColorRGB, maxValue: Int) -> Palette {
        return (0...maxValue).map {
            let a = Double($0) / Double(maxValue)
            return lerp(low, high, alpha: a)
        }
    }
    
    static func heatmap(low: ColorRGB, mid: ColorRGB, high: ColorRGB, maxValue: Int) -> Palette {
        return (0...maxValue).map {
            let a = Double($0) / Double(maxValue)
            return lerp(low, mid, high, alpha: a)
        }
    }
    
    static func heatmap(low: ColorRGB, mid1: ColorRGB, mid2: ColorRGB, high: ColorRGB, maxValue: Int) -> Palette {
        return (0...maxValue).map {
            let a = Double($0) / Double(maxValue)
            return lerp(low, mid1, mid2, high, alpha: a)
        }
    }
        
    let r: UInt8
    let g: UInt8
    let b: UInt8
    
    var tuple: UintColorTuple {
        get {
            return (r, g, b, 255)
        }
    }
    
    var hexString: String {
        get {
            return String(format: "%02X%02X%02X", r, g, b)
        }
    }
    
    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }
    
    init(_ c: UintColorTuple) {
        // ignore alpha
        self.r = c.r
        self.g = c.g
        self.b = c.b
    }
    
    init(hexValue: Int) {
        r = UInt8((hexValue >> 16) & 0xff)
        g = UInt8((hexValue >> 8) & 0xff)
        b = UInt8(hexValue & 0xff)
    }
}

func lerp(_ a: UInt8, _ b: UInt8, alpha: Double) -> UInt8 {
    let v = (1-alpha) * Double(a) + alpha * Double(b)
    return UInt8(round(v))
}

func lerp(_ a: ColorRGB, _ b: ColorRGB, alpha: Double) -> ColorRGB {
    let r = lerp(a.r, b.r, alpha: alpha)
    let g = lerp(a.g, b.g, alpha: alpha)
    let b = lerp(a.b, b.b, alpha: alpha)
    return ColorRGB(r: r, g: g, b: b)
}

func lerp(_ a: ColorRGB, _ b: ColorRGB, _ c: ColorRGB, alpha: Double) -> ColorRGB {
    if alpha < 0.5 {
        return lerp(a, b, alpha: 2 * alpha)
    }
    return lerp(b, c, alpha: 2 * alpha - 1)
}

func lerp(_ a: ColorRGB, _ b: ColorRGB, _ c: ColorRGB, _ d: ColorRGB, alpha: Double) -> ColorRGB {
    if alpha < 1/3 {
        return lerp(a, b, alpha: 3 * alpha)
    }
    if alpha >= 1/3 && alpha < 2/3 {
        return lerp(b, c, alpha: 3 * alpha - 1)
    }
    return lerp(c, d, alpha: 3 * alpha - 2)
}

