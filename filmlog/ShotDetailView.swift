// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
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
        case name, note, elevation, colorTemperature, focusDistance
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
                    onImagePicked: { newData in
                        replaceImage(for: &shot.photoImage, with: newData)
                    }
                )
                
                HStack {
                    Text("Film size")
                    Spacer()
                    Text(shot.filmSize)
                }
                
                Picker("Aspect Ratio", selection: $shot.aspectRatio) {
                    ForEach(CameraOptions.aspectRatios, id: \.label) { item in
                        Text(item.label).tag(item.value)
                    }
                }
                .disabled(shot.isLocked)
                
                TextField("Name", text: $shot.name)
                    .focused($activeField, equals: .name)
                    .disabled(shot.isLocked)
                
                TextField("Note", text: $shot.note, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($activeField, equals: .note)
                    .disabled(shot.isLocked)
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
                    if requestingLocation || shot.elevation == 0 {
                        Text("-")
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 0) {
                            TextField("", value: $shot.elevation, formatter: elevationFormatter)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($activeField, equals: .elevation)
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
                    if requestingLocation || shot.elevation == 0 {
                        Text("-")
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 0) {
                            TextField("", value: $shot.colorTemperature, formatter: colorTemperatureFormatter)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($activeField, equals: .colorTemperature)
                                .disabled(shot.isLocked)
                            Text("K")
                        }
                    }
                }
            }
            
            Section(header: Text("Camera")) {
                Picker("F-Stop", selection: $shot.fstop) {
                    ForEach(CameraOptions.fStops, id: \.label) { item in
                        Text(item.label).tag(item.value)
                    }
                }
                .disabled(shot.isLocked)
                
                Picker("Shutter", selection: $shot.shutter) {
                    ForEach(CameraOptions.shutterSpeeds, id: \.label) { item in
                        Text(item.label).tag(item.value)
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
                Picker("Lens", selection: $shot.lensName) {
                    ForEach(CameraOptions.lensNames, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .disabled(shot.isLocked)
                
                Picker("Focal length", selection: $shot.lensFocalLength) {
                    ForEach(CameraOptions.focalLengths, id: \.label) { item in
                        Text(item.label).tag(item.value)
                    }

                }
                .disabled(shot.isLocked)
                
                HStack {
                    Text("Focus Distance")
                    Spacer()

                    HStack(spacing: 2) {
                        TextField("", value: $shot.focusDistance, formatter: focusDistanceFormatter)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($activeField, equals: .focusDistance)
                            .disabled(shot.isLocked)
                        Text("mm")
                    }
                }
                
                HStack {
                    Text("Depth of field")
                    Spacer()

                    HStack(spacing: 2) {
                        TextField("", value: $shot.focusDepthOfField, formatter: focusDistanceFormatter)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(true)
                        Text("mm")
                        
                        Image(systemName: "function")
                            .foregroundColor(.secondary)
                            .help("This value is automatically calculated and cannot be edited")
                    }
                }
                
                HStack {
                    Text("Near limit")
                    Spacer()

                    HStack(spacing: 2) {
                        TextField("", value: $shot.focusNearLimit, formatter: focusDistanceFormatter)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(true)
                        Text("mm")
                        
                        Image(systemName: "function")
                            .foregroundColor(.secondary)
                            .help("This value is automatically calculated and cannot be edited")
                    }
                }
                
                HStack {
                    Text("Far limit")
                    Spacer()

                    HStack(spacing: 2) {
                        TextField("", value: $shot.focusFarLimit, formatter: focusDistanceFormatter)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(true)
                        Text("mm")
                        
                        Image(systemName: "function")
                            .foregroundColor(.secondary)
                            .help("This value is automatically calculated and cannot be edited")
                    }
                }
                
                HStack {
                    Text("Hyperfocal distance")
                    Spacer()

                    HStack(spacing: 2) {
                        TextField("", value: $shot.focusHyperfocalDistance, formatter: focusDistanceFormatter)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(true)
                        Text("mm")
                        
                        Image(systemName: "function")
                            .foregroundColor(.secondary)
                            .help("This value is automatically calculated and cannot be edited")
                    }
                }
            }
            
            Section(header: Text("Lightmeter")) {
                PhotoSectionView(
                    data: shot.lightMeterImage?.data,
                    label: "Add photo",
                    isLocked: shot.isLocked
                ) { newData in
                    replaceImage(for: &shot.lightMeterImage, with: newData)
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
                        createNextShot(count: 1)
                        dismiss()
                    }
                    Button("Add 2 shots") {
                        createNextShot(count: 2)
                        dismiss()
                    }
                    Button("Add 5 shots") {
                        createNextShot(count: 5)
                        dismiss()
                    }
                    Button("Add 10 shots") {
                        createNextShot(count: 10)
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
                shot.elevation = 0
                shot.colorTemperature = 0
            }
            updateDof()
        }
        .onChange(of: shot.focusDistance) { _, _ in updateDof() }
        .onChange(of: shot.fstop) { _, _ in updateDof() }
        .onChange(of: shot.lensFocalLength) { _, _ in updateDof() }
        .onReceive(locationManager.$currentLocation) { location in
            if requestingLocation, let location = location {
                shot.location = LocationOptions.Location(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    altitude: location.altitude
                )
                shot.elevation = shot.location?.elevation(for: Date()) ?? 0
                shot.colorTemperature = shot.location?.colorTemperature(for: Date()) ?? 0
                requestingLocation = false
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
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
                    cleanupImage(shot.photoImage)
                    cleanupImage(shot.lightMeterImage)
                    modelContext.delete(shot)
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

    private func createNextShot(count: Int) {
        for _ in 0..<count {
            let newShot = shot.copy()
            newShot.roll = roll
            modelContext.insert(newShot)
            roll.shots.append(newShot)
        }
    }
    
    private func openInMaps(latitude: Double, longitude: Double) {
        if let url = URL(string: "http://maps.apple.com/?ll=\(latitude),\(longitude)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func updateDof() {
        guard shot.focusDistance > 0 else {
            shot.focusDepthOfField = 0
            return
        }
        
        guard let filmSize = CameraOptions.filmSizes.first(where: { $0.label == shot.filmSize })?.value,
              let aperture = CameraOptions.fStops.first(where: { $0.label == shot.fstop })?.value,
              let focalLength = CameraOptions.focalLengths.first(where: { $0.label == shot.lensFocalLength })?.value else {
            shot.focusDepthOfField = 0
            return
        }
        
        let result = filmSize.focusDepthOfField(
            focalLength: focalLength,
            aperture: aperture,
            focusDistance: shot.focusDistance
        )
        
        shot.focusDepthOfField = result.dof.isInfinite ? -1.0 : result.dof
        shot.focusNearLimit = result.near
        shot.focusFarLimit = result.far
        shot.focusHyperfocalDistance = result.hyperfocal
    }
    
    private func replaceImage(for imageRef: inout ImageData?, with newData: Data) {
        if let oldImage = imageRef, oldImage.decrementReference() {
            modelContext.delete(oldImage)
        }
        imageRef = ImageData(data: newData)
    }
    
    private func cleanupImage(_ image: ImageData?) {
        if let img = image, img.decrementReference() {
            modelContext.delete(img)
        }
    }

    private var elevationFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        formatter.negativePrefix = ""
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
        return formatter
    }

    @ViewBuilder
    private func evPicker(title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("EV na").tag("-")
            ForEach(-6...6, id: \.self) { value in
                Text("EV\(value >= 0 ? "+\(value)" : "\(value)")").tag("\(value)")
            }
        }
        .disabled(shot.isLocked)
    }
}
