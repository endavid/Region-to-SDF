//
//  SimpleImage.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 03/04/2026.
//
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers


struct SimpleImage<T> {
    let width: Int
    let height: Int
    
    var data: [T]
    
    func index(_ p: Coord2D) -> Int {
        return p.y * width + p.x
    }
    func indexToCoord(_ i: Int) -> Coord2D {
        return (i % width, i / width)
    }
    func isValid(_ p: Coord2D) -> Bool {
        return p.x >= 0 && p.x < width && p.y >= 0 && p.y < height
    }
    
    func getValue(_ p: Coord2D) -> T {
        return data[index(p)]
    }
    mutating func setValue(_ v: T, at coord: Coord2D) {
        data[index(coord)] = v
    }
    mutating func clear(value: T) {
        data = [T].init(repeating: value, count: width * height)
    }
    
    func get4Neighbors(_ p: Coord2D) -> [Coord2D] {
        return [
            // NSEW
            (p.x - 1, p.y),
            (p.x, p.y - 1),
            (p.x + 1, p.y),
            (p.x, p.y + 1)]
    }
    func get4Diagonals(_ p: Coord2D) -> [Coord2D] {
        return [
            // from top-left, clock-wise
            (p.x - 1, p.y - 1),
            (p.x - 1, p.y + 1),
            (p.x + 1, p.y - 1),
            (p.x + 1, p.y + 1)]
    }
    func get4ValidNeighbors(_ p: Coord2D) -> [Coord2D] {
        return get4Neighbors(p).filter { isValid($0) }
    }
    func get8ValidNeighbors(_ p: Coord2D) -> [Coord2D] {
        let all = get4Neighbors(p) + get4Diagonals(p)
        return all.filter { isValid($0) }
    }
    
    init(width: Int, height: Int, repeating value: T) {
        self.width = width
        self.height = height
        self.data = [T].init(repeating: value, count: width * height)
    }
    
    func toCGImage() -> CGImage? {
        logDebug("Unsupported type: \(T.self)")
        return nil
    }
}

extension SimpleImage where T == UInt8 {
    func toCGImage() -> CGImage? {
        let pixelCount = width * height
        var imageBytes = data
        guard let provider = CGDataProvider(data: NSData(bytes: &imageBytes, length: pixelCount * MemoryLayout<UInt8>.size)) else {
            return nil
        }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
            )
    }
}

extension SimpleImage where T == UInt32 {
    func toCGImage() -> CGImage? {
        let bytesPerPixel = 4
        let pixelCount = width * height
        let bitsPerComponent = 8
        var imageBytes = [UInt8].init(repeating: 0, count: pixelCount * bytesPerPixel)
        for i in 0..<data.count {
            let c = data[i]
            imageBytes[4 * i] = UInt8(c >> 24)
            imageBytes[4 * i + 1] = UInt8((c >> 16) & 0x0000ff)
            imageBytes[4 * i + 2] = UInt8((c >> 8) & 0x0000ff)
            imageBytes[4 * i + 3] = UInt8(c & 0x0000ff)
        }
        guard let provider = CGDataProvider(data: NSData(bytes: &imageBytes, length: pixelCount * bytesPerPixel * MemoryLayout<UInt8>.size)) else {
            return nil
        }
        let bitmapInfo:CGBitmapInfo = [.byteOrder32Big, CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)]
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bytesPerPixel * bitsPerComponent,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
            )
    }
}

extension SimpleImage where T == Int {
    func indexToUVTexture() -> CGImage? {
        let bytesPerPixel = 4
        let pixelCount = width * height
        let bitsPerComponent = 8
        var imageBytes = [UInt8].init(repeating: 0, count: pixelCount * bytesPerPixel)
        for i in 0..<data.count {
            let index = data[i]
            if index < 0 {
                // unexpected
                imageBytes[4 * i] = 0
                imageBytes[4 * i + 1] = 0
                imageBytes[4 * i + 2] = 255
                imageBytes[4 * i + 3] = 255
                continue
            }
            let coord = indexToCoord(index)
            let u = 255.0 * Float(coord.x) / Float(width - 1)
            let v = 255.0 * Float(coord.y) / Float(height - 1)
            imageBytes[4 * i] = UInt8(u)
            imageBytes[4 * i + 1] = UInt8(v)
            imageBytes[4 * i + 2] = 0
            imageBytes[4 * i + 3] = 255
        }
        guard let provider = CGDataProvider(data: NSData(bytes: &imageBytes, length: pixelCount * bytesPerPixel * MemoryLayout<UInt8>.size)) else {
            return nil
        }
        let bitmapInfo:CGBitmapInfo = [.byteOrder32Big, CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)]
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bytesPerPixel * bitsPerComponent,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
            )
    }
    
    func toCGImage(palette: Palette) -> CGImage? {
        let bytesPerPixel = 4
        let pixelCount = width * height
        let bitsPerComponent = 8
        var imageBytes = [UInt8].init(repeating: 0, count: pixelCount * bytesPerPixel)
        for i in 0..<data.count {
            let c = max(0, data[i])
            let color = palette[min(c, palette.count - 1)]
            imageBytes[4 * i] = UInt8(color.r)
            imageBytes[4 * i + 1] = UInt8(color.g)
            imageBytes[4 * i + 2] = UInt8(color.b)
            imageBytes[4 * i + 3] = 255
        }
        guard let provider = CGDataProvider(data: NSData(bytes: &imageBytes, length: pixelCount * bytesPerPixel * MemoryLayout<UInt8>.size)) else {
            return nil
        }
        let bitmapInfo:CGBitmapInfo = [.byteOrder32Big, CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)]
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bytesPerPixel * bitsPerComponent,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
            )
    }
}
