// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var rolls: [Roll]
    @State private var selectedRoll: Roll? = nil
    
    @State private var rollToDelete: Roll?
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            List(selection: $selectedRoll) {
                let newRolls = rolls.filter { $0.status == "new" }
                Section(header: Text("New rolls")) {
                    if newRolls.isEmpty {
                        Text("No new rolls.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(newRolls.sorted(by: { $0.timestamp < $1.timestamp }).enumerated()), id: \.element.id) { localIndex, roll in
                            NavigationLink(destination: {
                                RollDetailView(roll: roll, selectedRoll: $selectedRoll, index: localIndex)
                            }) {
                                Label {
                                    Text("\(localIndex + 1).) \(roll.name.isEmpty ? roll.timestamp.formatted(date: .numeric, time: .standard) : roll.name) (\(roll.daysAgoText))")
                                        .font(.footnote)
                                } icon: {
                                    Image(systemName: "film.fill")
                                }
                            }
                        }
                    }
                }
                let shootingRolls = rolls.filter { $0.status == "shooting" }
                Section(header: Text("Shooting rolls")) {
                    if shootingRolls.isEmpty {
                        Text("No rolls currently shooting.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(shootingRolls.sorted(by: { $0.timestamp < $1.timestamp }).enumerated()), id: \.element.id) { localIndex, roll in
                            NavigationLink(destination: {
                                RollDetailView(roll: roll, selectedRoll: $selectedRoll, index: localIndex)
                            }) {
                                Label {
                                    Text("\(localIndex + 1).) \(roll.name.isEmpty ? roll.timestamp.formatted(date: .numeric, time: .standard) : roll.name) (\(roll.daysAgoText))")
                                        .font(.footnote)
                                } icon: {
                                    Image(systemName: "film.fill")
                                }
                            }
                        }
                    }
                }
                let processingRolls = rolls.filter { $0.status == "processing" }
                Section(header: Text("For processing rolls")) {
                    if processingRolls.isEmpty {
                        Text("No rolls waiting for processing.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(processingRolls.sorted(by: { $0.timestamp < $1.timestamp }).enumerated()), id: \.element.id) { localIndex, roll in
                            NavigationLink(destination: {
                                RollDetailView(roll: roll, selectedRoll: $selectedRoll, index: localIndex)
                            }) {
                                Label {
                                    Text("\(localIndex + 1).) \(roll.name.isEmpty ? roll.timestamp.formatted(date: .numeric, time: .standard) : roll.name) (\(roll.daysAgoText))")
                                        .font(.footnote)
                                } icon: {
                                    Image(systemName: "film.fill")
                                }
                            }
                        }
                    }
                }

                let finishedRolls = rolls.filter { $0.status == "finished" }
                Section(header: Text("Finished rolls")) {
                    if finishedRolls.isEmpty {
                        Text("No rolls finished.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(finishedRolls.sorted(by: { $0.timestamp < $1.timestamp }).enumerated()), id: \.element.id) { localIndex, roll in
                            NavigationLink(value: roll) {
                                Label {
                                    Text("\(localIndex + 1).) \(roll.name.isEmpty ? roll.timestamp.formatted(date: .numeric, time: .standard) : roll.name), Film: \(roll.filmStock) (\(roll.shots.count))")
                                        .font(.footnote)
                                } icon: {
                                    Image(systemName: "film.fill")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filmlog")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: addRoll) {
                        Label("Add roll", systemImage: "plus")
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
        }
    }

    private func addRoll() {
        withAnimation {
            let baseName = "Untitled"
            var name = baseName
            var index = 1
            let names = Set(rolls.map { $0.name })
            while names.contains(name) {
                name = "\(baseName) \(index)"
                index += 1
            }
            let newRoll = Roll(name: name)
            modelContext.insert(newRoll)
        }
    }
}

extension Roll {
    var daysAgoText: String {
        let calendar = Calendar.current
        let now = Date()
        if let days = calendar.dateComponents([.day], from: timestamp, to: now).day {
            return "\(days) day\(days == 1 ? "" : "s")"
        }
        return "Unknown"
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Roll.self, inMemory: true)
}
