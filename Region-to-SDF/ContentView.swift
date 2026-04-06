//
//  ContentView.swift
//  Region-to-SDF
//
//  Created by David Gavilan Ruiz on 02/04/2026.
//

import SwiftUI
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins

struct ContentView: View {
    @State private var droppedImage: NSImage? = nil
    @State private var displayedImage: Image? = nil
    @State private var imageSampler: ImageSampler?

    @State private var palette: [Color] = []
    @State private var lastTapPoint: CGPoint? = nil
    @State private var lastImageRect: CGRect = .zero
    

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 16) {
                // Image Well (Drag & Drop)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Image Well")
                        .font(.headline)
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                            .foregroundStyle(.secondary)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.windowBackgroundColor))
                            )
                        if let displayedImage {
                            displayedImage
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(4)
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "tray.and.arrow.down")
                                    .font(.system(size: 28, weight: .regular))
                                    .symbolRenderingMode(.hierarchical)
                                Text("Drag & drop an image here")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                    }
                    .frame(minWidth: 260, maxWidth: 420, minHeight: 260)
                    .contentShape(Rectangle())
                    .onDrop(of: [UTType.image, UTType.fileURL], isTargeted: nil) { providers in
                        handleDrop(providers: providers)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)

                // Color Picking Canvas and Palette
                VStack(alignment: .leading, spacing: 12) {
                    Text("Color Picker Canvas")
                        .font(.headline)
                    ZStack(alignment: .topLeading) {
                        if let displayedImage {
                            GeometryReader { geo in
                                ZStack {
                                    displayedImage
                                        .resizable()
                                        .scaledToFit()
                                        .overlay(
                                            ZStack {
                                                // Crosshair overlay limited to the drawn image rect
                                                GeometryReader { innerGeo in
                                                    let containerSize = innerGeo.size
                                                    let imageSize = droppedImage?.size ?? .zero
                                                    let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
                                                    let drawnSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                                                    let origin = CGPoint(x: (containerSize.width - drawnSize.width) / 2, y: (containerSize.height - drawnSize.height) / 2)
                                                    let imgRect = CGRect(origin: origin, size: drawnSize)
                                                    Color.clear
                                                        .onAppear { lastImageRect = imgRect }
                                                        .onChange(of: containerSize) { lastImageRect = imgRect }
                                                    if let p = lastTapPoint, imgRect.contains(p) {
                                                        // Vertical line
                                                        Path { path in
                                                            path.move(to: CGPoint(x: p.x, y: imgRect.minY))
                                                            path.addLine(to: CGPoint(x: p.x, y: imgRect.maxY))
                                                        }
                                                        .stroke(.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [4,3]))
                                                        // Horizontal line
                                                        Path { path in
                                                            path.move(to: CGPoint(x: imgRect.minX, y: p.y))
                                                            path.addLine(to: CGPoint(x: imgRect.maxX, y: p.y))
                                                        }
                                                        .stroke(.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [4,3]))
                                                        // Center dot
                                                        Circle()
                                                            .strokeBorder(.yellow, lineWidth: 2)
                                                            .background(Circle().fill(Color.yellow.opacity(0.2)))
                                                            .frame(width: 10, height: 10)
                                                            .position(p)
                                                    }
                                                }
                                            }
                                        )
                                        .gesture(
                                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                                .onEnded { value in
                                                    let tapPoint = value.location
                                                    self.lastTapPoint = tapPoint
                                                    sampleColor(at: tapPoint)
                                                }
                                        )
                                }
                            }
                        } else {
                            Text("Drop an image to enable color picking")
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    }
                    .frame(minHeight: 260)

                    Divider()

                    let paletteTitle: AttributedString = {
                        var s = AttributedString("Palette (")
                        var countPart = AttributedString(String(palette.count))
                        countPart.inlinePresentationIntent = .stronglyEmphasized
                        s.append(countPart)
                        s.append(AttributedString(")"))
                        return s
                    }()
                    Text(paletteTitle)
                    List {
                        ForEach(Array(palette.enumerated()), id: \.offset) { index, color in
                            HStack(spacing: 12) {
                                Text("#\(index)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                                Circle()
                                    .fill(color)
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(Color.secondary.opacity(0.2)))
                                Text(color.hexDescription())
                                    .font(.subheadline)
                                Spacer()
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                        }
                        .onMove(perform: movePalette)
                        .onDelete(perform: deletePalette)
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 160)
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button(role: .destructive) {
                                palette.removeAll()
                            } label: {
                                Label("Clear Palette", systemImage: "trash")
                            }
                            .help("Remove all colors from the palette")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding()
            .navigationTitle("Region-to-SDF")
        }
    }

    // MARK: - Drag & Drop Handling
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // Prefer direct image
        if let itemProvider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) {
            _ = itemProvider.loadObject(ofClass: NSImage.self) { reading, _ in
                if let nsImage = reading as? NSImage {
                    prepareImage(nsImage)
                }
            }
            return true
        }
        // Fallback to file URL
        if let itemProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL, let nsImage = NSImage(contentsOf: url) {
                    prepareImage(nsImage)
                }
            }
            return true
        }
        return false
    }

    private func prepareImage(_ nsImage: NSImage) {
        DispatchQueue.main.async {
            self.droppedImage = nsImage
            self.displayedImage = Image(nsImage: nsImage)
            self.imageSampler = ImageSampler(image: nsImage)
        }
    }

    // MARK: - Color Sampling
    private func sampleColor(at tapPoint: CGPoint) {
        guard let sampler = imageSampler else { return }

        // (u,v) where top-left is (0,0)
        let u = Float(tapPoint.x / lastImageRect.width)
        let v = Float(tapPoint.y / lastImageRect.height)
        
        let sample: UintColorTuple = sampler.get(u: u, v: v)
        
        logDebug("Tap: \(tapPoint) UV(\(u), \(v)) color: \(sample)")
        
        let nsColor = NSColor(sample)
        DispatchQueue.main.async {
            addToPalette(Color(nsColor: nsColor))
        }
    }

    // MARK: - Palette Operations
    private func movePalette(from source: IndexSet, to destination: Int) {
        palette.move(fromOffsets: source, toOffset: destination)
    }

    private func deletePalette(at offsets: IndexSet) {
        palette.remove(atOffsets: offsets)
    }
    
    private func addToPalette(_ color: Color) {
        for c in palette {
            if c == color {
                logDebug("Color \(color.hexDescription()) already in palette")
                return
            }
        }
        palette.append(color)
    }
}

// MARK: - Helpers
private extension NSImage {
    func bestBitmapRep() -> NSBitmapImageRep? {
        // Try to get an existing bitmap rep
        if let rep = self.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return rep
        }
        // Otherwise, draw into a bitmap context
        let size = self.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.cgContext.interpolationQuality = .high
            self.draw(in: CGRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
}

#Preview {
    ContentView()
}

