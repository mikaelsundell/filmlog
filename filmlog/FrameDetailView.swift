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

struct FrameDetailView: View {
    @Bindable var frame: Frame
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
            Section(header: Text("Frame")) {
                FrameSectionView(
                    frame: frame,
                    isLocked: frame.isLocked,
                    onImagePicked: { newData in
                        replaceImage(for: &frame.photoImage, with: newData)
                    }
                )
                
                HStack {
                    Text("Film size")
                    Spacer()
                    Text(frame.filmSize)
                }
                
                Picker("Aspect Ratio", selection: $frame.aspectRatio) {
                    ForEach(CameraOptions.aspectRatios, id: \.label) { item in
                        Text(item.label).tag(item.value)
                    }
                }
                .disabled(frame.isLocked)
                
                TextField("Name", text: $frame.name)
                    .focused($activeField, equals: .name)
                    .disabled(frame.isLocked)
                
                TextField("Note", text: $frame.note, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($activeField, equals: .note)
                    .disabled(frame.isLocked)
            }
            
            Section(header: Text("Location")) {
                if requestingLocation {
                    Text("Waiting for location...")
                        .foregroundColor(.secondary)
                } else if let loc = frame.location {
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
                .disabled(frame.isLocked || requestingLocation)

                HStack {
                    Text("Elevation")
                    Spacer()
                    if requestingLocation || frame.elevation == 0 {
                        Text("-")
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 0) {
                            TextField("", value: $frame.elevation, formatter: elevationFormatter)
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
                    if requestingLocation || frame.elevation == 0 {
                        Text("-")
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 0) {
                            TextField("", value: $frame.colorTemperature, formatter: colorTemperatureFormatter)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($activeField, equals: .colorTemperature)
                                .disabled(frame.isLocked)
                            Text("K")
                        }
                    }
                }
            }
            
            Section(header: Text("Camera")) {
                Picker("F-Stop", selection: $frame.fstop) {
                    ForEach(CameraOptions.fStops, id: \.label) { item in
                        Text(item.label).tag(item.value)
                    }
                }
                .disabled(frame.isLocked)
                
                Picker("Shutter", selection: $frame.shutter) {
                    ForEach(CameraOptions.shutterSpeeds, id: \.label) { item in
                        Text(item.label).tag(item.value)
                    }
                }
                .disabled(frame.isLocked)
                
                Picker("Compensation", selection: $frame.exposureCompensation) {
                    ForEach(["-3", "-2", "-1", "0", "+1", "+2", "+3"], id: \.self) { value in
                        Text("EV\(value)").tag(value)
                    }
                }
                .disabled(frame.isLocked)
            }
            
            Section(header: Text("Lens")) {
                Picker("Lens", selection: $frame.lensName) {
                    ForEach(CameraOptions.lensNames, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .disabled(frame.isLocked)
                
                Picker("Focal length", selection: $frame.lensFocalLength) {
                    ForEach(CameraOptions.focalLengths, id: \.label) { item in
                        Text(item.label).tag(item.value)
                    }

                }
                .disabled(frame.isLocked)
                
                HStack {
                    Text("Focus Distance")
                    Spacer()

                    HStack(spacing: 2) {
                        TextField("", value: $frame.focusDistance, formatter: focusDistanceFormatter)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($activeField, equals: .focusDistance)
                            .disabled(frame.isLocked)
                        Text("mm")
                    }
                }
                
                HStack {
                    Text("Depth of field")
                    Spacer()

                    HStack(spacing: 2) {
                        TextField("", value: $frame.focusDepthOfField, formatter: focusDistanceFormatter)
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
                        TextField("", value: $frame.focusNearLimit, formatter: focusDistanceFormatter)
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
                        TextField("", value: $frame.focusFarLimit, formatter: focusDistanceFormatter)
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
                        TextField("", value: $frame.focusHyperfocalDistance, formatter: focusDistanceFormatter)
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
                    data: frame.lightMeterImage?.data,
                    label: "Add photo",
                    isLocked: frame.isLocked
                ) { newData in
                    replaceImage(for: &frame.lightMeterImage, with: newData)
                }
                
                evPicker(title: "Sky", selection: $frame.exposureSky)
                evPicker(title: "Foliage", selection: $frame.exposureFoliage)
                evPicker(title: "Highlights", selection: $frame.exposureHighlights)
                evPicker(title: "Mid gray", selection: $frame.exposureMidGray)
                evPicker(title: "Shadows", selection: $frame.exposureShadows)
                evPicker(title: "Skin key", selection: $frame.exposureSkinKey)
                evPicker(title: "Skin fill", selection: $frame.exposureSkinFill)
            }
            
            Section {
                Button(action: {
                    showDialog = true
                }) {
                    Label("Next frame", systemImage: "film")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .listRowBackground(Color.clear)
                .confirmationDialog("Choose an option", isPresented: $showDialog) {
                    Button("Add one frame") {
                        createNextFrame(count: 1)
                        dismiss()
                    }
                    Button("Add 2 frames") {
                        createNextFrame(count: 2)
                        dismiss()
                    }
                    Button("Add 5 frames") {
                        createNextFrame(count: 5)
                        dismiss()
                    }
                    Button("Add 10 frames") {
                        createNextFrame(count: 10)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .navigationTitle("Frame \(index + 1) of \(count)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            locationManager.currentLocation = nil
            if frame.location == nil {
                frame.elevation = 0
                frame.colorTemperature = 0
            }
            updateDof()
        }
        .onChange(of: frame.focusDistance) { _, _ in updateDof() }
        .onChange(of: frame.fstop) { _, _ in updateDof() }
        .onChange(of: frame.lensFocalLength) { _, _ in updateDof() }
        .onReceive(locationManager.$currentLocation) { location in
            if requestingLocation, let location = location {
                frame.location = LocationOptions.Location(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    altitude: location.altitude
                )
                frame.elevation = frame.location?.elevation(for: Date()) ?? 0
                frame.colorTemperature = frame.location?.colorTemperature(for: Date()) ?? 0
                requestingLocation = false
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: { frame.isLocked.toggle() }) {
                    Image(systemName: frame.isLocked ? "lock.fill" : "lock.open")
                }
                .help(frame.isLocked ? "Unlock to edit frame info" : "Lock to prevent editing")
                
                if count > 1 {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete this frame")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Button("Done") { activeField = nil }
            }
        }
        .alert("Are you sure?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                withAnimation {
                    cleanupImage(frame.photoImage)
                    cleanupImage(frame.lightMeterImage)
                    modelContext.delete(frame)
                    onDelete?()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if index == count - 1 {
                Text("This frame contains associated data. Are you sure you want to delete it?")
            } else {
                Text("Deleting this frame will change the frame order. Are you sure you want to proceed?")
            }
        }
    }

    private func createNextFrame(count: Int) {
        for _ in 0..<count {
            let newFrame = frame.copy()
            newFrame.roll = roll
            modelContext.insert(newFrame)
            roll.frames.append(newFrame)
        }
    }
    
    private func openInMaps(latitude: Double, longitude: Double) {
        if let url = URL(string: "http://maps.apple.com/?ll=\(latitude),\(longitude)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func updateDof() {
        guard frame.focusDistance > 0 else {
            frame.focusDepthOfField = 0
            return
        }
        
        guard let filmSize = CameraOptions.filmSizes.first(where: { $0.label == frame.filmSize })?.value,
              let aperture = CameraOptions.fStops.first(where: { $0.label == frame.fstop })?.value,
              let focalLength = CameraOptions.focalLengths.first(where: { $0.label == frame.lensFocalLength })?.value else {
            frame.focusDepthOfField = 0
            return
        }
        
        let result = filmSize.focusDepthOfField(
            focalLength: focalLength,
            aperture: aperture,
            focusDistance: frame.focusDistance
        )
        
        frame.focusDepthOfField = result.dof.isInfinite ? -1.0 : result.dof
        frame.focusNearLimit = result.near
        frame.focusFarLimit = result.far
        frame.focusHyperfocalDistance = result.hyperfocal
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
        .disabled(frame.isLocked)
    }
}
