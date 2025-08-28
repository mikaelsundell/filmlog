// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import PhotosUI
import QuickLook

class PDFPreviewController: NSObject, QLPreviewControllerDataSource {
    var fileURL: URL!
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return fileURL as QLPreviewItem
    }
}

struct RollDetailView: View {
    @Bindable var roll: Roll
    @Binding var selectedRoll: Roll?
    var index: Int
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedShot: Shot? = nil
    @State private var showCamera = false
    @State private var showDeleteAlert = false
    @State private var confirmMoveToShooting = false
    @State private var confirmMoveToProcessing = false
    @State private var confirmMoveToFinished = false

    var body: some View {
        Form {
            if roll.status == "shooting" || roll.status == "processing" || roll.status == "finished" {
                Section(header: Text("Shots")) {
                    if roll.orderedShots.isEmpty {
                        Text("No shots")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(roll.orderedShots.enumerated()), id: \.element.id) { index, shot in
                            NavigationLink(destination: {
                                ShotDetailView(shot: shot,
                                                roll: roll,
                                                index: index,
                                                count: roll.shots.count,
                                                onDelete: {
                                                    roll.shots = roll.shots.filter { $0.id != shot.id }
                                                })
                            }) {
                                Label {
                                    Text("\(index + 1).) \(shot.name.isEmpty ? shot.timestamp.formatted(date: .numeric, time: .standard) : shot.name) (\(shot.daysAgoText))")
                                        .font(.footnote)
                                } icon: {
                                    Image(systemName: "film.fill")
                                }
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("Roll")) {
                VStack(alignment: .leading) {
                    PhotoPickerView(
                        image: roll.imageData?.thumbnail,
                        label: "Add photo",
                        isLocked: roll.isLocked
                    ) { newUIImage in
                        let newImage = ImageData()
                        if newImage.updateFile(to: newUIImage) {
                            roll.updateImage(to: newImage, context: modelContext)
                        }
                    }
                }
                
                TextField("Name", text: $roll.name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit {
                        focused = false
                    }
                    .disabled(roll.isLocked)
                
                TextEditor(text: $roll.note)
                    .frame(height: 100)
                    .focused($focused)
                    .disabled(roll.isLocked)
                    .offset(x: -4)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                focused = false
                        }
                    }
                }
            }
            
            Section(header: Text("Info")) {
                Picker("Camera", selection: $roll.camera) {
                    ForEach(CameraUtils.cameras, id: \.self) { camera in
                        Text(camera).tag(camera)
                    }
                }
                .disabled(roll.isLocked)
                
                Picker("Counter", selection: $roll.counter) {
                    ForEach([5, 10, 20, 24, 30, 34], id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .disabled(roll.isLocked)
                
                Picker("Push/ pull", selection: $roll.pushPull) {
                    ForEach(["-3", "-2", "-1", "0", "+1", "+2", "+3"], id: \.self) { value in
                        Text("EV\(value)").tag(value)
                    }
                }
                .disabled(roll.isLocked)
                
                DatePicker("Film date", selection: $roll.filmDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .disabled(roll.isLocked)
                
                Picker("Film size", selection: $roll.filmSize) {
                    ForEach(CameraUtils.filmSizes, id: \.label) { size in
                        Text(size.label).tag(size.label)
                    }
                }
                .disabled(roll.isLocked)
                
                Picker("Film stock", selection: $roll.filmStock) {
                    ForEach(CameraUtils.filmStocks, id: \.label) { stock in
                        Text(stock.label).tag(stock.label)
                    }
                }
                .disabled(roll.isLocked)
            }
        
            if roll.status == "new" {
                Section {
                    Button(action: {
                        confirmMoveToShooting = true
                    }) {
                        Label("Move to Shooting", systemImage: "camera.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .listRowBackground(Color.clear)
                    .alert("Move to Shooting?", isPresented: $confirmMoveToShooting) {
                        Button("Confirm", role: .destructive) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    roll.status = "shooting"
                                    roll.isLocked = true
                                    addShot()
                                }
                            }
                            confirmMoveToShooting = false
                        }
                        Button("Cancel", role: .cancel) {
                            confirmMoveToShooting = false
                        }
                    } message: {
                        Text("Are you sure you want to move this roll to shooting?")
                    }
                }
            }
            
            if roll.status == "shooting" {
                Section {
                    Button(action: {
                        confirmMoveToProcessing = true
                    }) {
                        Label("Move to Processing", systemImage: "tray.and.arrow.down.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .listRowBackground(Color.clear)
                    .alert("Move to Processing?", isPresented: $confirmMoveToProcessing) {
                        Button("Confirm", role: .destructive) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    roll.status = "processing"
                                    roll.isLocked = true
                                }
                            }
                            confirmMoveToProcessing = false
                        }
                        Button("Cancel", role: .cancel) {
                            confirmMoveToProcessing = false
                        }
                    } message: {
                        Text("Are you sure you want to move this roll to processing?")
                    }
                }
            }

            if roll.status == "processing" {
                Section {
                    Button(action: {
                        confirmMoveToFinished = true
                    }) {
                        Label("Move to Finished", systemImage: "checkmark.seal.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .listRowBackground(Color.clear)
                    .alert("Mark as Finished?", isPresented: $confirmMoveToFinished) {
                        Button("Confirm", role: .destructive) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    roll.status = "finished"
                                    roll.isLocked = true
                                }
                            }
                            confirmMoveToFinished = false
                        }
                        Button("Cancel", role: .cancel) {
                            confirmMoveToFinished = false
                        }
                    } message: {
                        Text("Do you want to mark this roll as finished?")
                    }
                }
            }
        }
        .navigationTitle("\(roll.status.capitalized) \(roll.name.isEmpty ? "roll" : roll.name)")
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                let newImage = ImageData()
                if newImage.updateFile(to: image) {
                    roll.updateImage(to: newImage, context: modelContext)
                } else {
                    print("failed to save camera image for roll")
                }
            }
        }
        .onChange(of: selectedItem) {
            if let selectedItem {
                Task {
                    if let data = try? await selectedItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        let newImage = ImageData()
                        if newImage.updateFile(to: image) {
                            roll.updateImage(to: newImage, context: modelContext)
                        } else {
                            print("failed to save selected image for roll")
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: {
                    roll.isLocked.toggle()
                }) {
                    Image(systemName: roll.isLocked ? "lock.fill" : "lock.open")
                }
                .help(roll.isLocked ? "Unlock to edit roll info" : "Lock to prevent editing")

                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete this roll")

                Menu {
                    Button {
                        generatePDF()
                    } label: {
                        Label("Export as PDF", systemImage: "doc.richtext")
                    }

                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("More actions")
            }
        }
        .alert("Are you sure?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                withAnimation {
                    modelContext.safelyDelete(roll)
                    selectedRoll = nil
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This roll contains \(roll.shots.count) shot\(roll.shots.count == 1 ? "" : "s"). Are you sure you want to delete it?")
        }
    }

    private func addShot() {
        withAnimation {
            do {
                let newShot = Shot()
                newShot.name = "Untitled"
                newShot.filmSize = roll.filmSize
                newShot.filmStock = roll.filmStock
                modelContext.insert(newShot)
                try modelContext.save()
                
                roll.shots.append(newShot)
                try modelContext.save()
                
            } catch {
                print("failed to save shot: \(error)")
            }
        }
    }
    
    private func generatePDF() {
        let pageWidth: CGFloat = 595.2
        let pageHeight: CGFloat = 841.8
        let margin: CGFloat = 40
        let contentWidth = pageWidth - (margin * 2)
        let imageMaxWidth: CGFloat = 120

        let pdfMetaData = [
            kCGPDFContextCreator: "FilmLog App",
            kCGPDFContextAuthor: "FilmLog"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), format: format)

        let data = renderer.pdfData { context in
            context.beginPage()
            var yOffset: CGFloat = margin

            if let icon = UIImage(named: "AppIcon") {
                icon.draw(in: CGRect(x: margin, y: yOffset, width: 40, height: 40))
            }

            let title = "Roll - \(roll.name.isEmpty ? "Untitled" : roll.name)"
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let dateText = dateFormatter.string(from: roll.timestamp)

            title.draw(at: CGPoint(x: margin + 50, y: yOffset), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 18)
            ])
            dateText.draw(at: CGPoint(x: margin + 50, y: yOffset + 22), withAttributes: [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.gray
            ])
            yOffset += 60

