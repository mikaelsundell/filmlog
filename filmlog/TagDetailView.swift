// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI

struct TagDetailView: View {
    @Bindable var tag: Tag
    var index: Int
    var count: Int
    var onSelect: ((Int) -> Void)?
    var onBack: (() -> Void)?
    
    enum Field {
        case name, note
    }
    @FocusState private var activeField: Field?
    
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
                Text(tag.name)
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
            .shadow(radius: 2)
            
            Form {
                Section(header:
                            HStack {
                    Text("Tag")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                    Spacer()
                }
                ) {
                    HStack {
                        TextField("Name", text: $tag.name)
                            .focused($activeField, equals: .name)
                            .submitLabel(.done)
                            .textInputAutocapitalization(.words)
                        
                        if !tag.name.isEmpty {
                            Button {
                                tag.name = ""
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
                        Text(tag.timestamp.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                
                Section(header:
                            HStack {
                    Text("Color")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                    Spacer()
                }
                ) {
                    HStack {
                        ColorPicker("Tag color", selection: Binding(
                            get: { Color(hex: tag.color ?? "#007AFF") ?? .blue },
                            set: { newColor in
                                tag.color = newColor.toHex()
                                tag.timestamp = Date()
                                try? modelContext.save()
                            }
                        ))
                        .labelsHidden()
                        
                        Circle()
                            .fill(Color(hex: tag.color ?? "#007AFF") ?? .blue)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                    }
                }
                
                Section(header:
                            HStack {
                    Text("Note")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                    Spacer()
                }
                ) {
                    TextEditor(text: $tag.note)
                        .frame(height: 80)
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
            .scrollContentBackground(.hidden)
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.05))
    }
}
