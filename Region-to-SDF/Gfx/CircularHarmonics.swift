//
//  CircularHarmonics.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 28/04/2026.
//
import simd

struct CircularHarmonics {
    let order: Int   // max frequency n
    var a: [Float]   // cosine coefficients
    var b: [Float]   // sine coefficients
    
    init(order: Int) {
        self.order = order
        self.a = Array(repeating: 0, count: order + 1)
        self.b = Array(repeating: 0, count: order + 1)
    }
    
    mutating func setCoefficient(k: Int, real: Float, imag: Float) {
        a[k] = real
        b[k] = imag
    }
    
    func evaluate(direction: SIMD2<Float>) -> Float {
        let x = direction.x // cos(theta)
        let y = direction.y // sin(theta)

        // Start with DC term
        var result = a[0]

        // If order is zero, return immediately
        if order == 0 { return result }

        // cos(theta), sin(theta)
        var c = x
        var s = y
        // n = 1 term
        result += a[1] * c + b[1] * s

        // For n >= 2, use angle addition recurrence:
        // cos((n+1)θ) = cos θ * cos(nθ) - sin θ * sin(nθ)
        // sin((n+1)θ) = sin θ * cos(nθ) + cos θ * sin(nθ)
        if order >= 2 {
            for n in 2...order {
                let nextC = x * c - y * s
                let nextS = y * c + x * s
                c = nextC
                s = nextS
                result += a[n] * c + b[n] * s
            }
        }

        return result
    }
}

