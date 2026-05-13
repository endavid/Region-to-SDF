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

enum DistanceFunction: String, CaseIterable, Identifiable {
    case SignedGray, SignedRedGreen, FieldOfView, DensityFT, DensityDF
    var id: Self { self }
}

struct ContentView: View {
    @State private var droppedImage: NSImage? = nil
    @State private var displayedImage: Image? = nil
    @State private var imageSampler: ImageSampler?

    @State private var palette: [Color] = []
    @State private var lastTapPoint: CGPoint? = nil
    @State private var lastImageRect: CGRect = .zero
    
    @State private var selectedDF: DistanceFunction = .FieldOfView
    
    @State private var generatedCGImages: [CGImage] = []
    
    @State private var maxColorDifference: Double = 5 // 0..128
    @State private var isExporting: Bool = false

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
                            .frame(minWidth: 80, maxWidth: 180, minHeight: 80, maxHeight: 180)
                            .contentShape(Rectangle())
                            .onDrop(of: [UTType.image, UTType.fileURL], isTargeted: nil) { providers in
                                handleDrop(providers: providers)
                            }
                        } // VStack image well
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // Epsilon slider
                            Text("Max color difference").font(.subheadline)
                            HStack(spacing: 8) {
                                Slider(value: $maxColorDifference, in: 0...128, step: 1)
                                Text("\(Int(maxColorDifference))")
                                    .monospacedDigit()
                                    .frame(width: 32, alignment: .trailing)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)

                            Picker("DF", selection: $selectedDF) {
                                    ForEach(DistanceFunction.allCases) { df in
                                        Text(df.rawValue)
                                    }
                                }
                            // Actions
                            Button(action: {
                                Task { await computeAllSDFs() }
                            }) {
                                Image(systemName: "wand.and.rays")
                                Text("Compute SDFs")
                            }
                            .disabled(palette.isEmpty)

                            Button(action: { exportGeneratedImages() }) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export Images")
                            }
                            .disabled(generatedCGImages.isEmpty)
                            
                            Button(action: { exportAtlas() }) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export Atlas")
                            }
                            .disabled(generatedCGImages.isEmpty)
                        }
                        .frame(alignment: .leading)
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
        
    // MARK: - SDF Batch Generation
    private func makeSDF(for color: Color, sampler: ImageSampler, epsilon: Float) throws -> CGImage? {
        let rdf = RegionalSDF(sampler: sampler, regionColor: color.colorRGB, epsilon: epsilon)
        try rdf.computeSDF()
        if selectedDF == .FieldOfView {
            let fovMap = rdf.computeFoV()
            let fcdf = rdf.computeAngularDistanceField(fovMap: fovMap)
            let img = RegionalSDF.fcdfToRGBAImage(fcdf)
            return img.toCGImage()
        }
        if selectedDF == .DensityFT {
            let df = rdf.computeDensityField()
            return df.toCGImage()
        }
        let sdf = rdf.getEuclideanSDF()
        if selectedDF == .SignedRedGreen {
            let img = RegionalSDF.distanceToRGImage(sdf, maxContrast: true)
            return img.toCGImage()
        }
        if selectedDF == .SignedGray {
            let img = RegionalSDF.distanceToGrayImage(sdf)
            return img.toCGImage()
        }
        return nil
    }
    
    private func exportGeneratedImages() {
        guard !generatedCGImages.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.title = "Choose export folder"
        panel.message = "Export generated DF images as PNG"
        if panel.runModal() == .OK, let url = panel.url {
            exportImages(to: url)
        }
    }
    
    private func exportAtlas() {
        guard !generatedCGImages.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.prompt = "Choose"
        panel.title = "Choose export image name"
        panel.message = "Export generated DF images as a single PNG"
        if panel.runModal() == .OK, let url = panel.url {
            generateAndExportAtlas(to: url)
        }
    }

    private func exportImages(to folderURL: URL) {
        for (idx, cg) in generatedCGImages.enumerated() {
            let fileURL = folderURL.appendingPathComponent(String(format: "sdf_%03d.png", idx))
            if let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, cg, nil)
                if !CGImageDestinationFinalize(dest) {
                    Logger.shared.err("Failed to write \(fileURL.lastPathComponent)")
                }
            } else {
                Logger.shared.err("Failed to create destination for \(fileURL.path)")
            }
        }
    }
    
    private func generateAndExportAtlas(to fileURL: URL) {
        guard let cg = ConcatenateVertical(images: generatedCGImages) else {
            Logger.shared.err("Failed to create atlas")
            return
        }
        if let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cg, nil)
            if !CGImageDestinationFinalize(dest) {
                Logger.shared.err("Failed to write \(fileURL.lastPathComponent)")
            }
        } else {
            Logger.shared.err("Failed to create destination for \(fileURL.path)")
        }
    }

    @MainActor
    private func resetGeneratedOutputs() {
        generatedCGImages.removeAll()
    }

    private func computeEpsilon() -> Float {
        // Map 0..128 to 0..(128/255)
        return Float(maxColorDifference) / 255.0
    }

    private func computeAllSDFsSync() throws -> [CGImage] {
        guard let imageSampler else { throw NSError(domain: "RegionToSDF", code: 1, userInfo: [NSLocalizedDescriptionKey: "No image sampler"]) }
        let epsilon = computeEpsilon()
        var images: [CGImage] = []
        for color in palette {
            let cg = try makeSDF(for: color, sampler: imageSampler, epsilon: epsilon)
            if let cg { images.append(cg) }
        }
        return images
    }

    private func computeAllSDFsParallel() async -> [CGImage] {
        guard let imageSampler else { return [] }
        let epsilon = computeEpsilon()
        if selectedDF == .DensityDF {
            let rgbPalette = palette.map { $0.colorRGB }
            let multi = MultiRegionalDF(sampler: imageSampler, regionColors: rgbPalette)
            do {
                try multi.computeDF()
                if let cg = multi.densityAndDistanceFieldImage().toCGImage() {
                    return [cg]
                }
            } catch {
                Logger.shared.err("SDF failed: \(error.localizedDescription)")
            }
            return []
        }
        // Run per-color computations in parallel
        return await withTaskGroup(of: (Int, CGImage?).self) { group in
            for index in 0..<palette.count {
                let color = palette[index]
                group.addTask {
                    do {
                        let cg = try await makeSDF(for: color, sampler: imageSampler, epsilon: epsilon)
                        return (index, cg)
                    } catch {
                        await Logger.shared.err("SDF failed: \(error.localizedDescription)")
                        return (index, nil)
                    }
                }
            }
            var images: [CGImage] = []
            var order: [Int: Int] = [:]
            var i = 0
            for await result in group {
                if let cg = result.1 {
                    images.append(cg)
                    order[result.0] = i
                    i += 1
                }
            }
            // sort using order
            var sortedImages: [CGImage] = []
            let keys = order.keys.sorted()
            for k in keys {
                let i = order[k]!
                sortedImages.append(images[i])
            }
            return sortedImages
        }
    }

    private func computeAllSDFs() async {
        await MainActor.run { resetGeneratedOutputs() }
        let images = await computeAllSDFsParallel()
        await MainActor.run {
            self.generatedCGImages = images
        }
    }
}

#Preview {
    ContentView()
}

