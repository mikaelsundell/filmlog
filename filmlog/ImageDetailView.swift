// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import CoreLocation

struct ImageDetailView: View {
    @Bindable var image: ImageData
    var gallery: Gallery
    var index: Int
    var count: Int
    var onSelect: ((Int) -> Void)?
    var onBack: (() -> Void)?

    enum ActiveField {
        case name, note
    }
    @FocusState private var activeField: ActiveField?
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack {
                    Button {
                        onBack?()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 24, weight: .regular))
                            .frame(width: 46, height: 46)
                    }
                    .padding(.leading, -6)
                    .buttonStyle(.borderless)
                }
                .frame(width: 80, alignment: .leading)
                Text(image.name ?? "Untitled")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                HStack(spacing: 8) {
                    Button {
                        let previousIndex = (index - 1 + count) % count
                        onSelect?(previousIndex)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 24, weight: .regular))
                    }
                    .buttonStyle(.borderless)

                    Button {
                        let nextIndex = (index + 1) % count
                        onSelect?(nextIndex)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 24, weight: .regular))
                    }
                    .buttonStyle(.borderless)
                }
                .frame(width: 80, alignment: .trailing)
                .padding(.trailing, 16)
            }
            .background(Color.black)
            .shadow(radius: 2)
            
            if let uiImage = image.original ?? image.thumbnail {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .cornerRadius(10)
                    .padding(.horizontal, 16)   // add side padding
                    .padding(.vertical, 12)     // increase top/bottom
            } else {
                Color.gray
                    .frame(height: 180)
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            
            Form {
                Section(
                    header: HStack {
                        Text("Image")
                    }
                ) {
                    HStack {
                        TextField("Name", text: Binding(
                            get: { image.name ?? "" },
                            set: { image.name = $0.isEmpty ? nil : $0 }
                        ))
                            .focused($activeField, equals: .name)
                            .submitLabel(.done)
                        if let name = image.name, !name.isEmpty {
                            Button {
                                image.name = ""
                                DispatchQueue.main.async {
                                    UIView.performWithoutAnimation {
                                        activeField = .name
                                    }
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 2)
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                    HStack {
                        Text("Modified:")
                        Text(image.timestamp.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                
                Section("Tags") {
                    if gallery.orderedTags.isEmpty {
                        Text("No tags available")
                            .foregroundColor(.secondary)
                    } else {
                        FlowLayout(spacing: 8, lineSpacing: 10) {
                            ForEach(gallery.orderedTags) { tag in
                                let isSelected = image.tags.contains(where: { $0.id == tag.id })
                                Text(tag.name)
                                    .font(.caption)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        tag.defaultColor.opacity(isSelected ? 1.0 : 0.1)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                tag.defaultColor.opacity(tag.isDefaultColor ? 0.4 : 1.0),
                                                lineWidth: 1.2
                                            )
                                    )
                                    .foregroundColor(isSelected ? .white : .gray)
                                    .cornerRadius(12)
                                    .onTapGesture {
                                        toggleTag(tag)
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section(
                    header: HStack {
                        Text("Note")
                    }
                ) {
                    TextEditor(text: Binding(
                        get: { image.note ?? "" },
                        set: { image.note = $0.isEmpty ? nil : $0 }
                    ))
                        .frame(height: 64)
                        .focused($activeField, equals: .note)
                        .padding(.horizontal, -4)
                        .scrollContentBackground(.hidden)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(6)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { activeField = nil }
                            }
                        }
                }
            }
        }
        .navigationBarBackButtonHidden(false)
    }
    
    private func toggleTag(_ tag: Tag) {
        if let index = image.tags.firstIndex(where: { $0.id == tag.id }) {
            image.tags.remove(at: index)
        } else {
            image.tags.append(tag)
        }
        do {
            try modelContext.save()
        } catch {
            print("failed to update image tags: \(error)")
        }
    }
}
