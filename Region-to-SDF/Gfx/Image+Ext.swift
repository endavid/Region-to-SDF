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
