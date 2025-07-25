// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import PhotosUI
import SwiftData

struct ThumbnailView: View {
    let imageData: ImageData
    let size: CGFloat

    var body: some View {
        Group {
            if let uiImage = UIImage(data: imageData.data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
                    .cornerRadius(0)
                    .contentShape(Rectangle())
            } else {
                Color.gray
                    .frame(width: size, height: size)
                    .cornerRadius(4)
            }
        }
    }
}

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var galleries: [Gallery]
    @State private var searchText: String = ""
    @State private var selectedCategory: Category? = nil
    @State private var showImagePicker = false
    @State private var selectedItem: PhotosPickerItem? = nil
    
    @State private var showCategoryEditSheet = false
    @State private var selectedCategoryForEdit: Category? = nil
    @State private var showEditOptions = false
    @State private var showRenameDialog = false
    @State private var renameText = ""
    
    @State private var selectedImageForEdit: ImageData? = nil
    @State private var newComment = ""
    @State private var newCategory: Category? = nil
    
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                
                VStack(alignment: .leading, spacing: 12) {
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
                            ForEach(currentGallery.orderedCategories) { category in
                                Text(category.name)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedCategory == category ? Color.blue : Color.blue.opacity(0.1))
                                    .foregroundColor(selectedCategory == category ? .white : .blue)
                                    .cornerRadius(12)
                                    .onTapGesture {
                                        selectedCategory = selectedCategory == category ? nil : category
                                    }
                                    .contextMenu {
                                        Button {
                                            selectedCategoryForEdit = category
                                            renameText = category.name
                                            showCategoryEditSheet = true
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        
                                        Button(role: .destructive) {
                                            deleteCategory(category)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    HStack {
                        Text("Images")
                            .font(.headline)
                    }
                    .padding(.horizontal)
                }

                ScrollView {
                    if filteredImages.isEmpty {
                        Text("No images found")
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        let gridWidth = UIScreen.main.bounds.width / 3 - 8
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
                        
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(filteredImages, id: \.id) { image in
                                ThumbnailView(imageData: image, size: gridWidth)
                                    .contentShape(Rectangle())
                                    .contextMenu {
                                        Button {
                                            selectedImageForEdit = image
                                            newComment = image.comment ?? ""
                                            newCategory = image.category
                                        } label: {
                                            Label("Edit image", systemImage: "pencil")
                                        }

                                        Button(role: .destructive) {
                                            deleteImage(image)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .id(image.id)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.top)
            }
            .navigationTitle("Gallery")
            .onAppear {
                importSharedImages()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    importSharedImages()
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        let newImage = ImageData(data: data, category: selectedCategory)
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
            .alert("Rename category", isPresented: $showRenameDialog) {
                TextField("Category name", text: $renameText)
                Button("Save") {
                    if let category = selectedCategoryForEdit {
                        category.name = renameText
                        try? modelContext.save()
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showCategoryEditSheet) {
                if let category = selectedCategoryForEdit {
                    NavigationView {
                        Form {
                            Section(header: Text("Rename category")) {
                                TextField("Category name", text: $renameText)
                            }
                        }
                        .navigationTitle("Edit category")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    category.name = renameText
                                    try? modelContext.save()
                                    showCategoryEditSheet = false
                                }
                            }
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    showCategoryEditSheet = false
                                }
                            }
                        }
                    }
                }
            }
            .sheet(item: $selectedImageForEdit) { image in
                NavigationView {
                    Form {
                        Section(header: Text("Comment")) {
                            TextField("Enter comment", text: $newComment)
                        }

                        Section(header: Text("Category")) {
                            Picker("Select category", selection: $newCategory) {
                                Text("None").tag(Category?.none)
                                ForEach(currentGallery.orderedCategories) { category in
                                    Text(category.name).tag(Optional(category))
                                }
                            }
                        }
                    }
                    .onAppear {
                        print("Show image for edit UUID: \(image.id)")
                    }
                    .navigationTitle("Edit image")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                image.comment = newComment
                                image.category = newCategory
                                try? modelContext.save()
                                selectedImageForEdit = nil
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                selectedImageForEdit = nil
                            }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showImagePicker = true }) {
                        Label("Add Images", systemImage: "plus")
                    }
                }
            }
            .photosPicker(
                isPresented: $showImagePicker,
                selection: $selectedItems,
                maxSelectionCount: 10,
                matching: .images
            )
            .onChange(of: selectedItems) { oldItems, newItems in
                for item in newItems {
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            let newImage = ImageData(data: data, category: selectedCategory)
                            modelContext.insert(newImage)
                            do {
                                try modelContext.save()
                            } catch {
                                print("failed to insert image: \(error)")
                            }
                            withAnimation {
                                currentGallery.images.append(newImage)
                            }
                        }
                    }
                }
                selectedItems.removeAll()
            }
        }
    }
    
    private var currentGallery: Gallery {
        if let gallery = galleries.first {
            return gallery
        } else {
            let gallery = Gallery()
            modelContext.insert(gallery)
            try? modelContext.save()
            return gallery
        }
    }

    private var filteredImages: [ImageData] {
        var imgs = currentGallery.orderedImages
        if let category = selectedCategory {
            imgs = imgs.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            imgs = imgs.filter { $0.comment?.localizedCaseInsensitiveContains(searchText) == true }
        }
        return imgs
    }

    private func addCategory() {
        do {
            let newCategory = Category(name: "Category \(currentGallery.categories.count + 1)")
            modelContext.insert(newCategory)
            try modelContext.save()
            
            currentGallery.categories.append(newCategory)
            try modelContext.save()
        } catch {
            print("failed to add category: \(error)")
        }
    }
    
    private func deleteCategory(_ category: Category) {
        for image in currentGallery.images where image.category?.id == category.id {
            image.category = nil
        }
        if let index = currentGallery.categories.firstIndex(where: { $0.id == category.id }) {
            currentGallery.categories.remove(at: index)
        }
        modelContext.delete(category)
        do {
            try modelContext.save()
        } catch {
            print("failed to delete category: \(error)")
        }
    }
    
    private func deleteImage(_ image: ImageData) {
        if let index = currentGallery.images.firstIndex(where: { $0.id == image.id }) {
            currentGallery.images.remove(at: index)
        }
        modelContext.delete(image)
        do {
            try modelContext.save()
        } catch {
            print("failed to delete image: \(error)")
        }
    }

    private func importSharedImages() {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.mikaelsundell.filmlog") else {
            return
        }

        do {
            let files = try fileManager.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            let imageFiles = files.filter {
                let fileName = $0.lastPathComponent.lowercased()
                let ext = $0.pathExtension.lowercased()
                return fileName.hasPrefix("shared_") && ["jpg", "jpeg", "png"].contains(ext)
            }
            if imageFiles.isEmpty {
                return
            }

            for imageFile in imageFiles {
                let baseName = imageFile.deletingPathExtension().lastPathComponent
                let jsonFile = containerURL.appendingPathComponent("\(baseName).json")

                if let data = try? Data(contentsOf: imageFile) {
                    var comment: String? = nil
                    var creator: String? = nil
                    var timestamp: Date? = nil

                    if fileManager.fileExists(atPath: jsonFile.path),
                       let jsonData = try? Data(contentsOf: jsonFile),
                       let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        comment = jsonObject["comment"] as? String
                        creator = jsonObject["creator"] as? String
                        timestamp = jsonObject["timestamp"] as? Date
                    }

                    let newImage = ImageData(
                        data: data,
                        category: selectedCategory,
                        comment: comment,
                        creator: creator
                    )
                    
                    newImage.timestamp = timestamp ?? Date()

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
