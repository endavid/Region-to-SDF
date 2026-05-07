//
//  Dijkstra.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 07/05/2026.
//

/// Multi-source Dijkstra

class Dijkstra {
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
}
