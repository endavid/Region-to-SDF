//
//  Math.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 03/04/2026.
//

import Foundation

let PI      : Float = 3.1415926535897932384626433832795
let PI_2    = 0.5 * PI
let PI2     = 2.0 * PI
let PI_INV  = 1.0 / PI
let NORM_SQR_ERROR_TOLERANCE : Float = 0.001
let π       : Double = Double(PI)

/// Converts angle in degrees to radians
func DegToRad(_ angle: Float) -> Float {
    return angle * (PI/180.0)
}
func IsClose(_ a: Float, _ b: Float, epsilon: Float = 0.0001) -> Bool {
    return ( fabsf( a - b ) < epsilon )
}
func IsClose(_ a: Double, _ b: Double, epsilon: Double = 0.0001) -> Bool {
    return ( abs( a - b ) < epsilon )
}
/// Compares 2 colors, ignoring alpha
func IsClose(_ a: ColorRGB, _ b: ColorRGB, epsilon: Float = 0.001) -> Bool {
    let r = Float(a.r) - Float(b.r)
    let g = Float(a.g) - Float(b.g)
    let b = Float(a.b) - Float(b.b)
    return r * r + g * g + b * b < epsilon * epsilon
}

/// Gets the sign of a number
func Sign(_ n: Float) -> Float {
    return (n>=0) ?1:-1
}
/// Max
func Max(_ a: Float,_ b: Float) -> Float {
    return (a>=b) ?a:b
}
/// Min
func Min(_ a: Float,_ b: Float) -> Float {
    return (a<=b) ?a:b
}
/// Clamp
func Clamp(_ value: Float, low: Float, high: Float) -> Float {
    return (value<low) ?low:(value>high) ?high:value
}
func Clamp(_ value: Int, low: Int, high: Int) -> Int {
    return (value<low) ?low:(value>high) ?high:value
}
/// Random Int. Preferred to rand() % upperBound
func Rand(_ upperBound: UInt32) -> UInt32 {
    return arc4random_uniform(upperBound)
}
/// Random Float between 0 and 1
func Randf() -> Float {
    return Float(Rand(10000)) * 0.0001
}
/// Choose Float digits
func Round(_ a: Double, digits: Int) -> Double {
    let m = pow(10, Double(digits))
    let rounded = Int64(a * m)
    return Double(rounded) / m
}

func +(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    return CGPoint(x: a.x + b.x, y: a.y + b.y)
}

func -(_ a: Coord2D, _ b: Coord2D) -> Coord2D {
    return (a.x - b.x, a.y - b.y)
}

func Length(_ v: Coord2D) -> Float {
    return sqrtf(Float(v.x * v.x + v.y * v.y))
}

func LengthD(_ v: CGPoint) -> Double {
    return sqrt(v.x * v.x + v.y * v.y)
}

func Normalize(_ v: CGPoint) -> CGPoint {
    let n = max(1e-10, LengthD(v))
    return CGPoint(x: v.x / n, y: v.y / n)
}

func Dot(_ a: CGPoint, _ b: CGPoint) -> Double {
    return a.x * b.x + a.y * b.y
}

// Factorial of a number with a cache
func Factorial(_ n: Int) -> Double { // 64-bit ints aren't enough for big factorials
    struct CacheData {
        static let maxCount = 33
        static var isFactorialCached = false
        static var factorialCache : [Double] = [Double](repeating: 1, count: maxCount)
    }
    
    if (n < 2) {
        return 1
    }
    if (!CacheData.isFactorialCached) {
        // init cache
        var r : Double = 1
        for c in 0..<CacheData.maxCount {
            r *= Double(c+2)
            CacheData.factorialCache[c] = r
        }
        CacheData.isFactorialCached = true
    }
    if (n - 2 < CacheData.maxCount) {
        return CacheData.factorialCache[n-2]
    }
    var r = CacheData.factorialCache[CacheData.maxCount-1]
    for i in (CacheData.maxCount+2)...n {
        r *= Double(i)
    }
    return r
}
