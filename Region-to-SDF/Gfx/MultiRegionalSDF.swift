//
//  MultiRegionalSDF.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 07/05/2026.
//

import Foundation

class MultiRegionalDF {
    let regionCount: Int
    var regions: SimpleImage<Int>
    private var distances: SimpleImage<Float>
    private var closestParent: SimpleImage<Coord2D>
    private var maxDistancePerRegion: [Float]
    
    var width: Int {
        get {
            return distances.width
        }
    }
    
    var height: Int {
        get {
            return distances.height
        }
    }
    
    init(sampler: ImageSampler, regionColors: Palette) {
        let w = sampler.width
        let h = sampler.height
        regionCount = regionColors.count
        regions = SimpleImage<Int>(width: w, height: h, repeating: 0)
        regions.setAll { i, coord in
            let s: UintColorTuple = sampler.get(coord: coord)
            let color = ColorRGB(s)
            let colorsSorted = regionColors.sorted { Diff2($0, color) < Diff2($1, color) }
            guard let closestColor = colorsSorted.first else {
                return 0
            }
            let index = regionColors.firstIndex { $0.hex == closestColor.hex }
            guard let index = index else {
                return 0
            }
            return index
        }
        distances = SimpleImage<Float>(width: w, height: h, repeating: RegionalSDF.BigValue)
        closestParent = SimpleImage<Coord2D>(width: w, height: h, repeating: (-1,-1))
        maxDistancePerRegion = [Float].init(repeating: 0, count: regionCount)
    }
    
    func computeDF(debugIterationFn: ((Int)->())? = nil) throws {
        let INF = RegionalSDF.BigValue
        closestParent.clear(value: (-1,1))

        let neighbors: [(dx:Int, dy:Int, cost: Float)] = [
            (-1, 0, 1), (1, 0, 1), (0, -1, 1), (0, 1, 1),
            (-1,-1, Float(sqrt(2.0))), (1,-1, Float(sqrt(2.0))), (-1,1, Float(sqrt(2.0))), (1,1, Float(sqrt(2.0)))
        ]
        
        // 1) Init boundary pixels (any pixel that has a neighbor of a different region)
        distances.setAll { i, coord in
            var minDist = INF
            let r = regions.data[i]
            for n in neighbors {
                let c = (x: coord.x + n.dx, y: coord.y + n.dy)
                if !regions.isValid(c) {
                    // treat image borders as a change in region
                    if n.cost < minDist {
                        minDist = n.cost
                        closestParent.data[i] = c
                    }
                } else if regions.getValue(c) != r {
                    // crossed to a different region
                    if n.cost < minDist {
                        minDist = n.cost
                        closestParent.data[i] = c
                    }
                }
                if minDist == 1 {
                    // no point in check more, because there's no cost smaller than 1
                    break
                }
            }
            return minDist
        }
        if let fn = debugIterationFn { fn(0) }
        
        // 2) Multi-source Dijkstra
        let dijkstra = Dijkstra()
        for y in 0..<height {
            for x in 0..<width {
                let d = distances.getValue((x,y))
                if d < INF {
                    dijkstra.heapPush(Dijkstra.Node(d: d, x: x, y: y))
                }
            }
        }

        var popped = 0
        while let node = dijkstra.heapPop() {
            popped += 1
            let c = (node.x, node.y)
            if node.d > distances.getValue(c) { continue } // stale
            for nb in neighbors {
                let nx = node.x + nb.dx
                let ny = node.y + nb.dy
                let q = (nx, ny)
                if !distances.isValid(q) { continue }
                let nd = node.d + nb.cost
                if nd < distances.getValue(q) {
                    distances.setValue(nd, at: q)
                    closestParent.setValue(c, at: q)
                    dijkstra.heapPush(Dijkstra.Node(d: nd, x: nx, y: ny))
                }
            }
            if let fn = debugIterationFn { fn(popped) }
        }
        
        // 3) Remember max distance of each region and normalize each region separately
        maxDistancePerRegion = [Float].init(repeating: 0, count: regionCount)
        
        for i in 0..<regions.data.count {
            let r = regions.data[i]
            let d = distances.data[i]
            maxDistancePerRegion[r] = max(maxDistancePerRegion[r], d)
        }
        
        // normalize. The normalized DF corresponds to density with linear falloff
        for i in 0..<distances.data.count {
            let r = regions.data[i]
            let maxD = maxDistancePerRegion[r]
            distances.data[i] = distances.data[i] / maxD
        }

    }

    func distancesToGrayImage() -> SimpleImage<UInt8> {
        let w = distances.width
        let h = distances.height
        var img = SimpleImage<UInt8>(width: w, height: h, repeating: 0)
        // hypotenuse
        let maxDistance = sqrtf(Float(w * w + h * h))
        img.data = distances.data.map { value in
            let normalized = value / maxDistance
            // 0..1
            let u = Clamp(normalized, low: 0, high: 1)
            return UInt8(roundf(255.0 * u))
        }
        return img
    }
    
    func normalizedDistancesToGrayImage() -> SimpleImage<UInt8> {
        var img = SimpleImage<UInt8>(width: width, height: height, repeating: 0)
        img.data = distances.data.map { value in
            let u = Clamp(value, low: 0, high: 1)
            return UInt8(roundf(255.0 * u))
        }
        return img
    }

}
