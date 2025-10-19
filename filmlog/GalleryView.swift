// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import PhotosUI
import SwiftData

struct ImageView: View {
    let imageData: ImageData
    let size: CGFloat
    var body: some View {
        Group {
            if let uiImage = imageData.thumbnail {
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

    @State private var showDeleteCategoryAlert = false
    @State private var categoryToDelete: Category? = nil
    
    @State private var selectedImageForEdit: ImageData? = nil
    @State private var newName = ""
    @State private var newNote = ""
    @State private var newCategories: [Category] = []
    @State private var newSelectedCategories: Set<Category> = []
    @FocusState private var selectedImageFocused: Bool
    
    @State private var showDeleteImageAlert = false
    @State private var imageToDelete: ImageData? = nil
    
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        
        /*
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
                                            categoryToDelete = category
                                            showDeleteCategoryAlert = true
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
                                ImageView(imageData: image, size: gridWidth)
                                    .contentShape(Rectangle())
                                    .contextMenu {
                                        Button {
                                            selectedImageForEdit = image
                                            newName = image.name ?? ""
                                            newNote = image.note ?? ""
                                            newCategories = image.categories
                                        } label: {
                                            Label("Edit image", systemImage: "pencil")
                                        }

                                        Button(role: .destructive) {
                                            imageToDelete = image
                                            showDeleteImageAlert = true
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
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        do {
                            let newImage = ImageData()
                            if newImage.updateFile(to: uiImage) {
                                modelContext.insert(newImage)
                                try modelContext.save()

                                withAnimation {
                                    currentGallery.addImage(newImage)
                                }

                                try modelContext.save()
                            } else {
                                print("failed to save image file for new image")
                            }
                        } catch {
                            print("failed to insert image: \(error)")
                        }
                    } else {
                        print("could not load image from PhotosPicker")
                    }
                }
            }
            .alert("Delete Category?", isPresented: $showDeleteCategoryAlert, presenting: categoryToDelete) { category in
                Button("Delete", role: .destructive) {
                    deleteCategory(category)
                }
                Button("Cancel", role: .cancel) { }
            } message: { category in
                Text("Are you sure you want to delete the category \(category.name)?")
            }
            .alert("Delete Image?", isPresented: $showDeleteImageAlert, presenting: imageToDelete) { image in
                Button("Delete", role: .destructive) {
                    deleteImage(image)
                }
                Button("Cancel", role: .cancel) { }
            } message: { image in
                Text("Are you sure you want to delete \(image.name ?? "this image")?")
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
                        Section(header: Text("Image")) {
                            TextField("Name", text: $newName)
                                .focused($selectedImageFocused)
                            
                            TextEditor(text: $newNote)
                                .frame(height: 100)
                                .focused($selectedImageFocused)
                                .offset(x: -4)
                        }
                        
                        Section(header: Text("Categories")) {
                            NavigationLink("Select categories") {
                                CategoryPickerView(
                                    selectedCategories: $newSelectedCategories,
                                    allCategories: currentGallery.orderedCategories
                                )
                                .navigationTitle("Select Categories")
                            }

                            if !newSelectedCategories.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(Array(newSelectedCategories)) { category in
                                            Text(category.name)
                                                .padding(8)
                                                .background(Color.accentColor.opacity(0.2))
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    .onAppear {
                        selectedImageFocused = true
                    }
                    .navigationTitle("Edit image")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                image.name = newName
                                image.note = newNote
                                image.categories = Array(newSelectedCategories)
                                try? modelContext.save()
                                selectedImageForEdit = nil
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                selectedImageForEdit = nil
                            }
                        }
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                selectedImageFocused = false
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            do {
                                let newImage = ImageData()
                                if newImage.updateFile(to: uiImage) {
                                    modelContext.insert(newImage)
                                    try modelContext.save()

                                    withAnimation {
                                        currentGallery.addImage(newImage)
                                    }
                                    try modelContext.save()
                                } else {
                                    print("failed to save image file for new image")
                                }
                            } catch {
                                print("failed to insert image: \(error)")
                            }
                        } else {
                            print("could not load image from PhotosPicker")
                        }
                    }
                }
                selectedItems.removeAll()
            }
        }*/
         
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
            imgs = imgs.filter { $0.categories.contains(category) }
        }
        if !searchText.isEmpty {
            imgs = imgs.filter {
                ($0.note?.localizedCaseInsensitiveContains(searchText) == true) ||
                ($0.name?.localizedCaseInsensitiveContains(searchText) == true)
            }
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
        do {
            for image in currentGallery.orderedImages {
                if let index = image.categories.firstIndex(where: { $0.id == category.id }) {
                    image.categories.remove(at: index)
                }
            }

            if let index = currentGallery.categories.firstIndex(where: { $0.id == category.id }) {
                currentGallery.categories.remove(at: index)
            }

            modelContext.delete(category)
            try modelContext.save()

        } catch {
            print("failed to delete category: \(error)")
        }
    }
    
    private func deleteImage(_ image: ImageData) {
        do {
            currentGallery.deleteImage(image, context: modelContext)
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

                if let data = try? Data(contentsOf: imageFile),
                   let image = UIImage(data: data) {

                    var name: String? = nil
                    var note: String? = nil
                    var creator: String? = nil
                    var timestamp: Date? = nil

                    if fileManager.fileExists(atPath: jsonFile.path),
                       let jsonData = try? Data(contentsOf: jsonFile),
                       let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        name = jsonObject["name"] as? String
                        note = jsonObject["note"] as? String
                        creator = jsonObject["creator"] as? String
                        if let timestampString = jsonObject["timestamp"] as? String {
                            let formatter = ISO8601DateFormatter()
                            timestamp = formatter.date(from: timestampString)
                        }
                    }

                    let newImage = ImageData(name: name, note: note, creator: creator)
                    newImage.timestamp = timestamp ?? Date()

                    if let selectedCategory {
                        newImage.categories.append(selectedCategory)
                    }

                    if newImage.updateFile(to: image) {
                        modelContext.insert(newImage)
                        try modelContext.save()

                        currentGallery.addImage(newImage)

                        try? fileManager.removeItem(at: imageFile)
                        if fileManager.fileExists(atPath: jsonFile.path) {
                            try? fileManager.removeItem(at: jsonFile)
                        }
                    } else {
                        print("failed to save image data for file: \(imageFile.lastPathComponent)")
                    }
                } else {
                    print("could not load image from file: \(imageFile.lastPathComponent)")
                }
            }
            try modelContext.save()
            
        } catch {
            print("error reading shared images: \(error)")
        }
    }
}
