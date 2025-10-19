// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var currentLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.first
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("failed to get location: \(error.localizedDescription)")
    }
}

struct ShotDetailView: View {
    @Bindable var shot: Shot
    var roll: Roll
    var index: Int
    var count: Int
    var onDelete: (() -> Void)?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode

    enum ActiveField {
        case name, note, locationElevation, locationColorTemperature, focusDistance
    }
    @FocusState private var activeField: ActiveField?
    @State private var showDeleteAlert = false
    @State private var showDialog = false
    @State private var requestingLocation = false
    @StateObject private var locationManager = LocationManager()
    
    var body: some View {
        Form {
            Section(header: Text("Shot")) {
                ShotSectionView(
                    shot: shot,
                    isLocked: shot.isLocked,
                    onImagePicked: { newUIImage in
                        let newImage = ImageData()
                        if newImage.updateFile(to: newUIImage) {
                            shot.updateImage(to: newImage, context: modelContext)
                        }
                    }
                )
                
                HStack {
                    Text("Film size")
                    Spacer()
                    Text(shot.filmSize)
                }
                
                Picker("Aspect Ratio", selection: $shot.aspectRatio) {
                    ForEach(CameraUtils.aspectRatios, id: \.name) { ratio in
                        Text(ratio.name).tag(ratio.name)
                    }
                }
                .disabled(shot.isLocked)
                
                TextField("Name", text: $shot.name)
                    .focused($activeField, equals: .name)
                    .disabled(shot.isLocked)
                
                TextEditor(text: $shot.note)
                    .frame(height: 100)
                    .disabled(shot.isLocked)
                    .focused($activeField, equals: .note)
                    .offset(x: -4)
            }
            
            Section(header: Text("Location")) {
                if requestingLocation {
                    Text("Waiting for location...")
                        .foregroundColor(.secondary)
                } else if let loc = shot.location {
                    HStack {
                        Text("Lat: \(loc.latitude), Lon: \(loc.longitude)")
                        Spacer()
                        Button(action: {
                            openInMaps(latitude: loc.latitude, longitude: loc.longitude)
                        }) {
                            Image(systemName: "map")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("No location set")
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    requestingLocation = true
                    locationManager.requestLocation()
                }) {
                    Label("Request location", systemImage: "location.fill")
                }
                .disabled(shot.isLocked || requestingLocation)

                HStack {
                    Text("Elevation")
                    Spacer()
                    if requestingLocation || shot.locationElevation == 0 {
                        Text("-")
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 0) {
                            TextField("", value: $shot.locationElevation, formatter: elevationFormatter)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($activeField, equals: .locationElevation)
                                .disabled(true)
                            
                            HStack(spacing: 2) {
                                Text("°")
                                Image(systemName: "function")
                                    .foregroundColor(.secondary)
                                    .help("This value is automatically calculated and cannot be edited")
                            }
                        }
                    }
                }
                
                HStack {
                    Text("Color temperature")
                    Spacer()
                    if requestingLocation || shot.locationElevation == 0 {
                        Text("-")
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 0) {
                            TextField("", value: $shot.locationColorTemperature, formatter: colorTemperatureFormatter)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($activeField, equals: .locationColorTemperature)
                                .disabled(shot.isLocked)
                            Text("K")
                        }
                    }
                }
            }
            
            Section(header: Text("Camera")) {
                Picker("Aperture", selection: $shot.aperture) {
                    ForEach(CameraUtils.apertures, id: \.name) { aperture in
                        Text(aperture.name).tag(aperture.name)
                    }
                }
                .disabled(shot.isLocked)
                
                Picker("Shutter", selection: $shot.shutter) {
                    ForEach(CameraUtils.shutters, id: \.name) { shutter in
                        Text(shutter.name).tag(shutter.name)
                    }
                }
                .disabled(shot.isLocked)
                
                Picker("Compensation", selection: $shot.exposureCompensation) {
                    ForEach(["-3", "-2", "-1", "0", "+1", "+2", "+3"], id: \.self) { value in
                        Text("EV\(value)").tag(value)
                    }
                }
                .disabled(shot.isLocked)
            }
            
            Section(header: Text("Lens")) {
                Picker("Lens", selection: $shot.lens) {
                    ForEach(CameraUtils.lenses, id: \.name) { lens in
                        Text(lens.name).tag(lens.name)
                    }
                }
                .disabled(shot.isLocked)
                
                Picker("Lens color filter", selection: $shot.colorFilter) {
                    ForEach(CameraUtils.colorFilters, id: \.name) { filter in
                        Text(filter.name).tag(filter.name)
                    }
                }
                .disabled(shot.isLocked)
                
                Picker("Lens ND filter", selection: $shot.ndFilter) {
                    ForEach(CameraUtils.ndFilters, id: \.name) { filter in
                        Text(filter.name).tag(filter.name)
                    }
                }
                .disabled(shot.isLocked)
                
                Picker("Focal length", selection: $shot.focalLength) {
                    ForEach(CameraUtils.focalLengths, id: \.name) { focal in
                        Text(focal.name).tag(focal.name)
                    }
                }
                .disabled(shot.isLocked)
            }
            
            Section(header: Text("Focus")) {
                HStack {
                    Text("Focus distance")
                    Spacer()
                    HStack(spacing: 2) {
                        TextField("", value: $shot.focusDistance, formatter: focusDistanceFormatter)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($activeField, equals: .focusDistance)
                            .disabled(shot.isLocked)
                        Text("mm").frame(width: 32, alignment: .trailing)
                    }
                    Text("\(shot.focusDistance / 1000, specifier: "%.1f") m")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }

                focusRow(label: "Depth of field", value: shot.focusDepthOfField)
                focusRow(label: "Near", value: shot.focusNearLimit)
                focusRow(label: "Far", value: shot.focusFarLimit)

                HStack {
                    Image(systemName: "function")
                        .foregroundColor(.secondary)
                        .help("This value is automatically calculated and cannot be edited")

                    Button {
                        shot.focusDistance = shot.focusHyperfocalDistance
                    } label: {
                        Image(systemName: "scope")
                            .foregroundColor(.blue)
                            .help("Set focus distance to hyperfocal value")
                    }
                    .buttonStyle(.borderless)

                    Text("Hyperfocal")
                    Spacer()

                    HStack(spacing: 2) {
                        Text(shot.focusHyperfocalDistance > 1_000_000
                             ? "∞"
                             : (focusDistanceFormatter.string(from: NSNumber(value: shot.focusHyperfocalDistance)) ?? "0"))
                        Text("mm").frame(width: 32, alignment: .trailing)
                    }
                    
                    Text(shot.focusHyperfocalDistance > 1_000_000
                         ? "∞"
                         : String(format: "%.1f m", shot.focusHyperfocalDistance / 1000))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }

                focusRow(label: "Near", value: shot.focusHyperfocalNearLimit)
            }
            
            Section(header: Text("Lightmeter")) {
                PhotoPickerView(
                    image: shot.lightMeterImageData?.thumbnail,
                    label: "Add photo",
                    isLocked: shot.isLocked
                ) { newUIImage in
                    let newImage = ImageData()
                    if newImage.updateFile(to: newUIImage) {
                        shot.updateLightMeterImage(to: newImage, context: modelContext)
                    }
                }
                evPicker(title: "Sky", selection: $shot.exposureSky)
                evPicker(title: "Foliage", selection: $shot.exposureFoliage)
                evPicker(title: "Highlights", selection: $shot.exposureHighlights)
                evPicker(title: "Mid gray", selection: $shot.exposureMidGray)
                evPicker(title: "Shadows", selection: $shot.exposureShadows)
                evPicker(title: "Skin key", selection: $shot.exposureSkinKey)
                evPicker(title: "Skin fill", selection: $shot.exposureSkinFill)
            }
            
            Section {
                Button(action: {
                    showDialog = true
                }) {
                    Label("Next shot", systemImage: "film")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .listRowBackground(Color.clear)
                .confirmationDialog("Choose an option", isPresented: $showDialog) {
                    Button("Add one shot") {
                        addNextShot(count: 1)
                        dismiss()
                    }
                    Button("Copy to next shot") {
                        copyNextShot(count: 1)
                        dismiss()
                    }
                    Button("Copy to 2 shots") {
                        copyNextShot(count: 2)
                        dismiss()
                    }
                    Button("Copy to 5 shots") {
                        copyNextShot(count: 5)
                        dismiss()
                    }
                    Button("Copy to 10 shots") {
                        copyNextShot(count: 10)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .navigationTitle("Shot \(index + 1) of \(count)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            locationManager.currentLocation = nil
            if shot.location == nil {
                shot.locationTimestamp = Date()
                shot.locationColorTemperature = 0
                shot.locationElevation = 0
            }
            updateDof()
        }
        .onChange(of: shot.focusDistance) { _, _ in updateDof() }
        .onChange(of: shot.aperture) { _, _ in updateDof() }
        .onChange(of: shot.focalLength) { _, _ in updateDof() }
        .onReceive(locationManager.$currentLocation) { location in
            if requestingLocation, let location = location {
                shot.location = LocationUtils.Location(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    altitude: location.altitude
                )
                shot.locationColorTemperature = shot.location?.colorTemperature(for: Date()) ?? 0
                shot.locationElevation = shot.location?.elevation(for: Date()) ?? 0
                requestingLocation = false
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                
                Button(action: {
                    showDialog = true
                }) {
                    Label("Add shot", systemImage: "plus")
                }
                .listRowBackground(Color.clear)
                .confirmationDialog("Choose an option", isPresented: $showDialog) {
                    Button("Add one shot") {
                        addNextShot(count: 1)
                        dismiss()
                    }
                    Button("Copy to next shot") {
                        copyNextShot(count: 1)
                        dismiss()
                    }
                    Button("Copy to 2 shots") {
                        copyNextShot(count: 2)
                        dismiss()
                    }
                    Button("Copy to 5 shots") {
                        copyNextShot(count: 5)
                        dismiss()
                    }
                    Button("Copy to 10 shots") {
                        copyNextShot(count: 10)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                }
                
                Button(action: { shot.isLocked.toggle() }) {
                    Image(systemName: shot.isLocked ? "lock.fill" : "lock.open")
                }
                .help(shot.isLocked ? "Unlock to edit shot info" : "Lock to prevent editing")
                
                if count > 1 {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete this shot")
                }

                Menu {
                    Button {
                        generatePDF()
                    } label: {
                        Label("Export as PDF", systemImage: "doc.richtext")
                    }

                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("More actions")
            }
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Done") {
                        activeField = nil
                    }
                }
            }
        }
        .alert("Are you sure?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                withAnimation {
                    modelContext.safelyDelete(shot)
                    onDelete?()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if index == count - 1 {
                Text("This shot contains associated data. Are you sure you want to delete it?")
            } else {
                Text("Deleting this shot will change the shot order. Are you sure you want to proceed?")
            }
        }
    }
    
    @ViewBuilder
    private func focusRow(label: String, value: Double) -> some View {
        HStack {
            Image(systemName: "function")
                .foregroundColor(.secondary)
                .help("This value is automatically calculated and cannot be edited")

            Text(label)
            Spacer()

            HStack(spacing: 2) {
                Text(value > CameraUtils.FilmSize.defaultInfinity
                     ? "∞"
                     : (focusDistanceFormatter.string(from: NSNumber(value: value)) ?? "0"))

                if value <= CameraUtils.FilmSize.defaultInfinity {
                    Text("mm")
                        .frame(width: 32, alignment: .trailing)
                }
            }

            Text(value > CameraUtils.FilmSize.defaultInfinity
                 ? "∞"
                 : String(format: "%.1f m", value / 1000))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }
    
    private func addNextShot(count: Int) {
        let baseName = "Untitled"
        let names = Set(roll.shots.map { $0.name })
        
        for _ in 0..<count {
            var name = baseName
            var suffix = 1
            while names.contains(name) {
                name = "\(baseName) \(suffix)"
                suffix += 1
            }
            do {
                let newShot = Shot()
                newShot.name = name
                newShot.filmSize = roll.filmSize
                newShot.filmStock = roll.filmStock

                modelContext.insert(newShot)
                try modelContext.save()

                roll.shots.append(newShot)
                try modelContext.save()
                
            } catch {
                print("failed to save shot: \(error)")
            }
        }
    }

    private func copyNextShot(count: Int) {
        let baseName = shot.name.isEmpty ? "Copy" : shot.name
        let names = Set(roll.shots.map { $0.name })

        for _ in 0..<count {
            var name = baseName
            var suffix = 1
            while names.contains(name) {
                name = "\(baseName) \(suffix)"
                suffix += 1
            }
            do {
                let newShot = shot.copy(context: modelContext)
                newShot.name = name

                modelContext.insert(newShot)
                try modelContext.save()

                roll.shots.append(newShot)
                try modelContext.save()
                
            } catch {
                print("failed to save shot: \(error)")
            }
        }
    }
    
    private func openInMaps(latitude: Double, longitude: Double) {
        if let url = URL(string: "http://maps.apple.com/?ll=\(latitude),\(longitude)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func updateDof() {
        let focusDistance = shot.focusDistance
        guard focusDistance > 0 else {
            shot.focusDepthOfField = 0
            return
        }
        
        let filmSize = CameraUtils.filmSize(for: shot.filmSize)
        let aperture = CameraUtils.aperture(for: shot.aperture)
        let focalLength = CameraUtils.focalLength(for: shot.focalLength)
        guard !filmSize.isNone, !aperture.isNone, !focalLength.isNone else {
            shot.focusDepthOfField = 0
            return
        }

        let result = filmSize.focusDepthOfField(
            focalLength: focalLength.length,
            aperture: aperture.fstop,
            focusDistance: focusDistance
        )
    
        shot.focusDepthOfField = result.dof.isInfinite ? -1.0 : result.dof
        shot.focusNearLimit = result.near
        shot.focusFarLimit = result.far
        shot.focusHyperfocalDistance = result.hyperfocal
        shot.focusHyperfocalNearLimit = result.hyperfocalNear
    }
    
    private func generatePDF() {
        
    }

    private var elevationFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        formatter.negativePrefix = "-"
        return formatter
    }
    
    private var colorTemperatureFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }
    
    private var focusDistanceFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.generatesDecimalNumbers = false
        formatter.isLenient = true
        return formatter
    }

    @ViewBuilder
    private func evPicker(title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("-").tag("-")
            ForEach(-6...6, id: \.self) { value in
                Text("EV\(value >= 0 ? "+\(value)" : "\(value)")").tag("\(value)")
            }
        }
        .disabled(shot.isLocked)
    }
}
