// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import PhotosUI
import SwiftData

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var galleries: [Gallery]
    @State private var searchText: String = ""
    @State private var selectedCategory: String? = nil
    @State private var showImagePicker = false
    @State private var selectedItem: PhotosPickerItem? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search images...", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Categories Section
                        HStack {
                            Text("Categories")
                                .font(.headline)
                            Spacer()
                            Button(action: addCategory) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(currentGallery.categories, id: \.self) { category in
                                    Text(category)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedCategory == category ? Color.blue : Color.blue.opacity(0.1))
                                        .foregroundColor(selectedCategory == category ? .white : .blue)
                                        .cornerRadius(12)
                                        .onTapGesture {
                                            selectedCategory = selectedCategory == category ? nil : category
                                        }
                                }
                            }
                            .padding(.horizontal)
                        }

                        Divider()
                            .padding(.horizontal)

                        // Images Grid
                        if filteredImages.isEmpty {
                            Text("No images found")
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        } else {
                            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(filteredImages, id: \.id) { image in
                                    if let uiImage = UIImage(data: image.data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: UIScreen.main.bounds.width / 3 - 4,
                                                   height: UIScreen.main.bounds.width / 3 - 4)
                                            .clipped()
                                            .cornerRadius(6)
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("Gallery")
            .onAppear {
                importSharedImages()
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showImagePicker = true }) {
                        Label("Add Image", systemImage: "plus")
                    }
                }
            }
            .photosPicker(isPresented: $showImagePicker, selection: $selectedItem, matching: .images)
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        let newImage = ImageData(data: data, category: selectedCategory ?? "")
                        modelContext.insert(newImage)
                        do {
                            try modelContext.save()
                        } catch {
                            print("failed to insert image: \(error)")
                        }

                        withAnimation {
                            currentGallery.images.append(newImage)
                        }

                        do {
                            try modelContext.save()
                        } catch {
                            print("failed to save gallery relationship: \(error)")
                        }
                    } else {
                        print("could not load image from PhotosPicker")
                    }
                }
            }
        }
    }

    private var currentGallery: Gallery {
        if let gallery = galleries.first {
            return gallery
        } else {
            let gallery = Gallery()
            modelContext.insert(gallery)
            try? modelContext.save() // ✅ Persist immediately
            return gallery
        }
    }

    private var filteredImages: [ImageData] {
        let allImages = currentGallery.images
        var imgs = allImages
        if let category = selectedCategory {
            imgs = imgs.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            imgs = imgs.filter { $0.id.uuidString.localizedCaseInsensitiveContains(searchText) }
        }
        return imgs
    }

    // MARK: - Actions
    private func addCategory() {
        let newCategory = "Category \(currentGallery.categories.count + 1)"
        currentGallery.categories.append(newCategory)
        try? modelContext.save()
    }

    private func importSharedImages() {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.mikaelsundell.filmlog") else {
            return
        }

        do {
            let files = try fileManager.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            let imageFiles = files.filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            if imageFiles.isEmpty {
                return
            }

            for imageFile in imageFiles {
                let baseName = imageFile.deletingPathExtension().lastPathComponent
                let jsonFile = containerURL.appendingPathComponent("\(baseName).json")

                if let data = try? Data(contentsOf: imageFile) {
                    var comment: String? = nil
                    var creator: String? = nil
                    var timestamp: Int? = nil

                    if fileManager.fileExists(atPath: jsonFile.path),
                       let jsonData = try? Data(contentsOf: jsonFile),
                       let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        comment = jsonObject["comment"] as? String
                        creator = jsonObject["creator"] as? String
                        timestamp = jsonObject["timestamp"] as? Int
                    }

                    let newImage = ImageData(
                        data: data,
                        category: selectedCategory,
                        comment: comment,
                        creator: creator,
                        timestamp: timestamp
                    )

                    modelContext.insert(newImage)
                    try modelContext.save()
                    
                    currentGallery.images.append(newImage)

                    try? fileManager.removeItem(at: imageFile)
                    if fileManager.fileExists(atPath: jsonFile.path) {
                        try? fileManager.removeItem(at: jsonFile)
                    }
                }
            }
            try modelContext.save()

        } catch {
            print("error reading shared images: \(error)")
        }
    }

}
