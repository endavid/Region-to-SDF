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
    
    init(sampler: ImageSampler, regionColor: ColorRGB, epsilon: Float = 5.0 / 255.0) {
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
                let isIn = IsClose(ColorRGB(s), regionColor, epsilon: epsilon) ? UInt8(1) : UInt8(0)
                inside.setValue(isIn, at: (x,y))
            }
        }
    }
    
    private func findBoundaryPixels() -> [Coord2D] {
        let w = distances.width
        let h = distances.height
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
        return frontier
    }
    
    /// Raster algorithm to compute SDF.
    /// I go in raster order to find region borders, and then iterate until all the image is filled with distances.
    func computeSDF(debugIterationFn: ((Int)->())? = nil) throws {
        let INF = RegionalSDF.BigValue
        // Reset distances and parents
        distances.clear(value: INF)
        closestParent.clear(value: -1)

        // 1) Collect boundary pixels (inside changes across 4-neighbors)
        let frontier: [Coord2D] = findBoundaryPixels()
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
        
        // the boundary is thicker than the actual region, so correct the closest parent
        for i in 0..<closestParent.data.count {
            if inside.data[i] == 0 && closestParent.data[i] == i {
                // point outside that points to itself instead of a boundary (interior) point
                let ns = inside.get4Neighbors(inside.indexToCoord(i)).filter { inside.isValid($0) && inside.getValue($0) == 1 }
                if let neighbor = ns.first {
                    // we pick the first but it could be any neighbor
                    closestParent.data[i] = inside.index(neighbor)
                }
            }
        }
    }

    func toGrayImage() -> SimpleImage<UInt8> {
        return RegionalSDF.distanceToGrayImage(getEuclideanSDF())
    }
    
    func toRGImage(maxContrast: Bool = false) -> SimpleImage<UInt32> {
        return RegionalSDF.distanceToRGImage(getEuclideanSDF(), maxContrast: maxContrast)
    }

    // MARK: - Boundary contour extraction (8-connected)
    func extractBoundaryContour() -> [Coord2D] {
        let w = inside.width
        let h = inside.height
        var boundarySet = Set<Int>()
        // Collect boundary pixels
        for y in 0..<h {
            for x in 0..<w {
                let c = (x,y)
                if inside.getValue(c) == 0 {
                    // outside
                    continue
                }
                // image borders count as contour
                let inCount = inside.get4ValidNeighbors(c).map { inside.getValue($0) }.reduce(0, +)
                if inCount < 4 { boundarySet.insert(inside.index(c)) }
            }
        }
        // for early debugging:
        //return boundarySet.map { inside.indexToCoord($0) }
        // sort it to make it deterministic -- otherwise the tests give different results depending on the starting point
        guard let startIdx = boundarySet.sorted().first else { return [] }
        var contour: [Coord2D] = []
        let firstElement = inside.indexToCoord(startIdx)
        var current = firstElement
        // 8-neighborhood offsets in clockwise order
        let offsets: [Coord2D] = [(-1,-1),(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1),(-1,0)]
        // Trace the boundary until we return to start or run out
        var prevDir = 0
        var backtrackStack: [(coord: Coord2D, directionIdx: Int)] = []
        var found = true
        while found && contour.count < w*h {
            let currentIndex = inside.index(current)
            contour.append(current)
            boundarySet.remove(currentIndex)
            found = false
            // Try neighbors, preferring continuing direction first
            var candidates: [(coord: Coord2D, directionIdx: Int)] = []
            var sawFirst = false
            for k in 0..<offsets.count {
                let idx = (prevDir + k) % offsets.count
                let n = (current.x + offsets[idx].x, current.y + offsets[idx].y)
                if !inside.isValid(n) { continue }
                if n == firstElement {
                    sawFirst = true
                } else if boundarySet.contains(inside.index(n)) {
                    candidates.append((n, idx))
                }
            }
            if let c = candidates.first {
                current = c.coord
                prevDir = c.directionIdx
                found = true
                // if there are other candidates, remember them in case we are traversing a thin edge and we have to go back
                let _ = candidates.removeFirst()
                backtrackStack.append(contentsOf: candidates)
            }
            if !found {
                if sawFirst {
                    // looped
                    break
                }
                // try going back
                if let c = backtrackStack.popLast() {
                    current = c.coord
                    prevDir = c.directionIdx
                    found = true
                }
            }
        }
        return contour
    }
    func buildBoundaryIndexMap(contour: [Coord2D]) -> [Int: Int] {
        // this boundary is thicker
        let boundaryPixels = findBoundaryPixels()
        var missingSet = Set(boundaryPixels.map { inside.index($0) }).subtracting(Set(contour.map { inside.index($0)}))
        var map: [Int: Int] = [:]
        for i in 0..<contour.count {
            let coord = contour[i]
            map[inside.index(coord)] = i
            // the boundary for SDF is thicker, so add neighbors
            for n in inside.get8ValidNeighbors(coord) {
                let indexN = inside.index(n)
                if missingSet.contains(indexN) {
                    map[indexN] = i
                    missingSet.remove(indexN)
                }
            }
        }
        // there could still be thin edges we ignored...
        for iCoord in missingSet {
            let coord = inside.indexToCoord(iCoord)
            for n in inside.get8ValidNeighbors(coord) {
                let i = inside.index(n)
                if let idx = map[i] {
                    map[iCoord] = idx
                    break
                }
            }
        }
        return map
    }

    private func angle(from p: Coord2D, to q: Coord2D) -> Float {
        let dx = Float(q.x - p.x)
        let dy = Float(q.y - p.y)
        return atan2f(dy, dx)
    }

    private func unwrap(_ theta: Float, around r: Float) -> Float {
        var t = theta
        while t - r > Float.pi { t -= 2*Float.pi }
        while t - r < -Float.pi { t += 2*Float.pi }
        return t
    }

    /// Compute left/right boundary indices for each exterior pixel.
    /// Returns two maps of size WxH with indices into the boundary contour (or -1 if none).
    func exteriorLeftRightMaps(maxSteps: Int = 48) -> (left: SimpleImage<Int>, right: SimpleImage<Int>) {
        let w = inside.width
        let h = inside.height
        var leftMap = SimpleImage<Int>(width: w, height: h, repeating: -1)
        var rightMap = SimpleImage<Int>(width: w, height: h, repeating: -1)

        let contour = extractBoundaryContour()
        guard !contour.isEmpty else { return (leftMap, rightMap) }
        let indexMap = buildBoundaryIndexMap(contour: contour)
        let contourCount = contour.count

        for y in 0..<h {
            for x in 0..<w {
                let p = (x,y)
                if isInside(p) { continue } // only exterior
                let parentIdx = closestParent.getValue(p)
                if parentIdx < 0 { continue }
                // because the border is thicker, some points aren't really "inside" but are treated as such
                if parentIdx == inside.index(p) {
                    leftMap.setValue(parentIdx, at: p)
                    rightMap.setValue(parentIdx, at: p)
                    continue
                }
                // Map parent pixel index to contour index; if not found, skip
                guard let v0 = indexMap[parentIdx] else { continue }
                let b = contour[v0]
                let theta0 = angle(from: p, to: b)

                // Walk forward (right) and backward (left) along contour
                var bestLeftAngle = theta0
                var bestLeftIdx = v0
                var bestRightAngle = theta0
                var bestRightIdx = v0

                // Walk CW (increasing contour index) for right bound
                var steps = 0
                var i = v0
                while steps < maxSteps {
                    let j = (i + 1) % contourCount
                    let a = contour[i]
                    let c = contour[j]
                    let ta = unwrap(angle(from: p, to: a), around: theta0)
                    let tc = unwrap(angle(from: p, to: c), around: theta0)
                    let tmax = max(ta, tc)
                    if tmax > bestRightAngle { bestRightAngle = tmax; bestRightIdx = (ta > tc) ? i : j }
                    i = j
                    steps += 1
                }

                // Walk CCW (decreasing contour index) for left bound
                steps = 0
                i = v0
                while steps < maxSteps {
                    let j = (i - 1 + contourCount) % contourCount
                    let a = contour[i]
                    let c = contour[j]
                    let ta = unwrap(angle(from: p, to: a), around: theta0)
                    let tc = unwrap(angle(from: p, to: c), around: theta0)
                    let tmin = min(ta, tc)
                    if tmin < bestLeftAngle { bestLeftAngle = tmin; bestLeftIdx = (ta < tc) ? i : j }
                    i = j
                    steps += 1
                }

                leftMap.setValue(inside.index(contour[bestLeftIdx]), at: p)
                rightMap.setValue(inside.index(contour[bestRightIdx]), at: p)
            }
        }
        return (leftMap, rightMap)
    }
    
    /// AngularDistanceField (ADF) is a name I came up with. We store 4 floats to approximate the distance a ray has to travel to hit a border
    typealias ADF = (angle: Float, dClose: Float, dFar: Float, cosine: Float)
    
    func computeAngularDistanceField(left: SimpleImage<Int>, right: SimpleImage<Int>) -> SimpleImage<ADF> {
        let euclidean = getEuclideanSDF()
        var img = SimpleImage<ADF>(width: width, height: height, repeating: (0,0,0,0))
        img.setAll() { i, coord in
            let dClose = abs(euclidean.data[i])
            if inside.data[i] == 1 || (left.data[i] == i && right.data[i] == i) {
                // inside, or border points pointing at themselves
                return (0, dClose, dClose, -1)
            }
            // we have 2 point that define a wedge
            let va = inside.indexToCoord(left.data[i]) - coord
            let vb = inside.indexToCoord(right.data[i]) - coord
            let vc = inside.indexToCoord(closestParent.data[i]) - coord
            let na = Normalize(CGPoint(x: Double(va.x), y: Double(va.y)))
            let nb = Normalize(CGPoint(x: Double(vb.x), y: Double(vb.y)))
            let nc = Normalize(CGPoint(x: Double(vc.x), y: Double(vc.y)))
            var nMid: CGPoint = CGPoint(x: (na.x + nb.x) / 2.0, y: (na.y + nb.y) / 2.0)
            if Dot(nc, nMid) < 0 {
                // This could happen if we are inside a concave area, and left and right are behind the point
                // Then, flip nMid to point to the same direction as nc, our closest direction.
                nMid.x = -nMid.x
                nMid.y = -nMid.y
            }
            let angle = atan2l(nMid.y, nMid.x)
            let da = Length(va)
            let db = Length(vb)
            let dFar = (da + db) / 2.0
            let cosine = Dot(na, nMid)
            return (Float(angle), dClose, dFar, Float(cosine))
        }
        return img
    }
    
    
    // MARK: Image conversion
    
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
    
    static func adfToRGBAImage(_ adf: SimpleImage<ADF>) -> SimpleImage<UInt32> {
        let w = adf.width
        let h = adf.height
        var img = SimpleImage<UInt32>(width: w, height: h, repeating: 0)
        // hypotenuse
        let maxDistance = sqrtf(Float(w * w + h * h))
        img.data = adf.data.map { v in
            let angle = 0.5 * v.angle / PI + 0.5
            let dClose = v.dClose / maxDistance
            let dFar = v.dFar / maxDistance
            let cosine = 0.5 * v.cosine + 0.5
            let r = UInt32(roundf(255.0 * angle)) & 0xff
            let g = UInt32(roundf(255.0 * dClose)) & 0xff
            let b = UInt32(roundf(255.0 * dFar)) & 0xff
            let a = UInt32(roundf(255.0 * cosine)) & 0xff
            return UInt32(r << 24 | g << 16 | b << 8 | a)
        }
        return img
    }
}

