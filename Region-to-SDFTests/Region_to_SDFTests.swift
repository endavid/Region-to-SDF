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
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(path)
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
    
    @Test func regionalSDF() throws {
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
        let regionalSDF = RegionalSDF(sampler: sampler, regionColor: (r: 47, g: 143, b: 236, a: 255))
        #expect(regionalSDF.isInside((15, 15)))
        #expect(!regionalSDF.isInside((0, 0)))
        try regionalSDF.computeSDF() { iteration in
            if iteration > 10 && (iteration % 10 != 0) {
                // skip 9 iterations
                return
            }
            guard let cgImage = regionalSDF.toRGImage(maxContrast: true).toCGImage() else {
                print("Failed to get image for iteration \(iteration)")
                return
            }
            saveImage(cgImage, path: "regionalSDF_test_\(iteration).png")
        }
        let sdf = regionalSDF.getSDF()
        let euclideanSdf = regionalSDF.getEuclideanSDF()
        if let cgImage = RegionalSDF.distanceToRGImage(sdf, maxContrast: false).toCGImage() {
            saveImage(cgImage, path: "regionalSDF_test_sdf.png")
        }
        if let cgImage = RegionalSDF.distanceToRGImage(euclideanSdf, maxContrast: false).toCGImage() {
            saveImage(cgImage, path: "regionalSDF_test_euclidean.png")
        }
        #expect(IsClose(sdf.getValue((15,15)), -2.83, epsilon: 0.01))
        #expect(IsClose(euclideanSdf.getValue((15,15)), -2.83, epsilon: 0.01))
        let closest = regionalSDF.getClosestBorder()
        if let cgImage = closest.indexToUVTexture() {
            saveImage(cgImage, path: "regionalSDF_test_closest_uv.png")
        }
        #expect(closest.getValue((15, 15)) == 557)
    }

    // Helper to get the test bundle via class lookup
    private final class SelfClass {}
}