            if let rollImage = UIImage(named: "RollPlaceholder") {
                let aspectRatio = rollImage.size.height / rollImage.size.width
                let imageHeight = imageMaxWidth * aspectRatio
                rollImage.draw(in: CGRect(x: margin, y: yOffset, width: imageMaxWidth, height: imageHeight))
            }

            let rollDetails = """
            Name: \(roll.name)
            Note: \(roll.note)
            Status: \(roll.status)

            Camera:
            Counter
            Push/ pull
            Film date
            Film size
            Film stock
            """

            rollDetails.draw(in: CGRect(x: margin + imageMaxWidth + 10, y: yOffset, width: contentWidth - imageMaxWidth - 10, height: 100), withAttributes: [
                .font: UIFont.systemFont(ofSize: 12)
            ])

            yOffset += 120

            let line = UIBezierPath(rect: CGRect(x: margin, y: yOffset, width: contentWidth, height: 1))
            UIColor.black.setFill()
            line.fill()
            yOffset += 20

            for (index, shot) in roll.orderedShots.enumerated() {
                if yOffset + 150 > pageHeight - margin {
                    context.beginPage()
                    yOffset = margin
                }
                
                if let imageData = shot.imageData,
                   let thumbnail = imageData.thumbnail {
                    let aspectRatio = thumbnail.size.height / thumbnail.size.width
                    let imgHeight = imageMaxWidth * aspectRatio
                    thumbnail.draw(in: CGRect(x: margin, y: yOffset, width: imageMaxWidth, height: imgHeight))
                } else {
                    UIColor.black.setFill()
                    UIBezierPath(rect: CGRect(x: margin, y: yOffset, width: imageMaxWidth, height: 80)).fill()
                    "Frame #\(index + 1)".draw(in: CGRect(x: margin + 10, y: yOffset + 30, width: 100, height: 20),
                                               withAttributes: [
                                                   .font: UIFont.boldSystemFont(ofSize: 12),
                                                   .foregroundColor: UIColor.white
                                               ])
                }

                let x1 = margin + imageMaxWidth + 10
                let columnWidth = (contentWidth - imageMaxWidth - 10) / 4

                let metadata = [
                    """
                    Name: \(shot.name)
                    Note: \(shot.note)
                    """,
                    """
                    Location:
                    Long/lat
                    Elevation
                    Color temperature
                    """,
                    """
                    Camera:
                    Aperture: \(shot.aperture)
                    Shutter: \(shot.shutter)
                    Compensation
                    """,
                    """
                    Lens:
                    \(shot.lensName)
                    Focal length: \(shot.lensFocalLength)
                    """
                ]

                for i in 0..<4 {
                    metadata[i].draw(in: CGRect(x: x1 + CGFloat(i) * columnWidth, y: yOffset, width: columnWidth, height: 100),
                                     withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
                }

                "Aspect ratio: \(String(format: "%.2f", shot.aspectRatio))"
                    .draw(at: CGPoint(x: x1, y: yOffset + 90),
                          withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.gray])

                yOffset += 110
            }

            let footerText = "Date: \(dateFormatter.string(from: Date()))"
            footerText.draw(at: CGPoint(x: margin, y: pageHeight - margin - 20),
                            withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.gray])
        }

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("Roll-\(roll.name).pdf")
        do {
            try data.write(to: tmpURL)

            let previewController = QLPreviewController()
            let previewDataSource = PDFPreviewController()
            previewDataSource.fileURL = tmpURL
            previewController.dataSource = previewDataSource

            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = scene.windows.first?.rootViewController {
                rootVC.present(previewController, animated: true)
            }
        } catch {
            print("failed to save PDF: \(error)")
        }
    }

}

extension Shot {
    var daysAgoText: String {
        let calendar = Calendar.current
        let now = Date()
        if let days = calendar.dateComponents([.day], from: timestamp, to: now).day {
            return "\(days) day\(days == 1 ? "" : "s")"
        }
        return "Unknown"
    }
}

