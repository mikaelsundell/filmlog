// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
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
