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
    private var density: SimpleImage<Float>
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
        regions.setAllParallel { i, coord in
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
        density = SimpleImage<Float>(width: w, height: h, repeating: 0)
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
        distances.setAllParallel { i, coord in
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
        density.setAllParallel { i, _ in
            let r = regions.data[i]
            let maxD = maxDistancePerRegion[r]
            return distances.data[i] / maxD
        }
    }
    
    func computeDensityField(ftOrder: Int = 4) -> SimpleImage<CircularHarmonics> {
        let w = width
        let h = height
        let hyp = Float(sqrt(Double(w * w + h * h)))
        // Output image of CircularHarmonics
        let chTemplate = CircularHarmonics(order: ftOrder)
        var out = SimpleImage<CircularHarmonics>(width: w, height: h, repeating: chTemplate)

        // Precompute 32 directions
        let dirCount = 32
        let twoPi = Float.pi * 2
        var dirs: [(dx: Float, dy: Float, angle: Float)] = []
        dirs.reserveCapacity(dirCount)
        for i in 0..<dirCount {
            let theta = (twoPi * Float(i)) / Float(dirCount)
            dirs.append((cosf(theta), sinf(theta), theta))
        }
        
        // bilinear sampling with region masking
        func sampleBilinear(_ x: Float, _ y: Float, region: Int) -> Float {
            if x < 0 || y < 0 || x > Float(width - 1) || y > Float(height - 1) { return 0 }
            let x0 = Int(floorf(x))
            let y0 = Int(floorf(y))
            let x1 = min(x0 + 1, width - 1)
            let y1 = min(y0 + 1, height - 1)
            let tx = x - Float(x0)
            let ty = y - Float(y0)
            let v00 = regions.getValue((x0,y0)) == region ? density.getValue((x0, y0)) : 0
            let v10 = regions.getValue((x1, y0)) == region ? density.getValue((x1, y0)) : 0
            let v01 = regions.getValue((x0, y1)) == region ? density.getValue((x0, y1)) : 0
            let v11 = regions.getValue((x1, y1)) == region ? density.getValue((x1, y1)) : 0
            let a = v00 * (1 - tx) + v10 * tx
            let b = v01 * (1 - tx) + v11 * tx
            return a * (1 - ty) + b * ty
        }

        // Ray-march parameters
        let step: Float = 1.0 // pixel step
        let maxRadius: Float = hyp

        // For each pixel, integrate along 32 directions and compute angular DFT
        out.setAll { idx, coord in
            let r = regions.data[idx]
            let cx = Float(coord.x)
            let cy = Float(coord.y)

            // Accumulate per-direction integrals
            var integrals = [Float](repeating: 0, count: dirCount)
            for (i, d) in dirs.enumerated() {
                var t: Float = 0
                var sum: Float = 0
                while t <= maxRadius {
                    let sx = cx + d.dx * t
                    let sy = cy + d.dy * t
                    if sx < 0 || sy < 0 || sx >= Float(w) || sy >= Float(h) { break }
                    sum += sampleBilinear(sx, sy, region: r)
                    t += step
                }
                integrals[i] = sum
            }

            // Compute DFT coefficients up to `defaultOrder`
            var ch = CircularHarmonics(order: ftOrder)
            // k = 0..order (assuming DC plus harmonics)
            for k in 0...ftOrder {
                var real: Float = 0
                var imag: Float = 0
                for i in 0..<dirCount {
                    let theta = dirs[i].angle
                    let value = integrals[i]
                    real += value * cosf(Float(k) * theta)
                    imag += value * sinf(Float(k) * theta)
                }
                // normalize by number of samples
                real /= Float(dirCount)
                imag /= Float(dirCount)
                ch.setCoefficient(k: k, real: real, imag: imag)
            }
            // store the density as well, since b[0] is always zero, so useless otherwise
            ch.b[0] = density.data[idx]
            return ch
        }

        return out
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
        
    func densityToGrayImage() -> SimpleImage<UInt8> {
        var img = SimpleImage<UInt8>(width: width, height: height, repeating: 0)
        img.data = density.data.map { value in
            let u = Clamp(value, low: 0, high: 1)
            return UInt8(roundf(255.0 * u))
        }
        return img
    }

}
