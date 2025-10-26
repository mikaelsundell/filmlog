// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import PhotosUI
import QuickLook

class PDFPreviewController: NSObject, QLPreviewControllerDataSource {
    var fileURL: URL!
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        fileURL as QLPreviewItem
    }
}

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Binding var selectedProject: Project?
    var index: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    @State private var activeShot: Shot? = nil
    @State private var showDeleteAlert = false
    @State private var confirmMoveToShooting = false
    @State private var confirmMoveToArchived = false

    var body: some View {
        ZStack {
            if activeShot == nil {
                VStack(spacing: 0) {
                    Form {
                        Section {
                            if project.orderedShots.isEmpty {
                                Text("No shots")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(project.orderedShots.enumerated()), id: \.element.id) { _, shot in
                                    Button {
                                        UIView.setAnimationsEnabled(false)
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            activeShot = shot
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            UIView.setAnimationsEnabled(true)
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(shot.name.isEmpty ? "Shot" : shot.name)
                                                    .font(.footnote)
                                                    .foregroundStyle(.white)

                                                let stock = CameraUtils.filmStock(for: shot.filmStock)
                                                let stockInfo = stock.speed > 0 ? "\(Int(stock.speed)) ISO" : stock.name

                                                Text("Film size: \(shot.filmSize), \(stockInfo)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.gray.opacity(0.8))
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            
                                            if let image = shot.imageData?.thumbnail {
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 64, height: 64)
                                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .stroke(Color.black.opacity(0.6), lineWidth: 0.5)
                                                    )
                                                    .shadow(radius: 1)
                                            } else {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(Color.white.opacity(0.1))
                                                        .frame(width: 64, height: 64)
                                                    
                                                    Image(systemName: "film.fill")
                                                        .renderingMode(.template)
                                                        .foregroundStyle(.white.opacity(0.7))
                                                        .font(.system(size: 28, weight: .regular))
                                                }
                                                .frame(width: 64, height: 64)
                                            }
                                            
                                            Image(systemName: "chevron.right")
                                                .renderingMode(.template)
                                                .foregroundStyle(.white)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Color.black)
                                }
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Text("SHOTS")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                                    .textCase(.uppercase)

                                if project.isLocked {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.5))
                                        .padding(.leading, 2)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.9))
                        }
                        .listRowBackground(Color.black)
                        
                        
                        Section(
                            header: HStack {
                                Text("Project")
                                if project.isLocked {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                        .padding(.leading, 4)
                                }
                            }
                        ) {
                            TextField("Name", text: $project.name)
                                .focused($focused)
                                .submitLabel(.done)
                                .onSubmit { focused = false }
                                .disabled(project.isLocked)
                            
                            HStack {
                                Text("Modified:")
                                Text(project.timestamp.formatted(date: .abbreviated, time: .shortened))
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        
                        Section(
                            header: HStack {
                                Text("Camera")
                                if project.isLocked {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                        .padding(.leading, 4)
                                }
                            }
                        ) {
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
                                ForEach(CameraUtils.groupedFilmSizes.keys.sorted(), id: \.self) { category in
                                    Section(header: Text(category)) {
                                        ForEach(CameraUtils.groupedFilmSizes[category] ?? [], id: \.name) { stock in
                                            Text(stock.name).tag(stock.name)
                                        }
                                    }
                                }
                            }
                            .disabled(project.isLocked)
                            
                            Picker("Film stock", selection: $project.filmStock) {
                                ForEach(CameraUtils.groupedFilmStocks.keys.sorted(), id: \.self) { category in
                                    Section(header: Text(category)) {
                                        ForEach(CameraUtils.groupedFilmStocks[category] ?? [], id: \.name) { stock in
                                            Text(stock.name).tag(stock.name)
                                        }
                                    }
                                }
                            }
                            .disabled(project.isLocked)
                        }
                        
                        Section(
                            header: HStack {
                                Text("Note")
                                if project.isLocked {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                        .padding(.leading, 4)
                                }
                            }
                        ) {
                            TextEditor(text: $project.note)
                                .frame(height: 64)
                                .focused($focused)
                                .disabled(project.isLocked)
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
                        }
                    }
                    .transition(.opacity)
                    
                    if !focused {
                        HStack {
                            Button {
                                showDeleteAlert = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 18, weight: .semibold))
                                    .frame(width: 40, height: 40)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                            .help("Delete project")
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Image(systemName: "film")
                                    .font(.system(size: 14, weight: .medium))
                                Text("\(project.shots.count) shot\(project.shots.count == 1 ? "" : "s")")
                                    .font(.subheadline)
                                    .fontWeight(.regular)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .foregroundColor(.blue)
                            .shadow(radius: 1)
                            
                            Spacer()
                            
                            Button {
                                if project.isArchived {
                                    withAnimation {
                                        project.isArchived = false
                                        project.isLocked = false
                                        for shot in project.shots {
                                            shot.isLocked = false
                                        }
                                        try? modelContext.save()
                                    }
                                } else {
                                    confirmMoveToArchived = true
                                }
                            } label: {
                                Image(systemName: project.isArchived ? "archivebox" : "archivebox.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .frame(width: 40, height: 40)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                            .help(project.isArchived ? "Unarchive project" : "Mark project as archived")
                            .alert("Mark as Archived?", isPresented: $confirmMoveToArchived) {
                                Button("Confirm", role: .destructive) {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation {
                                            project.isArchived = true
                                            project.isLocked = true
                                            for shot in project.shots {
                                                shot.isLocked = true
                                            }
                                        }
                                    }
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("Do you want to mark this project as archived?")
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color.black)
                        .ignoresSafeArea(edges: .bottom)
                    }
                }
            }

            if let shot = activeShot,
               let index = project.orderedShots.firstIndex(where: { $0.id == shot.id }) {
                ShotDetailView(
                    shot: project.orderedShots[index],
                    project: project,
                    index: index,
                    count: project.orderedShots.count,
                    onAdd: { count in addShot(count: count) },
                    onDelete: {
                        project.shots.removeAll { $0.id == shot.id }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeShot = nil
                        }
                    },
                    onSelect: { newIndex in
                        guard newIndex >= 0 && newIndex < project.orderedShots.count else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeShot = project.orderedShots[newIndex]
                        }
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeShot = nil
                        }
                    }
                )
                .navigationBarHidden(true)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: activeShot)
        .navigationTitle("\(project.name.isEmpty ? "project" : project.name)")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if activeShot == nil {
                    Button {
                        addShot(count: 1)
                    } label: {
                        Label("Add shot", systemImage: "plus")
                    }
                    
                    Button(action: {
                    }) {
                        Image(systemName: "display")
                    }
                    .help("Play slideshow of project shots")

                    Menu {
                        Button {
                            project.isLocked.toggle()
                            for shot in project.shots {
                                shot.isLocked = project.isLocked
                            }
                            try? modelContext.save()
                        } label: {
                            Label(
                                project.isLocked ? "Unlock Project" : "Lock Project",
                                systemImage: project.isLocked ? "lock.open" : "lock.fill"
                            )
                        }
                        Divider()
                        
                        Button {
                            generatePDF()
                        } label: {
                            Label("Export as PDF", systemImage: "doc.richtext")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
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
    
    private func addShot(count: Int = 1) {
        withAnimation {
            do {
                for _ in 0..<count {
                    let newShot = Shot.createDefault(for: project, in: modelContext)
                    try modelContext.save()
                    project.shots.append(newShot)
                }
                
            } catch {
                print("Failed to add shot(s): \(error)")
            }
        }
    }

    private func generatePDF() {
        // PDF generation unchanged
    }
}

extension Shot {
    var daysAgoText: String {
        let calendar = Calendar.current
        if let days = calendar.dateComponents([.day], from: timestamp, to: Date()).day {
            return "\(days) day\(days == 1 ? "" : "s")"
        }
        return "Unknown"
    }
}
