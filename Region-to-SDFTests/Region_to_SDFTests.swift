//
//  Region_to_SDFTests.swift
//  Region-to-SDFTests
//
//  Created by David Gavilan Ruiz on 02/04/2026.
//

import Testing
import Foundation
import AppKit

@testable import Region_to_SDF

struct Region_to_SDFTests {
    
    func saveImage(_ cgImage: CGImage, path: String) {
        let outputURL = FileManager.default.temporaryDirectory.appending(path: path, directoryHint: .notDirectory)
        if #available(macOS 13.0, iOS 14.0, *) {
            CGImageWriteToFile(cgImage, filename: outputURL)
            print("✅ Saved iteration image to \(outputURL.path)")
        } else {
            // Fallback on earlier versions
        }
    }
    
    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }
    
    @Test func someMaths() {
        let p = CGPoint(x: 10, y: 0.2)
        let n = Normalize(p)
        #expect(IsClose(atan2(p.y, p.x), atan2(n.y, n.x), epsilon: 1e-6))
    }
    
    @Test func angles() {
        #expect(IsClose(Angle(from: (20,14), to: (21,14)), 0))
        #expect(IsClose(Angle(from: (20,14), to: (20,13)), -PI_2))
        #expect(IsClose(Angle(from: (20,14), to: (20,15)), PI_2))
        #expect(IsClose(Angle(from: (20,14), to: (19,14)), PI))
        #expect(IsClose(Angle(from: (20,14), to: (19,12)), -2.0344439))
    }
    
    @Test func angleUnwrap() {
        #expect(IsClose(Unwrap(PI, around: PI), PI))
        #expect(IsClose(Unwrap(PI, around: 0), -PI))
        #expect(IsClose(Unwrap(PI, around: PI_2), PI))
    }
    
    @Test(
        "Regional SDF",
        arguments: [
            (regionColor: ColorRGB(hexValue: 0xf7c164), minValue: -8, testCoord: (28, 2), expectedSdf: -4.83, expectedEuclidean: -4.472, closestIndex: 218),
            (regionColor: ColorRGB(hexValue: 0x2f8fec), minValue: -3.6055, testCoord: (15, 15), expectedSdf: -2.83, expectedEuclidean: -2.83, closestIndex: 557)
        ]
    )
    func regionalSDF(regionColor: ColorRGB, minValue: Float, testCoord: Coord2D, expectedSdf: Float, expectedEuclidean: Float, closestIndex: Int) throws {
        // Resolve the test bundle for this test type
        let testBundle = Bundle(for: SelfClass.self)
        // Alternatively: Bundle.module if using SwiftPM test target with resources

        // Find the image by name (adjust extension as needed)
        guard let url = testBundle.url(forResource: "RegionTest32x32", withExtension: "png") else {
            Issue.record("Missing test image RegionTest32x32.png in test bundle")
            return
        }

        guard let image = NSImage(contentsOf: url) else {
            Issue.record("Failed to load NSImage from \(url)")
            return
        }
        
        let sampler = ImageSampler(image: image)
        let regionalSDF = RegionalSDF(sampler: sampler, regionColor: regionColor, epsilon: 5.0/255.0, grow: false)
        #expect(regionalSDF.isInside(testCoord))
        #expect(!regionalSDF.isInside((0, 0)))
        try regionalSDF.computeSDF() { iteration in
            if iteration > 10 && (iteration % 25 != 0) {
                // skip some
                return
            }
            guard let cgImage = regionalSDF.toRGImage(maxContrast: true).toCGImage() else {
                print("Failed to get image for iteration \(iteration)")
                return
            }
            let si = String(format: "%06d", iteration)
            saveImage(cgImage, path: "regionalSDF_test_\(regionColor.hexString)_\(si).png")
        }
        let sdf = regionalSDF.getSDF()
        let euclideanSdf = regionalSDF.getEuclideanSDF()
        let minDistance = euclideanSdf.minValue()
        #expect(IsClose(minDistance, minValue))
        if let cgImage = RegionalSDF.distanceToRGImage(sdf, maxContrast: false).toCGImage() {
            saveImage(cgImage, path: "regionalSDF_test_\(regionColor.hexString)_sdf.png")
        }
        if let cgImage = RegionalSDF.distanceToRGImage(euclideanSdf, maxContrast: false).toCGImage() {
            saveImage(cgImage, path: "regionalSDF_test_\(regionColor.hexString)_euclidean.png")
        }
        #expect(IsClose(sdf.getValue(testCoord), expectedSdf, epsilon: 0.01))
        #expect(IsClose(euclideanSdf.getValue(testCoord), expectedEuclidean, epsilon: 0.01))
        let closest = regionalSDF.getClosestBorder()
        if let cgImage = closest.indexToUVTexture() {
            saveImage(cgImage, path: "regionalSDF_test_\(regionColor.hexString)_closest_uv.png")
        }
        #expect(closest.getValue(testCoord) == closestIndex)
        // check which points refer to themselves (should be interior points only)
        var img = SimpleImage<Int>(width: closest.width, height: closest.height, repeating: 0)
        let boundary = Set<Int>(regionalSDF.extractBoundaryContour().map { closest.index($0) })
        img.setAll() { i, coord in
            if closest.data[i] != i {
                return 0
            }
            if boundary.contains(i) {
                return 1
            }
            return regionalSDF.isInside(coord) ? 2 : 3
        }
        if let cgImage = img.toCGImage(palette: [.black, .white, .yellow, .enDavid_orange]) {
            saveImage(cgImage, path: "regionalSDF_test_\(regionColor.hexString)_closest_identity_check.png")
        }
    }
    
    @Test(
        "Correct region boundaries",
        arguments: [
            // the number of boundary pixels are different from the expected because
            // thin edges may be ignored, or we may have to loop back, depeding on the starting point
            (regionColor: ColorRGB(hexValue: 0xf7c164), expectedCount: 51), // actual boundary pixels = 52
            (regionColor: ColorRGB(hexValue: 0x2f8fec), expectedCount: 53) // actual 57
        ]
    )
    func boundaryCountour(regionColor: ColorRGB, expectedCount: Int) throws {
        let testBundle = Bundle(for: SelfClass.self)
        guard let url = testBundle.url(forResource: "RegionTest32x32", withExtension: "png") else {
            Issue.record("Missing test image RegionTest32x32.png in test bundle")
            return
        }
        guard let image = NSImage(contentsOf: url) else {
            Issue.record("Failed to load NSImage from \(url)")
            return
        }
        let sampler = ImageSampler(image: image)
        let regionalSDF = RegionalSDF(sampler: sampler, regionColor: regionColor, epsilon: 5.0 / 255.0, grow: false)
        let contour = regionalSDF.extractBoundaryContour()
        #expect(contour.count == expectedCount)
        var img = SimpleImage<Int>(width: regionalSDF.width, height: regionalSDF.height, repeating: 0)
        let palette = [ColorRGB.black] + ColorRGB.heatmap(low: .green, mid: .yellow, high: .red, maxValue: contour.count)
        for i in 0..<contour.count {
            img.setValue(i+1, at: contour[i])
            if let cgImage = img.toCGImage(palette: palette) {
                let si = String(format: "%06d", i)
                saveImage(cgImage, path: "boundaryContour_test_0x\(regionColor.hexString)_\(si).png")
            }
        }
        let thickBoundary = regionalSDF.buildBoundaryIndexMap(contour: contour)
        img.clear(value: 0)
        for (iCoord, idx) in thickBoundary {
            let coord = img.indexToCoord(iCoord)
            img.setValue(idx+1, at: coord)
        }
        if let cgImage = img.toCGImage(palette: palette) {
            saveImage(cgImage, path: "boundaryContour_test_0x\(regionColor.hexString)_thick.png")
        }
    }
    
    @Test(
        "Exterior bounding maps",
        arguments: [
            (regionColor: ColorRGB(hexValue: 0xf7c164), expectedCount: 51),
            (regionColor: ColorRGB(hexValue: 0x2f8fec), expectedCount: 53)
        ]
    )
    func exteriorBoundingMaps(regionColor: ColorRGB, expectedCount: Int) throws {
        let testBundle = Bundle(for: SelfClass.self)
        guard let url = testBundle.url(forResource: "RegionTest32x32", withExtension: "png") else {
            Issue.record("Missing test image RegionTest32x32.png in test bundle")
            return
        }
        guard let image = NSImage(contentsOf: url) else {
            Issue.record("Failed to load NSImage from \(url)")
            return
        }
        let sampler = ImageSampler(image: image)
        let regionalSDF = RegionalSDF(sampler: sampler, regionColor: regionColor)
        try regionalSDF.computeSDF()
        let debugCoords: [Coord2D] = [(20,14), (30, 11)]
        let fovMap = regionalSDF.computeFoV(debugCoords: debugCoords, debugPrefix: FileManager.default.temporaryDirectory.appending(path: "exteriorBoundingMaps_test_0x\(regionColor.hexString)"))
        if let cgImage = fovMap.left.indexToUVTexture() {
            saveImage(cgImage, path: "exteriorBoundingMaps_test_0x\(regionColor.hexString)_left.png")
        }
        if let cgImage = fovMap.right.indexToUVTexture() {
            saveImage(cgImage, path: "exteriorBoundingMaps_test_0x\(regionColor.hexString)_right.png")
        }
        if let cgImage = fovMap.mid.indexToUVTexture() {
            saveImage(cgImage, path: "exteriorBoundingMaps_test_0x\(regionColor.hexString)_mid.png")
        }
        let testCoords: [Coord2D] = [(5, 10), (10, 12), (10, 30), (17, 25), (20, 14), (20, 18), (22, 17), (30, 2), (30, 11), (30, 30)]
        for c in testCoords {
            if let cgImage = regionalSDF.createFoVDebugImage(coord: c, fovMap: fovMap) {
                saveImage(cgImage, path: "exteriorBoundingMaps_test_0x\(regionColor.hexString)_\(c.x)_\(c.y).png")
            }
        }
        let adf = regionalSDF.computeAngularDistanceField(fovMap: fovMap)
        let adfImage = RegionalSDF.fcdfToRGBAImage(adf)
        if let cgImage = adfImage.toCGImage() {
            saveImage(cgImage, path: "exteriorBoundingMaps_test_0x\(regionColor.hexString)_fcdf.png")
        }
        let closest = regionalSDF.getClosestBorder()
        if let cgImage = closest.indexToUVTexture() {
            saveImage(cgImage, path: "exteriorBoundingMaps_test_0x\(regionColor.hexString)_closest_uv.png")
        }
    }
    
    @Test(
        "Circular Harmonics",
        arguments: [
            // at least one of the arguments needs to be hashable for identification, so I use Int for the color
            (hexColor: 0xf7c164, expected0a0: 0.8001529, expMinValue: -1.6166525, expMaxValue: 4.153237),
            (hexColor: 0x2f8fec, expected0a0: 0.533785, expMinValue: -1.4623079, expMaxValue: 4.3262334)
        ]
    )
    func circularHarmonicsTest(hexColor: Int, expected0a0: Float, expMinValue: Float, expMaxValue: Float) throws {
        let regionColor = ColorRGB(hexValue: hexColor)
        let testBundle = Bundle(for: SelfClass.self)
        guard let url = testBundle.url(forResource: "RegionTest32x32", withExtension: "png") else {
            Issue.record("Missing test image RegionTest32x32.png in test bundle")
            return
        }
        guard let image = NSImage(contentsOf: url) else {
            Issue.record("Failed to load NSImage from \(url)")
            return
        }
        let sampler = ImageSampler(image: image)
        let regionalSDF = RegionalSDF(sampler: sampler, regionColor: regionColor)
        try regionalSDF.computeSDF()
        let density = regionalSDF.computeNormalizedDensity()
        if let cgImage = density.toCGImage() {
            saveImage(cgImage, path: "circularHarmonicsTest_0x\(regionColor.hexString)_density.png")
        }
        let densityField = regionalSDF.computeDensityField(ftOrder: 12)
        let maxValue = densityField.maxValue()
        let minValue = densityField.minValue()
        #expect(IsClose(maxValue, expMaxValue))
        #expect(IsClose(minValue, expMinValue))
        #expect(IsClose(densityField.data[0].a[0], expected0a0))
        let rangesA = densityField.rangesA()
        let rangesB = densityField.rangesB()
        print(rangesA)
        print(rangesB)
        let upwardsDensity = densityField.evaluate(direction: SIMD2(x: 0, y: -1)).normalize()
        let downwardsDensity = densityField.evaluate(direction: SIMD2(x: 0, y: 1)).normalize()
        let leftwardsDensity = densityField.evaluate(direction: SIMD2(x: -1, y: 0)).normalize()
        let rightwardsDensity = densityField.evaluate(direction: SIMD2(x: 1, y: 0)).normalize()
        if let cgImage = upwardsDensity.toCGImage() {
            saveImage(cgImage, path: "circularHarmonicsTest_0x\(regionColor.hexString)_upwards.png")
        }
        if let cgImage = downwardsDensity.toCGImage() {
            saveImage(cgImage, path: "circularHarmonicsTest_0x\(regionColor.hexString)_downwards.png")
        }
        if let cgImage = leftwardsDensity.toCGImage() {
            saveImage(cgImage, path: "circularHarmonicsTest_0x\(regionColor.hexString)_leftwards.png")
        }
        if let cgImage = rightwardsDensity.toCGImage() {
            saveImage(cgImage, path: "circularHarmonicsTest_0x\(regionColor.hexString)_rightwards.png")
        }
        if let cgImage = densityField.toCGImage() {
            saveImage(cgImage, path: "circularHarmonicsTest_0x\(regionColor.hexString)_ftDensityField.png")
        }
        let realUpwardsDensity = regionalSDF.computeDensity(direction: SIMD2(x: 0, y: -1)).normalize()
        let realDownwardsDensity = regionalSDF.computeDensity(direction: SIMD2(x: 0, y: 1)).normalize()
        let realLeftwardsDensity = regionalSDF.computeDensity(direction: SIMD2(x: -1, y: 0)).normalize()
        let realRightwardsDensity = regionalSDF.computeDensity(direction: SIMD2(x: 1, y: 0)).normalize()
        if let cgImage = realUpwardsDensity.toCGImage() {
            saveImage(cgImage, path: "circularHarmonicsTest_0x\(regionColor.hexString)_upwards_truth.png")
        }
        if let cgImage = realDownwardsDensity.toCGImage() {
            saveImage(cgImage, path: "circularHarmonicsTest_0x\(regionColor.hexString)_downwards_truth.png")
        }
        if let cgImage = realLeftwardsDensity.toCGImage() {
            saveImage(cgImage, path: "circularHarmonicsTest_0x\(regionColor.hexString)_leftwards_truth.png")
        }
        if let cgImage = realRightwardsDensity.toCGImage() {
            saveImage(cgImage, path: "circularHarmonicsTest_0x\(regionColor.hexString)_rightwards_truth.png")
        }
    }
    
    @Test func multiregionalDF() throws {
        let testBundle = Bundle(for: SelfClass.self)
        guard let url = testBundle.url(forResource: "RegionTest32x32", withExtension: "png") else {
            Issue.record("Missing test image RegionTest32x32.png in test bundle")
            return
        }
        guard let image = NSImage(contentsOf: url) else {
            Issue.record("Failed to load NSImage from \(url)")
            return
        }
        let sampler = ImageSampler(image: image)
        let palette = [ColorRGB(hexValue: 0x130c14), ColorRGB(hexValue: 0xf7c164), ColorRGB(hexValue: 0x2f8fec), ColorRGB(hexValue: 0x805710), ColorRGB(hexValue: 0xd8ea35), ColorRGB(hexValue: 0xb8274d), ColorRGB(hexValue: 0xb8274d), ColorRGB(hexValue: 0x0aa80e), ColorRGB(hexValue: 0xcd10de)]
        let multiregionalDF = MultiRegionalDF(sampler: sampler, regionColors: palette)
        if let cgImage = multiregionalDF.regions.toCGImage(palette: palette) {
            saveImage(cgImage, path: "multiregionalDF_regions.png")
        }
        try multiregionalDF.computeDF() { iteration in
            if iteration > 10 && (iteration % 25 != 0) {
                // skip some
                return
            }
            guard let cgImage = multiregionalDF.distancesToGrayImage().toCGImage() else {
                print("Failed to get image for iteration \(iteration)")
                return
            }
            let si = String(format: "%06d", iteration)
            saveImage(cgImage, path: "multiregionalDF_df_\(si).png")
        }
        if let cgImage = multiregionalDF.densityToGrayImage().toCGImage() {
            saveImage(cgImage, path: "multiregionalDF_df_density.png")
        }
        let densityField = multiregionalDF.computeDensityField(ftOrder: 2)
        let maxValue = densityField.maxValue()
        let minValue = densityField.minValue()
        #expect(IsClose(maxValue, 1.0))
        #expect(IsClose(minValue, -0.37812454))
        let upwardsDensity = densityField.evaluate(direction: SIMD2(x: 0, y: -1)).normalize()
        let downwardsDensity = densityField.evaluate(direction: SIMD2(x: 0, y: 1)).normalize()
        let leftwardsDensity = densityField.evaluate(direction: SIMD2(x: -1, y: 0)).normalize()
        let rightwardsDensity = densityField.evaluate(direction: SIMD2(x: 1, y: 0)).normalize()
        if let cgImage = upwardsDensity.toCGImage() {
            saveImage(cgImage, path: "multiregionalDF_df_upwards.png")
        }
        if let cgImage = downwardsDensity.toCGImage() {
            saveImage(cgImage, path: "multiregionalDF_df_downwards.png")
        }
        if let cgImage = leftwardsDensity.toCGImage() {
            saveImage(cgImage, path: "multiregionalDF_df_leftwards.png")
        }
        if let cgImage = rightwardsDensity.toCGImage() {
            saveImage(cgImage, path: "multiregionalDF_df_rightwards.png")
        }
        if let cgImage = densityField.toCGImage() {
            saveImage(cgImage, path: "multiregionalDF_df_FT.png")
        }
        if let cgImage = multiregionalDF.distanceAndRegionIdToRGImage().toCGImage() {
            saveImage(cgImage, path: "multiregionalDF_df_regions.png")
        }
        if let cgImage = multiregionalDF.colorAndDistanceImage(palette: palette).toCGImage() {
            saveImage(cgImage, path: "multiregionalDF_df_colors.png")
        }
        if let cgImage = multiregionalDF.densityAndDistanceFieldImage().toCGImage() {
            saveImage(cgImage, path: "multiregionalDF_df_DDF.png")
        }
    }

    // Helper to get the test bundle via class lookup
    private final class SelfClass {}
}
