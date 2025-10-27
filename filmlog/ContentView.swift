// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var projects: [Project]
    @State private var selectedProject: Project? = nil
    
    @State private var projectToDelete: Project?
    @State private var showDeleteAlert = false
    @State private var searchText: String = ""

    var filteredProjects: [Project] {
        if searchText.isEmpty {
            return projects
        } else {
            return projects.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.filmStock.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List(selection: $selectedProject) {
                let projects = filteredProjects.filter { $0.isArchived == false }
                Section(header: Text("Projects")) {
                    if projects.isEmpty {
                        Text("No projects.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(projects.sorted(by: { $0.timestamp < $1.timestamp }).enumerated()), id: \.element.id) { localIndex, project in
                            projectRow(project: project, localIndex: localIndex)
                        }
                    }
                }

                let archivedProjects = filteredProjects.filter { $0.isArchived == true  }
                Section(header: Text("Archived projects")) {
                    if archivedProjects.isEmpty {
                        Text("No projects archived.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(archivedProjects.sorted(by: { $0.timestamp < $1.timestamp }).enumerated()), id: \.element.id) { localIndex, project in
                            projectRow(project: project, localIndex: localIndex)
                        }
                    }
                }
            }
            .navigationTitle("Filmlog")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: addProject) {
                        Label("Add project", systemImage: "plus")
                    }

                    NavigationLink(destination: GalleryView()) {
                        Label("Gallery", systemImage: "photo")
                    }

                    Menu {
                        NavigationLink(destination: SettingsView()) {
                            Label("Settings", systemImage: "gear")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .help("More actions")
                }
            }
            .searchable(text: $searchText, prompt: "Search projects")
        }
    }
    
    private func projectRow(project: Project, localIndex: Int) -> some View {
        NavigationLink(destination: {
            ProjectDetailView(project: project, selectedProject: $selectedProject, index: localIndex)
        }) {
            projectLabel(project: project, localIndex: localIndex)
        }
        .listRowBackground(Color.black)
    }
    
    private func projectLabel(project: Project, localIndex: Int) -> some View {
        let displayName: String = {
            if project.name.isEmpty {
                return project.timestamp.formatted(date: .numeric, time: .standard)
            } else {
                return project.name
            }
        }()

        let filmStock = CameraUtils.filmStock(for: project.filmStock)
        let stockInfo = filmStock.speed > 0 ? "\(Int(filmStock.speed)) ISO" : filmStock.name

        let thumbnails = project.shots
            .compactMap { $0.imageData?.thumbnail }
            .suffix(3)

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.footnote)
                    .foregroundStyle(.white)

                Text("Film: \(project.filmStock), \(stockInfo)")
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .trailing) {
                if thumbnails.isEmpty {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 64, height: 64)
                        Image(systemName: "film.fill")
                            .renderingMode(.template)
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.system(size: 28, weight: .regular))
                    }
                } else {
                    ZStack {
                        ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .shadow(radius: 1.5)
                                .rotationEffect(.degrees(randomRotation(for: index)))
                                .offset(randomOffset(for: index))
                                .zIndex(Double(index))
                        }
                    }
                    .frame(width: 70, height: 64)
                    .padding(.trailing, 6)
                }
            }
            .frame(width: 80, height: 64, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }
    
    private func randomRotation(for index: Int) -> Double {
        switch index {
        case 0: return -5
        case 1: return 3
        case 2: return 1
        default: return 0
        }
    }

    private func randomOffset(for index: Int) -> CGSize {
        switch index {
        case 0: return CGSize(width: -8, height: 4)
        case 1: return CGSize(width: -2, height: -3)
        case 2: return CGSize(width: 4, height: 3)
        default: return .zero
        }
    }
    
    private func addProject() {
        withAnimation {
            _ = Project.createDefault(in: modelContext)
        }
    }
}
