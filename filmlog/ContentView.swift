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
    }

    private func projectLabel(project: Project, localIndex: Int) -> some View {
        let displayName: String = {
            if project.name.isEmpty {
                return project.timestamp.formatted(date: .numeric, time: .standard)
            } else {
                return project.name
            }
        }()

        let thumbnails = project.shots
            .compactMap { $0.imageData?.thumbnail }
            .suffix(3)
            .reversed()

        let shotCount = project.shots.count

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(displayName) (\(shotCount))")
                    .font(.footnote)
                    .lineLimit(1)
            }

            Spacer()

            ZStack(alignment: .trailing) {
                if thumbnails.isEmpty {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "film.fill")
                            .renderingMode(.template)
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.system(size: 16, weight: .regular))
                    }
                    .frame(width: 32, height: 32)
                } else if thumbnails.count == 1, let image = thumbnails.first {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.black.opacity(0.7), lineWidth: 0.5)
                        )
                        .frame(width: 48, alignment: .trailing)
                } else {
                    HStack(spacing: -12) {
                        ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.black.opacity(0.7), lineWidth: 0.5)
                                )
                                .shadow(radius: 1)
                        }
                    }
                    .frame(width: 64, alignment: .trailing)
                }
            }
            .frame(width: 64, height: 32, alignment: .trailing)
        }
    }

    private func addProject() {
        withAnimation {
            _ = Project.createDefault(in: modelContext)
        }
    }
}
