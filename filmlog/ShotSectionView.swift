import SwiftUI

struct ShotSectionView: View {
    @Bindable var shot: Shot
    var isLocked: Bool = false
    var onImagePicked: (UIImage) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var showCamera = false
    @State private var showFullImage = false
    @State private var showDeleteAlert = false
    
    var body: some View {
        VStack(spacing: 8) {
            // --- Image preview ---
            if let uiImage = shot.imageData?.thumbnail {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black)
                        .frame(height: 180)

                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .onTapGesture {
                    showFullImage = true
                }

                // --- Metadata (like Photos app) ---
                VStack(spacing: 4) {
                    // First line — camera + lens info
                    HStack(spacing: 6) {
                        if !shot.lens.isEmpty {
                            Text(shot.lens)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        //if shot.focalLength > 0 {
                            Text("\(Int(shot.focalLength)) mm")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        //}
                        //if shot.aperture > 0 {
                            Text("ƒ\(String(format: "%.1f", shot.aperture))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        //}
                        /*if shot.shutter > 0 {
                            Text("\(ShotFormatUtils.shutterString(from: shot.shutter)) s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }*/
                        //if shot.iso > 0 {
                        Text("ISO \(Int(shot.aperture))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        ///}
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 180)
                    .overlay(Text("No image").foregroundColor(.gray))
                    .cornerRadius(10)
            }

            // --- Camera buttons ---
            if !isLocked {
                HStack(spacing: 20) {
                    Button {
                        showCamera = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: "camera.fill") // use filled variant
                                .foregroundColor(Color.accentColor) // blue tint
                                .font(.system(size: 22, weight: .medium))
                                .offset(y: -2)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showDeleteAlert = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: "trash.fill") // filled variant
                                .foregroundColor(Color.accentColor) // blue tint
                                .font(.system(size: 22, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .alert("Delete this shot?", isPresented: $showDeleteAlert) {
                        Button("Delete", role: .destructive) {
                            onDelete?()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This action cannot be undone.")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            ShotViewfinderView(shot: shot) { image in
                onImagePicked(image)
            }
        }
        .fullScreenCover(isPresented: $showFullImage) {
            ShotImageView(shot: shot)
        }
    }
}
