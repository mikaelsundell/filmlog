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

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Binding var selectedProject: Project?
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
            if project.status == "shooting" || project.status == "finished" {
                Section(header: Text("Shots")) {
                    if project.orderedShots.isEmpty {
                        Text("No shots")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(project.orderedShots.enumerated()), id: \.element.id) { index, shot in
                            NavigationLink(destination: {
                                ShotDetailView(shot: shot,
                                                project: project,
                                                index: index,
                                                count: project.shots.count,
                                                onDelete: {
                                                    project.shots = project.shots.filter { $0.id != shot.id }
                                                })
                            }) {
                                Label {
                                    Text(shot.name.isEmpty ? shot.timestamp.formatted(date: .numeric, time: .standard) : shot.name).font(.footnote)
                                } icon: {
                                    if let thumbnail = shot.imageData?.thumbnail {
                                        Image(uiImage: thumbnail)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 32, height: 32)
                                            .clipShape(RoundedRectangle(cornerRadius: 2))
                                    } else {
                                        Image(systemName: "film.fill")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("Project")) {
                TextField("Name", text: $project.name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit {
                        focused = false
                    }
                    .disabled(project.isLocked)
                
                TextEditor(text: $project.note)
                    .frame(height: 44)
                    .focused($focused)
                    .disabled(project.isLocked)
                    .font(.footnote)
                    .padding(.horizontal, -4)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(6)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { focused = false }
                        }
                    }
                
                HStack {
                    Text("Created:")
                    Text(project.timestamp.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            
            Section(header: Text("Info")) {
                Picker("Camera", selection: $project.camera) {
                    ForEach(CameraUtils.cameras, id: \.name) { camera in
                        Text(camera.name).tag(camera.name)
                    }
                }
                .disabled(project.isLocked)
                
                Picker("Counter", selection: $project.counter) {
                    ForEach([5, 10, 20, 24, 30, 34], id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .disabled(project.isLocked)
                
                Picker("Push/ pull", selection: $project.pushPull) {
                    ForEach(["-3", "-2", "-1", "0", "+1", "+2", "+3"], id: \.self) { value in
                        Text("EV\(value)").tag(value)
                    }
                }
                .disabled(project.isLocked)
                
                DatePicker("Film date", selection: $project.filmDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .disabled(project.isLocked)
                
                Picker("Film size", selection: $project.filmSize) {
                    ForEach(CameraUtils.filmSizes, id: \.name) { size in
                        Text(size.name).tag(size.name)
                    }
                }
                .disabled(project.isLocked)
                
                Picker("Film stock", selection: $project.filmStock) {
                    ForEach(CameraUtils.filmStocks, id: \.name) { stock in
                        Text(stock.name).tag(stock.name)
                    }
                }
                .disabled(project.isLocked)
            }
        
            if project.status == "new" {
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
                                    project.status = "shooting"
                                    project.isLocked = true
                                    addShot()
                                }
                            }
                            confirmMoveToShooting = false
                        }
                        Button("Cancel", role: .cancel) {
                            confirmMoveToShooting = false
                        }
                    } message: {
                        Text("Are you sure you want to move this project to shooting?")
                    }
                }
            }

            if project.status == "shooting" {
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
                                    project.status = "finished"
                                    project.isLocked = true
                                }
                            }
                            confirmMoveToFinished = false
                        }
                        Button("Cancel", role: .cancel) {
                            confirmMoveToFinished = false
                        }
                    } message: {
                        Text("Do you want to mark this project as finished?")
                    }
                }
            }
        }
        .navigationTitle("\(project.status.capitalized) \(project.name.isEmpty ? "project" : project.name)")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: {
                    project.isLocked.toggle()
                }) {
                    Image(systemName: project.isLocked ? "lock.fill" : "lock.open")
                }
                .help(project.isLocked ? "Unlock to edit project info" : "Lock to prevent editing")

                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete this project")

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
                    modelContext.safelyDelete(project)
                    selectedProject = nil
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This project contains \(project.shots.count) shot\(project.shots.count == 1 ? "" : "s"). Are you sure you want to delete it?")
        }
    }

    private func addShot() {
        withAnimation {
            do {
                let newShot = Shot()
                newShot.name = "Untitled"
                newShot.filmSize = project.filmSize
                newShot.filmStock = project.filmStock
                modelContext.insert(newShot)
                try modelContext.save()
                
                project.shots.append(newShot)
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

            let title = "Project - \(project.name.isEmpty ? "Untitled" : project.name)"
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let dateText = dateFormatter.string(from: project.timestamp)

            title.draw(at: CGPoint(x: margin + 50, y: yOffset), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 18)
            ])
            dateText.draw(at: CGPoint(x: margin + 50, y: yOffset + 22), withAttributes: [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.gray
            ])
            yOffset += 60

            if let projectImage = UIImage(named: "ProjectPlaceholder") {
                let aspectRatio = projectImage.size.height / projectImage.size.width
                let imageHeight = imageMaxWidth * aspectRatio
                projectImage.draw(in: CGRect(x: margin, y: yOffset, width: imageMaxWidth, height: imageHeight))
            }

            let projectDetails = """
            Name: \(project.name)
            Note: \(project.note)
            Status: \(project.status)

            Camera:
            Counter
            Push/ pull
            Film date
            Film size
            Film stock
            """

            projectDetails.draw(in: CGRect(x: margin + imageMaxWidth + 10, y: yOffset, width: contentWidth - imageMaxWidth - 10, height: 100), withAttributes: [
                .font: UIFont.systemFont(ofSize: 12)
            ])

            yOffset += 120

            let line = UIBezierPath(rect: CGRect(x: margin, y: yOffset, width: contentWidth, height: 1))
            UIColor.black.setFill()
            line.fill()
            yOffset += 20

            for (index, shot) in project.orderedShots.enumerated() {
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
                    \(shot.lens)
                    Focal length: \(shot.focalLength)
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

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("Project-\(project.name).pdf")
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

