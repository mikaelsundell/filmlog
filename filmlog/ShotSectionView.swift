import SwiftUI

struct PhotoMetadataView: View {
    var camera: String = "Leica M6"
    var lens: String = "Summicron 50 mm"
    var aperture: String = "ƒ2.8"
    var shutter: String = "1/125 s"
    var iso: String = "ISO 400"

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Text(camera)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 6) {
                Text(lens)
                Text("· \(aperture)")
                Text("· \(shutter)")
                Text("· \(iso)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.1))
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

struct ShotSectionView: View {
    @Bindable var shot: Shot
    var isLocked: Bool = false
    var onImagePicked: (UIImage) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var showCamera = false
    @State private var showFullImage = false
    @State private var showDeleteAlert = false
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.9))
                    .overlay(
                        Rectangle()
                            .stroke(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                    )

                if let uiImage = shot.imageData?.thumbnail {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .padding(6) // 👈 inner gap between image and black base
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                        .onTapGesture { showFullImage = true }
                } else {
                    Text("No image")
                        .foregroundColor(.secondary)
                        .padding(6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .cornerRadius(0)
            .clipped()

            PhotoMetadataView()

            if !isLocked {
                HStack(spacing: 20) {
                    Button {
                        showCamera = true
                    } label: {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.accentColor)
                                    .offset(y: -1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showDeleteAlert = true
                    } label: {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.accentColor)
                            )
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
