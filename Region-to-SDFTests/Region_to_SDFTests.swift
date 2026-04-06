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
        // inside the region = -∞
        #expect(regionalSDF.get(coord: (15, 15)) == -RegionalSDF.BigValue)
        // outside the region = ∞
        #expect(regionalSDF.get(coord: (0, 0)) == RegionalSDF.BigValue)
        try regionalSDF.computeSDF() { iteration in
            guard let cgImage = regionalSDF.toRGImage().toCGImage() else {
                print("Failed to get image for iteration \(iteration)")
                return
            }
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("regionalSDF_test_\(iteration).png")
            if #available(macOS 13.0, iOS 14.0, *) {
                CGImageWriteToFile(cgImage, filename: outputURL)
                print("✅ Saved iteration image to \(outputURL.path)")
            } else {
                // Fallback on earlier versions
            }
        }
        #expect(regionalSDF.get(coord: (15, 15)) == -4.0)
    }

    // Helper to get the test bundle via class lookup
    private final class SelfClass {}
}
