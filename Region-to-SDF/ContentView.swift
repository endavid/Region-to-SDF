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
    
    @State private var generatedSDFs: [RegionalSDF] = []
    @State private var generatedCGImages: [CGImage] = []

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 16) {
                // Image Well (Drag & Drop)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Region Image")
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
                            } // ZStack
                            .frame(minWidth: 80, maxWidth: 240, minHeight: 80, maxHeight: 240)
                            .contentShape(Rectangle())
                            .onDrop(of: [UTType.image, UTType.fileURL], isTargeted: nil) { providers in
                                handleDrop(providers: providers)
                            }
                        } // VStack image well
                        Button(action: {
                            Task { await computeAllSDFs() }
                        }) {
                            Image(systemName: "wand.and.rays")
                            Text("Compute SDFs")
                              .padding(.horizontal)
                          }
                          .padding()
                          .foregroundColor(.secondary)
                          .cornerRadius(10)
                    } // HStack top
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SDF images")
                            .font(.headline)
                        if generatedCGImages.isEmpty {
                            Text("No SDF images yet").foregroundStyle(.secondary)
                        } else {
                            let columns = [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .top)]
                            ScrollView {
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                                    ForEach(Array(generatedCGImages.enumerated()), id: \.offset) { _, cg in
                                        Image(decorative: cg, scale: 1, orientation: .up)
                                            .resizable()
                                            .interpolation(.none)
                                            .antialiased(false)
                                            .scaledToFit()
                                            .frame(maxWidth: 160, maxHeight: 160)
                                            .background(Color(.underPageBackgroundColor))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                                    }
                                }
                            }
                        }
                    }
                } // VStack left
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
                                clear()
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
            self.clear()
        }
    }
    
    private func clear() {
        palette.removeAll()
        generatedSDFs.removeAll()
        generatedCGImages.removeAll()
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
    
    // MARK: - SDFs
    private func generateSDF(paletteIndex: Int) {
        if paletteIndex >= palette.count {
            logDebug("index \(paletteIndex) out of range: \(palette.count) colors")
            return
        }
        guard let imageSampler else {
            logDebug("No image sampler")
            return
        }
        let epsilon: Float = 5.0 / 255.0
        let color = palette[paletteIndex].colorTuple
        let sdf = RegionalSDF(sampler: imageSampler, regionColor: color, epsilon: epsilon)
        do {
            try sdf.computeSDF()
            // @todo append sdf to list
            let cgImage = sdf.toRGImage().toCGImage()
            // @todo append cgImage to "SDF images" region in the UI
        } catch {
            Logger.shared.err(error.localizedDescription)
        }
        
        
    }
    
    // MARK: - SDF Batch Generation
    private func makeSDF(for color: Color, sampler: ImageSampler, epsilon: Float) throws -> (RegionalSDF, CGImage?) {
        let tuple = color.colorTuple
        let sdf = RegionalSDF(sampler: sampler, regionColor: tuple, epsilon: epsilon)
        try sdf.computeSDF()
        let cg = sdf.toRGImage().toCGImage()
        return (sdf, cg)
    }

    @MainActor
    private func resetGeneratedOutputs() {
        generatedSDFs.removeAll()
        generatedCGImages.removeAll()
    }

    private func computeEpsilon() -> Float { 5.0 / 255.0 }

    private func computeAllSDFsSync() throws -> (sdfs: [RegionalSDF], images: [CGImage]) {
        guard let imageSampler else { throw NSError(domain: "RegionToSDF", code: 1, userInfo: [NSLocalizedDescriptionKey: "No image sampler"]) }
        let epsilon = computeEpsilon()
        var sdfs: [RegionalSDF] = []
        var images: [CGImage] = []
        for color in palette {
            let (sdf, cg) = try makeSDF(for: color, sampler: imageSampler, epsilon: epsilon)
            sdfs.append(sdf)
            if let cg { images.append(cg) }
        }
        return (sdfs, images)
    }

    private func computeAllSDFsParallel() async -> (sdfs: [RegionalSDF], images: [CGImage]) {
        guard let imageSampler else { return ([], []) }
        let epsilon = computeEpsilon()
        // Run per-color computations in parallel
        return await withTaskGroup(of: (RegionalSDF?, CGImage?).self) { group in
            for color in palette {
                group.addTask {
                    do {
                        let (sdf, cg) = try await makeSDF(for: color, sampler: imageSampler, epsilon: epsilon)
                        return (sdf, cg)
                    } catch {
                        await Logger.shared.err("SDF failed: \(error.localizedDescription)")
                        return (nil, nil)
                    }
                }
            }
            var sdfs: [RegionalSDF] = []
            var images: [CGImage] = []
            for await result in group {
                if let sdf = result.0 { sdfs.append(sdf) }
                if let cg = result.1 { images.append(cg) }
            }
            return (sdfs, images)
        }
    }

    private func computeAllSDFs() async {
        await MainActor.run { resetGeneratedOutputs() }
        let (sdfs, images) = await computeAllSDFsParallel()
        await MainActor.run {
            self.generatedSDFs = sdfs
            self.generatedCGImages = images
        }
    }
}

#Preview {
    ContentView()
}

