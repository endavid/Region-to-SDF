//
//  MultiRegionalSDF.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 07/05/2026.
//

class MultiRegionalSDF {
    var regions: SimpleImage<Int>
    
    init(sampler: ImageSampler, regionColors: Palette) {
        let w = sampler.width
        let h = sampler.height
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
    }

}
