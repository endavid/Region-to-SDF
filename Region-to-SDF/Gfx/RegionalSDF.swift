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
    private var distances: SimpleImage<Float>
    private var visited: SimpleImage<UInt8>
    private var inside: SimpleImage<UInt8>
    private var closestParent: SimpleImage<Int>
        
    func isInside(_ c: Coord2D) -> Bool {
        return inside.getValue(c) == 1
    }
    
    func getSDF() -> SimpleImage<Float> {
        let w = distances.width
        let h = distances.height
        var sdf = SimpleImage<Float>(width: w, height: h, repeating: RegionalSDF.BigValue)
        for i in 0..<(w*h) {
            let c = distances.indexToCoord(i)
            let sgn: Float = (inside.getValue(c) == 1) ? -1.0 : 1.0
            sdf.data[i] = sgn * distances.getValue(c)
        }
        return sdf
    }
    
    func getEuclideanSDF() -> SimpleImage<Float> {
        let w = distances.width
        let h = distances.height
        var sdf = SimpleImage<Float>(width: w, height: h, repeating: RegionalSDF.BigValue)
        for i in 0..<(w*h) {
            let c0 = distances.indexToCoord(i)
            let p = closestParent.data[i]
            // p < 0 => not initialized yet
            let c1 = distances.indexToCoord(p < 0 ? i : p)
            let sgn: Float = (inside.getValue(c0) == 1) ? -1.0 : 1.0
            sdf.data[i] = sgn * Length(c1 - c0)
        }
        return sdf
    }
    
    func getClosestBorder() -> SimpleImage<Int> {
        return closestParent
    }
    
    init(sampler: ImageSampler, regionColor: UintColorTuple, epsilon: Float = 5.0 / 255.0) {
        let w = sampler.width
        let h = sampler.height
        distances = SimpleImage<Float>(width: w, height: h, repeating: RegionalSDF.BigValue)
        visited = SimpleImage<UInt8>(width: w, height: h, repeating: 0)
        inside = SimpleImage<UInt8>(width: w, height: h, repeating: 0)
        closestParent = SimpleImage<Int>(width: w, height: h, repeating: -1)
        // Build inside mask
        for y in 0..<h {
            for x in 0..<w {
                let s: UintColorTuple = sampler.get(coord: (x, y))
                let isIn = IsClose(s, regionColor, epsilon: epsilon) ? UInt8(1) : UInt8(0)
                inside.setValue(isIn, at: (x,y))
            }
        }
    }
    
    /// Raster algorithm to compute SDF.
    /// I go in raster order to find region borders, and then iterate until all the image is filled with distances.
    func computeSDF(debugIterationFn: ((Int)->())? = nil) throws {
        let w = distances.width
        let h = distances.height
        let INF = RegionalSDF.BigValue
        // Reset distances and parents
        distances.clear(value: INF)
        closestParent.clear(value: -1)

        // 1) Collect boundary pixels (inside changes across 4-neighbors)
        var frontier: [Coord2D] = []
        frontier.reserveCapacity(w*h/8)
        for y in 0..<h {
            for x in 0..<w {
                let c = (x,y)
                let inC = inside.getValue(c) == 1
                var isBoundary = false
                // NSEW check
                for n in distances.get4Neighbors(c) {
                    if distances.isValid(n) {
                        let inN = inside.getValue(n) == 1
                        if inN != inC { isBoundary = true; break }
                    }
                }
                if isBoundary {
                    distances.setValue(0, at: c)
                    closestParent.setValue(closestParent.index(c), at: c)
                    frontier.append(c)
                }
            }
        }
        if frontier.isEmpty {
            throw RegionalSDFError.noRegionFound
        }

        // 2) Multi-source Dijkstra
        struct Node { let d: Float; let x: Int; let y: Int }
        // Simple binary heap
        var heap: [Node] = []
        func heapPush(_ node: Node) {
            heap.append(node)
            var i = heap.count - 1
            while i > 0 {
                let p = (i - 1) >> 1
                if heap[p].d <= heap[i].d { break }
                heap.swapAt(p, i)
                i = p
            }
        }
        func heapPop() -> Node? {
            guard !heap.isEmpty else { return nil }
            let res = heap[0]
            let last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last
                var i = 0
                while true {
                    let l = i * 2 + 1
                    let r = l + 1
                    var m = i
                    if l < heap.count && heap[l].d < heap[m].d { m = l }
                    if r < heap.count && heap[r].d < heap[m].d { m = r }
                    if m == i { break }
                    heap.swapAt(i, m)
                    i = m
                }
            }
            return res
        }

        for c in frontier { heapPush(Node(d: 0, x: c.x, y: c.y)) }

        let neighbors: [(dx:Int, dy:Int, cost: Float)] = [
            (-1, 0, 1), (1, 0, 1), (0, -1, 1), (0, 1, 1),
            (-1,-1, Float(sqrt(2.0))), (1,-1, Float(sqrt(2.0))), (-1,1, Float(sqrt(2.0))), (1,1, Float(sqrt(2.0)))
        ]

        var popped = 0
        while let node = heapPop() {
            popped += 1
            let c = (node.x, node.y)
            if node.d > distances.getValue(c) { continue } // stale
            let parentIdx = closestParent.getValue(c)
            for nb in neighbors {
                let nx = node.x + nb.dx
                let ny = node.y + nb.dy
                let q = (nx, ny)
                if !distances.isValid(q) { continue }
                let nd = node.d + nb.cost
                if nd < distances.getValue(q) {
                    distances.setValue(nd, at: q)
                    if parentIdx >= 0 {
                        closestParent.setValue(parentIdx, at: q)
                    } else {
                        closestParent.setValue(closestParent.index(c), at: q)
                    }
                    heapPush(Node(d: nd, x: nx, y: ny))
                }
            }
            if let fn = debugIterationFn { fn(popped) }
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
        return RegionalSDF.distanceToGrayImage(getEuclideanSDF())
    }
    
    func toRGImage(maxContrast: Bool = false) -> SimpleImage<UInt32> {
        return RegionalSDF.distanceToRGImage(getEuclideanSDF(), maxContrast: maxContrast)
    }

    static func distanceToGrayImage(_ sdf: SimpleImage<Float>) -> SimpleImage<UInt8> {
        let w = sdf.width
        let h = sdf.height
        var img = SimpleImage<UInt8>(width: w, height: h, repeating: 0)
        // hypotenuse
        let maxDistance = sqrtf(Float(w * w + h * h))
        img.data = sdf.data.map { value in
            // -1..1
            let normalized = value / maxDistance
            // 0..1
            let u = Clamp(normalized * 0.5 + 0.5, low: 0, high: 1)
            return UInt8(roundf(255.0 * u))
        }
        return img
    }
    
    static func distanceToRGImage(_ sdf: SimpleImage<Float>, maxContrast: Bool = false) -> SimpleImage<UInt32> {
        let w = sdf.width
        let h = sdf.height
        var img = SimpleImage<UInt32>(width: w, height: h, repeating: 0)
        // hypotenuse
        let maxDistance = sqrtf(Float(w * w + h * h))
        var maxRed = maxDistance
        var minGreen = -maxDistance
        if maxContrast {
            maxRed = sdf.data.reduce(0) { max, value in
                let d = min(value, maxDistance)
                return max > d ? max : d
            }
            minGreen = sdf.data.reduce(0) { minV, value in
                let d = max(value, -maxDistance)
                return minV < d ? minV : d
            }
        }
        if IsClose(maxRed, 0) {
            maxRed = 0.001
        }
        if IsClose(minGreen, 0) {
            minGreen = 0.001
        }
        img.data = sdf.data.map { value in
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

