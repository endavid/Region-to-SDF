//
//  CircularHarmonics.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 28/04/2026.
//

struct CircularHarmonics {
    let order: Int   // max frequency n
    var a: [Float]   // cosine coefficients
    var b: [Float]   // sine coefficients
    
    init(order: Int) {
        self.order = order
        self.a = Array(repeating: 0, count: order + 1)
        self.b = Array(repeating: 0, count: order + 1)
    }
}
