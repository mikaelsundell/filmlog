// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import PhotosUI

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
                    if roll.shots.isEmpty {
                        Text("No shots")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(roll.shots.sorted(by: { $0.timestamp < $1.timestamp }).enumerated()), id: \.element.id) { index, shot in
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
                                    Text("\(index + 1).) \(shot.name.isEmpty ? shot.timestamp.formatted(date: .numeric, time: .standard) : shot.name)")
                                        .font(.footnote)
                                } icon: {
                                    Image(systemName: "film")
                                }
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("Roll")) {
                VStack(alignment: .leading) {
                    PhotoSectionView(data: roll.image?.data, label: "Add photo", isLocked: roll.isLocked) { newImageData in
                        replaceImage(for: &roll.image, with: newImageData)
                    }
                }
                
                TextField("Name", text: $roll.name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit {
                        focused = false
                    }
                    .disabled(roll.isLocked)
                
                TextField("Note", text: $roll.note, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focused)
                    .disabled(roll.isLocked)
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
                    ForEach(CameraOptions.cameras, id: \.self) { camera in
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
                
                Picker("Film Size", selection: $roll.filmSize) {
                    ForEach(CameraOptions.filmSizes, id: \.label) { size in
                        Text(size.label).tag(size.label)
                    }
                }
                .disabled(roll.isLocked)
                
                Picker("Film Stock", selection: $roll.filmStock) {
                    ForEach(CameraOptions.filmStocks, id: \.self) { stock in
                        Text(stock).tag(stock)
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
                                    addFrame()
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
        .navigationTitle("\(roll.status.capitalized) roll \(index + 1)")
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9) {
                    replaceImage(for: &roll.image, with: data)
                }
            }
        }
        .onChange(of: selectedItem) {
            if let selectedItem {
                Task {
                    if let data = try? await selectedItem.loadTransferable(type: Data.self) {
                        replaceImage(for: &roll.image, with: data)
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
            }
        }
        .alert("Are you sure?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                withAnimation {
                    cleanupImage(roll.image)
                    modelContext.delete(roll)
                    selectedRoll = nil
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This roll contains \(roll.shots.count) shot\(roll.shots.count == 1 ? "" : "s"). Are you sure you want to delete it?")
        }
    }

    private func addFrame() {
        withAnimation {
            let newShot = Shot(timestamp: Date())
            newShot.filmSize = roll.filmSize
            roll.shots.append(newShot)
        }
    }

    private func replaceImage(for imageRef: inout ImageData?, with newData: Data) {
        if let oldImage = imageRef, oldImage.decrementReference() {
            modelContext.delete(oldImage)
        }
        imageRef = ImageData(data: newData)
    }

    private func cleanupImage(_ image: ImageData?) {
        if let img = image, img.decrementReference() {
            modelContext.delete(img)
        }
    }
}
