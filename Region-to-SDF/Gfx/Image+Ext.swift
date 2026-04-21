//
//  Image+Ext.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 06/04/2026.
//
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/** Saves image to disk
*  @see http://stackoverflow.com/questions/1320988/saving-cgimageref-to-a-png-file
*/
@available(macOS 13.0, iOS 14.0, *)
func CGImageWriteToFile(_ image: CGImage, filename: URL) {
    let url = filename as CFURL
    guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        NSLog("Failed to create destination: \(url)")
        return
    }
    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
        NSLog("Failed to write image to \(filename)")
    }
}

func ConcatenateVertical(images: [CGImage]) -> CGImage? {
    if images.isEmpty {
        return nil
    }
    guard let first = images.first, let colorSpace = first.colorSpace else {
        NSLog("Unexpected missing first image or color space")
        return nil
    }
    let w = first.width
    let bitsPerComponent = first.bitsPerComponent
    let bitsPerPixel = first.bitsPerPixel
    let bytesPerRow = first.bytesPerRow
    let bitmapInfo = first.bitmapInfo

    // Validate all images share the same format and compute total height
    var totalHeight = 0
    for img in images {
        if img.width != w {
            NSLog("One of the images has the wrong width (\(img.width)) - expected \(w)")
            return nil
        }
        if img.bitsPerComponent != bitsPerComponent {
            NSLog("One of the images has the wrong bitsPerComponent (\(img.bitsPerComponent)) - expected \(bitsPerComponent)")
            return nil
        }
        if img.bitsPerPixel != bitsPerPixel {
            NSLog("One of the images has the wrong bitsPerPixel (\(img.bitsPerPixel)) - expected \(bitsPerPixel)")
            return nil
        }
        if img.bytesPerRow != bytesPerRow {
            NSLog("One of the images has the wrong bytesPerRow (\(img.bytesPerRow)) - expected \(bytesPerRow)")
            return nil
        }
        if img.bitmapInfo != bitmapInfo {
            NSLog("One of the images has the wrong bitmapInfo (\(img.bitmapInfo)) - expected \(bitmapInfo)")
            return nil
        }
        if img.colorSpace != colorSpace {
            let expected = (colorSpace.name as String?) ?? "??"
            let got = (img.colorSpace?.name as String?) ?? "??"
            NSLog("One of the images has the wrong colorSpace (\(got)) - expected \(expected)")
            return nil
        }
        totalHeight += img.height
    }

    // Concatenate bytes row-by-row for vertical stacking
    // Each image contributes `height` rows, each row is `bytesPerRow` bytes
    var buffer = Data()
    buffer.reserveCapacity(bytesPerRow * totalHeight)

    for img in images {
        guard let cfData = img.dataProvider?.data else {
            NSLog("Missing data provider for one of the images")
            return nil
        }
        let imgData = cfData as Data
        // Append rows in order to stack vertically
        let height = img.height
        for row in 0..<height {
            let start = row * bytesPerRow
            let end = start + bytesPerRow
            // Defensive bounds check in case provider's bytesPerRow differs unexpectedly
            guard end <= imgData.count else {
                NSLog("Data size mismatch for one of the images")
                return nil
            }
            buffer.append(imgData[start..<end])
        }
    }

    guard let provider = CGDataProvider(data: NSData(data: buffer)) else {
        return nil
    }

    return CGImage(
        width: w,
        height: totalHeight,
        bitsPerComponent: bitsPerComponent,
        bitsPerPixel: bitsPerPixel,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}
