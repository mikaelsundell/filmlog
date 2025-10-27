// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @State private var newShotToShow: Shot?
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
    var project: Project
    var index: Int
    var count: Int
    var onAdd: ((Int) -> Void)?
    var onDelete: (() -> Void)?
    var onSelect: ((Int) -> Void)?
    var onBack: (() -> Void)?
    
    @Environment(\.modelContext) private var modelContext

    enum ActiveField {
        case name, note, locationElevation, locationColorTemperature, focusDistance
    }
    @FocusState private var activeField: ActiveField?
    @State private var showDeleteAlert = false
    @State private var showDialog = false
    @State private var requestingLocation = false
    @StateObject private var locationManager = LocationManager()
    
    var body: some View {
        VStack(spacing: 0) {
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
                .frame(width: 80, alignment: .leading)
                
                Spacer()
                
                Text(shot.name)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
                
                HStack(spacing: 8) {
                    Button {
                        if index > 0 { onSelect?(index - 1) }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 24, weight: .regular))
                    }
                    .disabled(index == 0)
                    .buttonStyle(.borderless)

                    Button {
                        if index < count - 1 { onSelect?(index + 1) }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 24, weight: .regular))
                    }
                    .disabled(index == count - 1)
                    .buttonStyle(.borderless)
                    
                    Menu {
                        Button {
                            shot.isLocked.toggle()
                            try? modelContext.save()
                        } label: {
                            Label(
                                shot.isLocked ? "Unlock Shot" : "Lock Shot",
                                systemImage: shot.isLocked ? "lock.open" : "lock.fill"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 22, weight: .regular))
                    }
                }
                .padding(.trailing, 16)
                .frame(width: 80, alignment: .trailing)
            }
            .background(Color.black)
            .shadow(radius: 2)
            
            Form {
                Section(header: Text("Camera")) {
                    ShotSectionView(
                            shot: shot,
                            isLocked: shot.isLocked
                        ) { newUIImage in
                            var metadata: [String: DataValue] = [:]
                            metadata["name"] = .string(shot.name)
                            metadata["timestamp"] = .double(shot.timestamp.timeIntervalSince1970)
                            metadata["camera"] = .string(project.camera)
                            metadata["note"] = .string(shot.note)
                            metadata["filmStock"] = .string(shot.filmStock)
                            metadata["filmSize"] = .string(shot.filmSize)
                            metadata["aspectRatio"] = .string(shot.aspectRatio)
                            metadata["aperture"] = .string(shot.aperture)
                            metadata["shutter"] = .string(shot.shutter)
                            metadata["exposureCompensation"] = .string(shot.exposureCompensation)
                            metadata["lens"] = .string(shot.lens)
                            metadata["focalLength"] = .string(shot.focalLength)
                            metadata["colorFilter"] = .string(shot.colorFilter)
                            metadata["ndFilter"] = .string(shot.ndFilter)
                            metadata["exposureSky"] = .string(shot.exposureSky)
                            metadata["exposureFoliage"] = .string(shot.exposureFoliage)
                            metadata["exposureHighlights"] = .string(shot.exposureHighlights)
                            metadata["exposureMidGray"] = .string(shot.exposureMidGray)
                            metadata["exposureShadows"] = .string(shot.exposureShadows)
                            metadata["exposureSkinKey"] = .string(shot.exposureSkinKey)
                            metadata["exposureSkinFill"] = .string(shot.exposureSkinFill)
                            metadata["focusDistance"] = .double(shot.focusDistance)
                            metadata["focusDepthOfField"] = .double(shot.focusDepthOfField)
                            metadata["focusNearLimit"] = .double(shot.focusNearLimit)
                            metadata["focusFarLimit"] = .double(shot.focusFarLimit)
                            metadata["focusHyperfocalDistance"] = .double(shot.focusHyperfocalDistance)
                            metadata["focusHyperfocalNearLimit"] = .double(shot.focusHyperfocalNearLimit)
                            if let loc = shot.location {
                                metadata["latitude"] = .double(loc.latitude)
                                metadata["longitude"] = .double(loc.longitude)
                                if let alt = loc.altitude { metadata["altitude"] = .double(alt) }
                            }
                            metadata["locationElevation"] = .double(shot.locationElevation ?? 0.0)
                            metadata["locationColorTemperature"] = .double(Double(shot.locationColorTemperature ?? 0))
                            metadata["locationTimestamp"] = .double(shot.locationTimestamp?.timeIntervalSince1970 ?? 0.0)
                            metadata["deviceRoll"] = .double(shot.deviceRoll)
                            metadata["deviceTilt"] = .double(shot.deviceTilt)
                            metadata["deviceLens"] = .string(shot.deviceLens)

                            let newImage = ImageData(metadata: metadata)
                            if newImage.updateFile(to: newUIImage) {
                                shot.updateImage(to: newImage, context: modelContext)
                            }
                        }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                Section(
                    header: HStack {
                        Text("Shot")
                        if shot.isLocked {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .padding(.leading, 4)
                        }
                    }
                ) {
                    HStack {
                        TextField("Name", text: $shot.name)
                            .focused($activeField, equals: .name)
                            .submitLabel(.done)
                            .disabled(shot.isLocked)
                        if !shot.name.isEmpty && !shot.isLocked {
                            Button {
                                shot.name = ""
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    activeField = .name
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
                        Text(shot.timestamp.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                    
                    Picker("Film size", selection: $shot.filmSize) {
                        ForEach(CameraUtils.groupedFilmSizes.keys.sorted(), id: \.self) { category in
                            Section(header: Text(category)) {
                                ForEach(CameraUtils.groupedFilmSizes[category] ?? [], id: \.name) { size in
                                    Text(size.name).tag(size.name)
                                }
                            }
                        }
                    }
                    .disabled(shot.isLocked)
                    
                    Picker("Film stock", selection: $shot.filmStock) {
                        ForEach(CameraUtils.groupedFilmStocks.keys.sorted(), id: \.self) { category in
                            Section(header: Text(category)) {
                                ForEach(CameraUtils.groupedFilmStocks[category] ?? [], id: \.name) { stock in
                                    Text(stock.name).tag(stock.name)
                                }
                            }
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
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        Spacer()
                                        Button("Done") {
                                            activeField = nil
                                        }
                                    }
                                }
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
                
                Section(
                    header: HStack {
                        Text("Note")
                        if shot.isLocked {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .padding(.leading, 4)
                        }
                    }
                ) {
                    TextEditor(text: $shot.note)
                        .frame(height: 64)
                        .focused($activeField, equals: .note)
                        .disabled(shot.isLocked)
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
            .alert("Are you sure?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    withAnimation {
                        modelContext.safelyDelete(shot)
                        onDelete?()
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
            
            if activeField == nil {
                
                HStack {
                    Button {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    .help("Delete project")
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Image(systemName: "film")
                            .font(.system(size: 14, weight: .medium))
                        Text("Shot \(index + 1) of \(count)")
                            .font(.subheadline)
                            .fontWeight(.regular)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .foregroundColor(.blue)
                    .shadow(radius: 1)
                    
                    Spacer()
                    
                    Button {
                        showDialog = true
                    } label: {
                        Image(systemName: "film.stack")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    .help("Add new shot(s)")
                    .confirmationDialog("Choose an option", isPresented: $showDialog) {
                        Button("Copy shot") { copyShot(count: 1) }
                        Button("Copy to 2 shots") { copyShot(count: 2) }
                        Button("Copy to 5 shots") { copyShot(count: 5) }
                        Button("Copy to 10 shots") { copyShot(count: 10) }
                        Button("Cancel", role: .cancel) {}
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.black)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationBarBackButtonHidden(false)
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

    private func copyShot(count: Int) {
        let originalName = shot.name.isEmpty ? "Shot" : shot.name
        let baseName = "Copy of \(originalName)"
        
        let existingCount = project.shots.count
        var existingNames = Set(project.shots.map { $0.name })

        for i in 0..<count {
            var name = baseName
            var suffix = 1
            
            // Ensure unique name within this session
            while existingNames.contains(name) {
                name = "\(baseName) \(suffix)"
                suffix += 1
            }

            do {
                let newShot = shot.copy(context: modelContext)
                newShot.name = name
                newShot.deleteImage(context: modelContext)

                modelContext.insert(newShot)
                try modelContext.save()

                project.timestamp = Date()
                project.shots.append(newShot)
                try modelContext.save()

                existingNames.insert(name)

                if i == 0 {
                    onSelect?(existingCount)
                }
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
                Text("EV\(value >= 0 ? "+\(value)" : "\(value)")")
                    .tag("\(value)")
            }
        }
        .disabled(shot.isLocked)
    }
}
