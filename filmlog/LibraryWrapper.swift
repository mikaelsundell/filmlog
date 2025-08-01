// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import PhotosUI

struct LibraryWrapper: View {
    @Binding var selectedItem: PhotosPickerItem?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Text("Select a photo")
                .onAppear {
                    // PhotosPicker auto-presents itself on appear
                }
        }
    }
}
