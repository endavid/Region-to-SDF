//
//  Number.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 03/04/2026.
//


import Foundation

protocol Number: Equatable, ExpressibleByIntegerLiteral {
    static var norm: Float { get }
    static var maxFloat: Float { get }
    init(_ source: Float)
    init(_ source: UInt8)
    init(_ source: UInt16)
    init(_ source: UInt32)
    var asFloat: Float { get }
}

extension UInt8: Number {
    static var maxFloat: Float { return Float(UInt8.max) }
    static var norm: Float { return UInt8.maxFloat }
    var asFloat: Float { return Float(self) }
}

extension UInt16: Number {
    static var maxFloat: Float { return Float(UInt16.max) }
    static var norm: Float { return UInt16.maxFloat }
    var asFloat: Float { return Float(self) }
}

extension UInt32: Number {
    // 4294967295 becomes 4294967300 when using floats! it goes out of UInt32 range
    static var maxFloat: Float { return 4.294967e9 }
    static var norm: Float { return UInt32.maxFloat }
    var asFloat: Float { return Float(self) }
}

extension Float: Number {
    static var maxFloat: Float { return Float.greatestFiniteMagnitude }
    static var norm: Float { return 1.0 }
    var asFloat: Float { return self }
}
