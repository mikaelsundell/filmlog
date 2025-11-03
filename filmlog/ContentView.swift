// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var projects: [Project]
    @State private var selectedProject: Project? = nil
    
    @State private var projectToDelete: Project?
    @State private var showDeleteAlert = false
    @State private var searchText: String = ""

    enum SortOption: String, CaseIterable, Identifiable {
        case name = "Name"
        case created = "Created"
        case lastModified = "Last modified"
        var id: String { rawValue }
    }
    
    @AppStorage("selectedSortOptionActive") private var selectedSortActiveRawValue: String = SortOption.lastModified.rawValue
    @AppStorage("selectedSortOptionArchived") private var selectedSortArchivedRawValue: String = SortOption.lastModified.rawValue

    private var selectedSortActive: SortOption {
        get { SortOption(rawValue: selectedSortActiveRawValue) ?? .lastModified }
        set { selectedSortActiveRawValue = newValue.rawValue }
    }

    private var selectedSortArchived: SortOption {
        get { SortOption(rawValue: selectedSortArchivedRawValue) ?? .lastModified }
        set { selectedSortArchivedRawValue = newValue.rawValue }
    }

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
    
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List(selection: $selectedProject) {
                let activeProjects = filteredProjects.filter { !$0.isArchived }
                Section(header: projectSectionHeader(title: "Projects", sortOption: $selectedSortActiveRawValue)) {
                    if activeProjects.isEmpty {
                        Text("No projects.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(sortedProjects(activeProjects, option: selectedSortActive).enumerated()), id: \.element.id) { localIndex, project in
                            projectRow(project: project, localIndex: localIndex)
                        }
                    }
                }
                let archivedProjects = filteredProjects.filter { $0.isArchived }
                Section(header: projectSectionHeader(title: "Archived projects", sortOption: $selectedSortArchivedRawValue)) {
                    if archivedProjects.isEmpty {
                        Text("No projects archived.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(sortedProjects(archivedProjects, option: selectedSortArchived).enumerated()), id: \.element.id) { localIndex, project in
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
                    .help("Settings")
                }
            }
            .searchable(text: $searchText, prompt: "Search projects")
        }
    }

    private func sortedProjects(_ projects: [Project], option: SortOption) -> [Project] {
        switch option {
        case .name:
            return projects.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        case .created:
            return projects.sorted {
                $0.created > $1.created
            }

        case .lastModified:
            return projects.sorted {
                $0.lastModified > $1.lastModified
            }
        }
    }

    private func icon(for option: SortOption) -> String {
        switch option {
        case .name: return "textformat"
        case .created: return "calendar"
        case .lastModified: return "clock"
        }
    }

    @ViewBuilder
    private func projectSectionHeader(title: String, sortOption: Binding<String>) -> some View {
        HStack {
            Menu {
                Picker("Sort by", selection: sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Label(option.rawValue, systemImage: icon(for: option))
                            .tag(option.rawValue)
                    }
                }
                .textCase(nil)
            } label: {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .offset(y: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .menuStyle(.button)
            .help("Sort projects")

            Spacer()
        }
        .padding(.bottom, 2)
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
        let modifiedText = "Last modified: \(project.lastModified.formatted(date: .abbreviated, time: .shortened))"
        let thumbnails = latestThumbnails(from: project)

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.footnote)
                    .foregroundStyle(.white)

                Text(modifiedText)
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
                            .frame(width: 64, height: 64)
                    }
                    .frame(width: 70, height: 64)
                    .padding(.trailing, 6)
                } else {
                    ZStack {
                        ForEach(Array(thumbnails.reversed().enumerated()), id: \.offset) { index, image in
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

    private func latestThumbnails(from project: Project, limit: Int = 3) -> [UIImage] {
        var images: [UIImage] = []
        for shot in project.shots.sorted(by: { $0.timestamp > $1.timestamp }) {
            if let thumb = shot.imageData?.thumbnail {
                images.append(thumb)
                if images.count == limit { break }
            }
        }
        if images.count < limit {
            let missing = limit - images.count
            let blackCard = UIImage.solidColor(.black, size: CGSize(width: 50, height: 50))
            images.append(contentsOf: Array(repeating: blackCard, count: missing))
        }
        return images
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



