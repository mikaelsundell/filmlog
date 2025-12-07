// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI

struct TagView: View {
    let gallery: Gallery
    @Binding var filterTags: [Tag]

    @State private var filterText: String = ""
    @State private var activeTag: Tag? = nil
    @State private var selectedTags: Set<Tag> = []
    
    enum ActiveField {
        case name, note
    }
    @FocusState private var activeField: ActiveField?
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack {
            if activeTag == nil {
                VStack(spacing: 0) {
                    Form {
                        Section {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.gray)
                                TextField("Filter tags...", text: $filterText)
                                    .textFieldStyle(.plain)
                                    .autocorrectionDisabled()
                                Button(action: addTag) {
                                    Image(systemName: "plus.circle")
                                        .font(.title2)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color(red: 0.05, green: 0.05, blue: 0.05))
                    .frame(maxHeight: 100)

                    let filteredTags = gallery.orderedTags.filter {
                        filterText.isEmpty || $0.name.localizedCaseInsensitiveContains(filterText)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if filteredTags.isEmpty {
                                Text("No tags available")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                            } else {
                                FlowLayout(spacing: 8, lineSpacing: 10) {
                                    ForEach(filteredTags) { tag in
                                        let count = gallery.orderedImages.filter { $0.tags.contains(tag) }.count
                                        let displayName = count > 0 ? "\(tag.name) (\(count))" : tag.name
                                        let isSelected = selectedTags.contains(tag)
                                        
                                        Text(displayName)
                                            .font(.caption)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(tag.defaultColor.opacity(isSelected ? 1.0 : 0.1))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(
                                                        tag.defaultColor.opacity(tag.isDefaultColor ? 0.4 : 1.0),
                                                        lineWidth: 1.2
                                                    )
                                            )
                                            .foregroundColor(isSelected ? .white : .gray)
                                            .cornerRadius(12)
                                            .transition(.asymmetric(
                                                insertion: .opacity,
                                                removal: .scale.combined(with: .opacity)
                                            ))
                                            .onTapGesture {
                                                toggleTagSelection(tag)
                                            }
                                            .contextMenu {
                                                Button {
                                                    activeTag = tag
                                                } label: {
                                                    Label("Edit", systemImage: "pencil")
                                                }

                                                Button(role: .destructive) {
                                                    withAnimation(.easeInOut(duration: 0.25)) {
                                                        deleteTag(tag)
                                                    }
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(Color(red: 0.05, green: 0.05, blue: 0.05))
                .onAppear {
                    selectedTags = Set(filterTags)
                }
                .onChange(of: selectedTags) { _, newValue in
                    filterTags = Array(newValue)
                }
            }

            if let tag = activeTag,
               let index = gallery.orderedTags.firstIndex(where: { $0.id == tag.id }) {
                TagDetailView(
                    tag: tag,
                    index: index,
                    count: gallery.orderedTags.count,
                    onSelect: { newIndex in
                        guard newIndex >= 0 && newIndex < gallery.orderedTags.count else { return }
                        activeTag = gallery.orderedTags[newIndex]
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeTag = nil
                        }
                    }
                )
            }
        }
    }
    
    private func addTag() {
        do {
            let newTag = Tag(name: "New Tag", note: "")
            modelContext.insert(newTag)
            try modelContext.save()
            gallery.tags.append(newTag)
        } catch {
            print("failed to create new tag: \(error)")
        }
    }

    private func deleteTag(_ tag: Tag) {
        do {
            for image in gallery.orderedImages {
                image.tags.removeAll(where: { $0.id == tag.id })
            }
            gallery.tags.removeAll(where: { $0.id == tag.id })
            modelContext.delete(tag)
            try modelContext.save()
        } catch {
            print("failed to delete tag: \(error)")
        }
    }
    
    private func toggleTagSelection(_ tag: Tag) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}
