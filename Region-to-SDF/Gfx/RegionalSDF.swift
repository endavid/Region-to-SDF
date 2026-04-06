//
//  RegionalSDF.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 03/04/2026.
//

import Foundation

public enum RegionalSDFError: Error {
    case noRegionFound
}

class RegionalSDF {
    static let BigValue: Float = 1e10
    var distances: SimpleImage<Float>
    private var visited: SimpleImage<UInt8>
    
    func get(coord: Coord2D) -> Float {
        return distances.getValue(coord)
    }
    
    init(sampler: ImageSampler, regionColor: UintColorTuple, epsilon: Float = 5.0 / 255.0) {
        distances = SimpleImage<Float>(width: sampler.width, height: sampler.height, value: 0)
        for y in 0..<sampler.height {
            for x in 0..<sampler.width {
                let sample: UintColorTuple = sampler.get(coord: (x, y))
                // very big distances, but negative if inside the region
                let v: Float = IsClose(sample, regionColor, epsilon: epsilon) ? -RegionalSDF.BigValue : RegionalSDF.BigValue
                distances.setValue(v, at: (x,y))
            }
        }
        visited = SimpleImage<UInt8>(width: sampler.width, height: sampler.height, value: 0)
    }
    
    /// Raster algorithm to compute SDF.
    /// I go in raster order to find region borders, and then iterate until all the image is filled with distances.
    func computeSDF(debugIterationFn: ((Int)->())? = nil) throws {
        var missingData = 0
        var iteration: Int = 0
        var changed = distances.width * distances.height
        if let fn = debugIterationFn {
            fn(iteration)
        }
        while changed > 0 {
            iteration += 1
            missingData = 0
            changed = 0
            for y in 0..<distances.height {
                for x in 0..<distances.width {
                    let c = (x, y)
                    let v = get(coord: c)
                    let d = abs(v)
                    var neighbors = getNeighbors(c, isOutside: v > 0)
                    if neighbors.isEmpty {
                        continue
                    }
                    neighbors.sort { $0.cost < $1.cost }
                    let best = neighbors.first!.cost
                    if best < d {
                        distances.setValue(v > 0 ? best : -best, at: c)
                        changed += 1
                    } else if d == RegionalSDF.BigValue {
                        missingData += 1
                    }
                }
            }
            if let fn = debugIterationFn {
                fn(iteration)
            }
        }
        if missingData > 0 {
            throw RegionalSDFError.noRegionFound
        }
    }
    
    private func getNeighbors(_ c: Coord2D, isOutside: Bool) -> [(p: Coord2D, cost: Float)] {
        let neighbors: [(p: Coord2D, cost: Float)] = distances.get4Neighbors(c).compactMap { n in
            if !distances.isValid(n) {
                // we reached the image border
                if isOutside {
                    // if we are outside, the distance only grows
                    return nil
                }
                // if we are inside, we reached a border
                return (n, 1)
            }
            let v = distances.getValue(n)
            if (isOutside && v < 0) || (!isOutside && v > 0) {
                // a change of sign indicate we found a boundary, so stop
                return (n, 1)
            }
            return (n, 1 + abs(v))
        }
        let diagonals: [(p: Coord2D, cost: Float)] = distances.get4Diagonals(c).compactMap { n in
            if !distances.isValid(n) {
                // we reached the image border
                if isOutside {
                    // if we are outside, the distance only grows
                    return nil
                }
                // if we are inside, we reached a border. Diagonal distance is sqrt(2)
                return (n, sqrt(2.0))
            }
            let v = distances.getValue(n)
            if (isOutside && v < 0) || (!isOutside && v > 0) {
                // a change of sign indicate we found a boundary, so stop
                return (n, sqrt(2.0))
            }
            return (n, sqrt(2.0) + abs(v))
        }
        return neighbors + diagonals
    }
    
    func toGrayImage() -> SimpleImage<UInt8> {
        let w = distances.width
        let h = distances.height
        var img = SimpleImage<UInt8>(width: w, height: h)
        // hypotenuse
        let maxDistance = sqrtf(Float(w * w + h * h))
        img.data = distances.data.map { value in
            // -1..1
            let normalized = value / maxDistance
            // 0..1
            let u = Clamp(normalized * 0.5 + 0.5, low: 0, high: 1)
            return UInt8(roundf(255.0 * u))
        }
        return img
    }
    
    func toRGImage(maxContrast: Bool = false) -> SimpleImage<UInt32> {
        let w = distances.width
        let h = distances.height
        var img = SimpleImage<UInt32>(width: w, height: h)
        // hypotenuse
        let maxDistance = sqrtf(Float(w * w + h * h))
        var maxRed = maxDistance
        var minGreen = -maxDistance
        if maxContrast {
            maxRed = distances.data.reduce(0) { max, value in
                let d = min(value, maxDistance)
                return max > d ? max : d
            }
            minGreen = distances.data.reduce(0) { minV, value in
                let d = max(value, -maxDistance)
                return minV < d ? minV : d
            }
        }
        img.data = distances.data.map { value in
            // -1..1
            let positive = Clamp(value / maxRed, low: 0, high: 1)
            let negative = Clamp(value / minGreen, low: 0, high: 1)
            let r = UInt32(roundf(255.0 * positive))
            let g = UInt32(roundf(255.0 * negative))
            return UInt32(r << 24 | g << 16 | 0x00ff)
        }
        return img
    }

}
