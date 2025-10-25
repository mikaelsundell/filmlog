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
                let newProjects = filteredProjects.filter { $0.status == "new" }
                Section(header: Text("New projects")) {
                    if newProjects.isEmpty {
                        Text("No new projects.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(newProjects.sorted(by: { $0.timestamp < $1.timestamp }).enumerated()), id: \.element.id) { localIndex, project in
                            projectRow(project: project, localIndex: localIndex)
                        }
                    }
                }
                
                let shootingProjects = filteredProjects.filter { $0.status == "shooting" }
                Section(header: Text("Shooting projects")) {
                    if shootingProjects.isEmpty {
                        Text("No projects currently shooting.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(shootingProjects.sorted(by: { $0.timestamp < $1.timestamp }).enumerated()), id: \.element.id) { localIndex, project in
                            projectRow(project: project, localIndex: localIndex)
                        }
                    }
                }

                let finishedProjects = filteredProjects.filter { $0.status == "finished" }
                Section(header: Text("Finished projects")) {
                    if finishedProjects.isEmpty {
                        Text("No projects finished.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(finishedProjects.sorted(by: { $0.timestamp < $1.timestamp }).enumerated()), id: \.element.id) { localIndex, project in
                            NavigationLink(value: project) {
                                projectLabel(project: project, localIndex: localIndex)
                            }
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

        let firstShotThumbnail = project.shots.first(where: { $0.imageData?.thumbnail != nil })?.imageData?.thumbnail
        let shotCount = project.shots.count

        return Label {
            Text("\(displayName) (\(shotCount))")
                .font(.footnote)
        } icon: {
            if let thumbnail = firstShotThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                Image(systemName: "film.fill")
            }
        }
    }

    private func addProject() {
        withAnimation {
            let baseName = "Untitled"
            var name = baseName
            var index = 1
            let names = Set(projects.map { $0.name })
            while names.contains(name) {
                name = "\(baseName) \(index)"
                index += 1
            }
            let newProject = Project(name: name)
            modelContext.insert(newProject)
        }
    }
}
